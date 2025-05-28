## Overview:
## This script is divided into three parts:
## After loading the packages, you can solve any of the scenrios,ie copplerplate, DCOPF or UC problems. 
## You save the dispaches and analyse the results afterwards.
## Make sure to open this file inside the MULTIPERIOD_OPTIMIZATION folder 

using PowerModels
using CSV
using DataFrames
using Gurobi
using JSON
using Dates
using Plots
# using Statistics

include("unit_commitment_functions.jl")
include("multiperiod_opf_functions.jl")
include("opf_violation_functions.jl") 
include("saving_prev_day_uc.jl")

include("read_GA_data_v2.jl") ## version 2 uses the Econ data as opposed to the NREL data
# include("read_GA_data.jl")

## Step 0: Initilize the parameters, options, and files path 
opt = Gurobi.Optimizer
reserve_requirment = 0.2
energy_not_served_cost = 10000.0

file_path = "/Users/rasiamah3/Library/CloudStorage/OneDrive-GeorgiaInstituteofTechnology/BTE_Model/BreakthroughEnergyGrid to PowerMod Code/Bus Data + Scripts/"
## CHANGE DATE: latest you can pick is december 31 hour 0
## DATE: Must be stored in these 3 variables
day = 1 ## day: 1-31
hour = 0 ## hour: 0-23
month = 7 ## month: 1-12  ### The month is set to July
time_horizon = 24 ## Horizon is it will run 24 hours from the hour you pick
global future_year = 2032
percentage = 1
data = read_GA_data(file_path, month, day, hour, time_horizon)

#### Read the NREL EV demand data to generate the demand profiles
# nrel_data = CSV.read("$file_path/aggregatedCounties.csv", DataFrame)
# counties = ["Appling", "Atkinson", "Bacon", "Baker", "Baldwin", "Banks", "Barrow", "Bartow", "Ben Hill", "Berrien", "Bibb", "Bleckley", "Brantley", "Brooks", "Bryan", "Bulloch", "Burke", "Butts", "Calhoun", "Camden", "Candler", "Carroll", "Catoosa", "Charlton", "Chatham", "Chattahoochee", "Chattooga", "Cherokee", "Clarke", "Clay", "Clayton", "Clinch", "Cobb", "Coffee", "Colquitt", "Columbia", "Cook", "Coweta", "Crawford", "Crisp", "Dade", "Dawson", "DeKalb", "Decatur", "Dodge", "Dooly", "Dougherty", "Douglas", "Early", "Echols", "Effingham", "Elbert", "Emanuel", "Evans", "Fannin", "Fayette", "Floyd", "Forsyth", "Franklin", "Fulton", "Gilmer", "Glascock", "Glynn", "Gordon", "Grady", "Greene", "Gwinnett", "Habersham", "Hall", "Hancock", "Haralson", "Harris", "Hart", "Heard", "Henry", "Houston", "Irwin", "Jackson", "Jasper", "Jeff Davis", "Jefferson", "Jenkins", "Johnson", "Jones", "Lamar", "Lanier", "Laurens", "Lee", "Liberty", "Lincoln", "Long", "Lowndes", "Lumpkin", "McDuffie", "McIntosh", "Macon", "Madison", "Marion", "Meriwether", "Miller", "Mitchell", "Monroe", "Montgomery", "Morgan", "Murray", "Muscogee", "Newton", "Oconee", "Oglethorpe", "Paulding", "Peach", "Pickens", "Pierce", "Pike", "Polk", "Pulaski", "Putnam", "Quitman", "Rabun", "Randolph", "Richmond", "Rockdale", "Schley", "Screven", "Seminole", "Spalding", "Stephens", "Stewart", "Sumter", "Talbot", "Taliaferro", "Tattnall", "Taylor", "Telfair", "Terrell", "Thomas", "Tift", "Toombs", "Towns", "Treutlen", "Troup", "Turner", "Twiggs", "Union", "Upson", "Walker", "Walton", "Ware", "Warren", "Washington", "Wayne", "Webster", "Wheeler", "White", "Whitfield", "Wilcox", "Wilkes", "Wilkinson", "Worth"]
# points = []
# ev_demand = Dict()
# for hour in 0:23
#     ev_demand[hour] = Dict()
#     for county in counties
#         points = []
#         ev_demand[hour][county] = Dict()
#         for x in eachrow(nrel_data)
#             for i in 0:6
#                 if x.geography == county && x.day_of_week == i && x.month == 1 && x.hour == hour # assume the shape for the different months are the same
#                     push!(points, x.Load)
#                     if i == 6
#                         ev_demand[hour][county] = points
#                     end               
#                 end
#             end
#         end
#     end
# end

# ## Normalize the EV demand profiles
# for county in counties
#     display(county)
#     all_values = []
#     for hour in 0:23
#         append!(all_values, ev_demand[hour][county])
#     end
#     display(all_values)
#     for hour in 0:23
#         ev_demand[hour][county] = ev_demand[hour][county]./maximum(all_values)
#         # ev_demand[hour][county] = ev_demand[hour][county]./mean(all_values)
#     end
# end

weekly_total = Dict()
for county in counties
    sum_values = []
    for hour in 0:23
        sum_values = append!(sum_values, ev_demand[hour][county])
    end
    display(sum_values)
    weekly_total[county] = sum(sum_values)
end

# #Save the ev_demand as a JSON file
JSON.open("ev_demand.json", "w") do file
    JSON.print(file, ev_demand)
end

## Save the ev_demand as a JSON file
JSON.open("results/weekly_total.json", "w") do file
    JSON.print(file, weekly_total)
end


###  Load the ev_demand from the JSON file
global ev_demand_loaded = Dict()
JSON.open("ev_demand.json") do file
    ev_demand_loaded = JSON.parse(file)
end
global weekly_total = Dict()
JSON.open("results/weekly_total.json") do file
    weekly_total = JSON.parse(file)
end

start = time()

# Scenarios 1 and 2: the Copperplate models
# This is the DC model but all the line limit constraints are removed.
gen_output = Dict()
for day in 1:31 # loop through the days and solve multiperiod dcopf problems

    println("day $day")
    data = read_GA_data(file_path, month, day, hour, time_horizon)

    for hour in 1:24
        total_load = sum(data["nw"]["$hour"]["load"][l]["pd"] for l in keys(data["nw"]["1"]["load"]))
        total_gen = sum(data["nw"]["$hour"]["gen"][g]["pmax"] for g in keys(data["nw"]["1"]["gen"]))
        println("Total Load: ", total_load)
        println("Total Generation: ", total_gen)
    end
    
    ## Relax the line limits
    for nw in keys(data["nw"])
        for b in keys(data["nw"][nw]["branch"])
            data["nw"][nw]["branch"][b]["rate_a"] = data["nw"][nw]["branch"][b]["rate_a"] * 10e6
            data["nw"][nw]["branch"][b]["rate_b"] = data["nw"][nw]["branch"][b]["rate_b"] * 10e6
            data["nw"][nw]["branch"][b]["rate_c"] = data["nw"][nw]["branch"][b]["rate_c"] * 10e6

        end
    end

    ### Printing this to make sure that the total load does not exceed the total generation capacity on any day.
    ### Spoiler alert! This is violated on day 8. Probably a couple more as well.
    for hour in 1:24
        total_load = sum(data["nw"]["$hour"]["load"][l]["pd"] for l in keys(data["nw"]["1"]["load"]))
        total_gen = sum(data["nw"]["$hour"]["gen"][g]["pmax"] for g in keys(data["nw"]["1"]["gen"]))
        println("Total Load: ", total_load)
        println("Total Generation: ", total_gen)
    end

    ## Solve OPF problem
    result = solve_mp_opf_ramp(data, DCPPowerModel, opt; multinetwork=true)

    ## Extract the generators output
    gen_output[day] = Dict(idx =>[haskey(result["solution"]["nw"]["$i"]["gen"], idx) ? result["solution"]["nw"]["$i"]["gen"][idx]["pg"] : 0.0  for i in 1:24] for idx in keys(data["nw"]["1"]["gen"]) )
end


## Scenarios 3 and 4: Solve DCOPF problems for every day seperately
gen_output = Dict()
for day in 1:31 # loop through the days and solve multiperiod dcopf problems

    println("day $day")
    data = read_GA_data(file_path, month, day, hour, time_horizon)

    # # ## Add generator status 
    # for nw in keys(data["nw"])
    #     for (i, gen) in data["nw"][nw]["gen"]
    #         gen["gen_status"] = gen_status[day][i][parse(Int64, nw)]
    #     end
    # end

    ### Printing this to make sure that the total load does not exceed the total generation capacity on any day.
    ### Spoiler alert! This is violated on day 8. Probably a couple more as well.
    for hour in 1:24
        total_load = sum(data["nw"]["$hour"]["load"][l]["pd"] for l in keys(data["nw"]["1"]["load"]))
        total_gen = sum(data["nw"]["$hour"]["gen"][g]["pmax"] for g in keys(data["nw"]["1"]["gen"]))
        println("Total Load: ", total_load)
        println("Total Generation: ", total_gen)
    end

    ## Solve OPF problem
    result = solve_mp_opf_ramp(data, DCPPowerModel, opt; multinetwork=true)

    ## Extract the generators output
    gen_output[day] = Dict(idx =>[haskey(result["solution"]["nw"]["$i"]["gen"], idx) ? result["solution"]["nw"]["$i"]["gen"][idx]["pg"] : 0.0  for i in 1:24] for idx in keys(data["nw"]["1"]["gen"]) )
end

## Scenarios 5 and 6: Solve UC problems for every day seperately 
gen_status = Dict()
uc_results = Dict()
for day in 1:31 # loop through the days and solve multiperiod dcopf problems

    println("This is day $day")
    data = read_GA_data(file_path, month, day, hour, time_horizon)

    ## Add reserve requirments and ENS cost
    for nw in keys(data["nw"])
        data["nw"][nw]["option"] = Dict("reserve_requirment" => reserve_requirment, "energy_not_served_cost" => energy_not_served_cost)
    end
    
    if day > 1
        for i in 1:24
            for gen in keys(data["nw"]["1"]["gen"])
                data["nw"]["$i"]["gen"][gen]["vg_prev_day"] = vg_prev_day[gen][i]
                data["nw"]["$i"]["gen"][gen]["wg_prev_day"] = wg_prev_day[gen][i]
            end
        end
    end

    ## Solve UC problem
    result = solve_uc(data, opt; multinetwork=true)

    ## Extract the generators status
    gen_status[day] = Dict(idx =>[result["solution"]["nw"]["$i"]["gen"][idx]["ug"]  for i in 1:24] for idx in keys(data["nw"]["1"]["gen"]) )
    uc_results[day] = Dict(idx =>[result["solution"]["nw"]["$i"]["gen"][idx]["pg"]  for i in 1:24] for idx in keys(data["nw"]["1"]["gen"]) )

    ## Save the previous day status
    global ug_prev_day, vg_prev_day, wg_prev_day = save_uc_results(data, day, gen_status)
end


end_time = time() - start
println("Time taken to read the data and solve the  problem: ", end_time, " seconds")

### Save the generation results for selected generators 
### These are the generators that Xin was interested in.
# indices = [
#     "199", "200", "201", "202", "203", "204", "80", "81", "82", "188", "189", "190", "127", "128", "129", "130",
#     "205", "206", "207", "208", "98", "99", "100", "101", "102", "103", "151", "152", "153", "154", "155", "156", "126",
#     "158", "159", "9", "10", "11", "12", "25", "26", "27", "28", "29", "250", "251", "5", "6", "75", "76", "77", "78", "149", "150",
#     "146", "147", "148", "160", "161", "162", "224", "225", "226", "227", "228", "229", "218", "219", "220", "221", "222", "223",
#     "2", "3", "176", "177", "178", "191", "192", "193", "194", "196", "197", "198", "244", "245", "246", "247", "248", "249"
# ]

# # Arrange the generation results 
# data = read_GA_data(file_path, month, day, hour, time_horizon)
# gens_data = Dict()
# timestamps = [DateTime(2021, month, day, hour, 0, 0) for hour in 0:23, day in 1:31]
# timestamps = reshape(timestamps, 1, :)
# gens_data[Date] = timestamps
# for g in keys(data["nw"]["1"]["gen"])
#     gens_pg = []
#     for day in 1:31
#         append!(gens_pg, gen_output[day][g])
#         # append!(gens_pg, uc_results[day][g])
#     end
#     gens_data[g] = Dict("id"=> data["nw"]["1"]["gen"][g]["source_id"][2], "type" => data["nw"]["1"]["gen"][g]["type"], "bus"=> data["nw"]["1"]["bus"]["$(data["nw"]["1"]["gen"][g]["gen_bus"])"]["source_id"][2], "output" => gens_pg)
# end

## Change the name depending on what scenario you are using.
### You change the Econ model in read_GA_data_v2.jl file.
# CSV.write("results/generator_outputs_Scenario_1.csv", df, header=true)


### This is for the analysis of the generation results.
# total_wind = []
# total_solar = []
# total_hydro = []
# total_coal = []
# total_ng = []
# total_dfo = []
# for g in keys(data["nw"]["1"]["gen"])
#     if gens_data[g]["type"] == "hydro"
#         total_hydro = append!(total_hydro, gens_data[g]["output"])
#     elseif gens_data[g]["type"] == "wind"
#         total_wind = append!(total_wind, gens_data[g]["output"])
#     elseif gens_data[g]["type"] == "solar"
#         total_solar = append!(total_solar, gens_data[g]["output"])
#     elseif gens_data[g]["type"] == "coal"
#         total_coal = append!(total_coal, gens_data[g]["output"])
#     elseif gens_data[g]["type"] == "ng"
#         total_ng = append!(total_ng, gens_data[g]["output"])
#     elseif gens_data[g]["type"] == "dfo"
#         total_dfo = append!(total_dfo, gens_data[g]["output"])
#     end
# end

# println("Total Hydro Generation: ", sum(total_hydro))
# println("Total Wind Generation: ", sum(total_wind))
# println("Total Solar Generation: ", sum(total_solar))
# println("Total Coal Generation: ", sum(total_coal))
# println("Total NG Generation: ", sum(total_ng))
# println("Total DFO Generation: ", sum(total_dfo))

# ## save the final generation results to a CSV file
# df = DataFrame(Date = vec(gens_data[Date]))
# for g in indices
#     if g!= Date
#         # display(gens_data[g]["output"])
#         df[!, Symbol(g)] = gens_data[g]["output"]
#     end
# end
