## Overview:
## This script reads GA data, solves UC problem, solves DCOPF problem, and save the generators dispaches
## Make sure to open this file inside the MULTIPERIOD_OPTIMIZATION folder 

using PowerModels
using CSV
using DataFrames
using Gurobi
using JSON
using Dates

include("unit_commitment_functions.jl")
include("multiperiod_opf_functions.jl")
include("opf_violation_functions.jl")
include("read_GA_data_v2.jl")
include("saving_prev_day_uc.jl")

## Step 0: Initilize the parameters, options, and files path 
opt = Gurobi.Optimizer
reserve_requirment = 0.2
energy_not_served_cost = 10000.0

file_path = "/Users/rasiamah3/Library/CloudStorage/OneDrive-GeorgiaInstituteofTechnology/BTE_Model/BreakthroughEnergyGrid to PowerMod Code/Bus Data + Scripts/"
## CHANGE DATE: latest you can pick is december 31 hour 0
## DATE: Must be stored in these 3 variables
day = 1 ## day: 1-31
hour = 0 ## hour: 0-23
month = 7 ## month: 1-12
time_horizon = 24 ## Horizon is it will run 24 hours from the hour you pick
global future_year = 2026

# Record starting time
start_time = time()
display("Reading EV data")
nrel_data = CSV.read("$file_path/aggregatedCounties.csv", DataFrame)
counties = ["Appling", "Atkinson", "Bacon", "Baker", "Baldwin", "Banks", "Barrow", "Bartow", "Ben Hill", "Berrien", "Bibb", "Bleckley", "Brantley", "Brooks", "Bryan", "Bulloch", "Burke", "Butts", "Calhoun", "Camden", "Candler", "Carroll", "Catoosa", "Charlton", "Chatham", "Chattahoochee", "Chattooga", "Cherokee", "Clarke", "Clay", "Clayton", "Clinch", "Cobb", "Coffee", "Colquitt", "Columbia", "Cook", "Coweta", "Crawford", "Crisp", "Dade", "Dawson", "De Kalb", "Decatur", "Dodge", "Dooly", "Dougherty", "Douglas", "Early", "Echols", "Effingham", "Elbert", "Emanuel", "Evans", "Fannin", "Fayette", "Floyd", "Forsyth", "Franklin", "Fulton", "Gilmer", "Glascock", "Glynn", "Gordon", "Grady", "Greene", "Gwinnett", "Habersham", "Hall", "Hancock", "Haralson", "Harris", "Hart", "Heard", "Henry", "Houston", "Irwin", "Jackson", "Jasper", "Jeff Davis", "Jefferson", "Jenkins", "Johnson", "Jones", "Lamar", "Lanier", "Laurens", "Lee", "Liberty", "Lincoln", "Long", "Lowndes", "Lumpkin", "Mcduffie", "Mcintosh", "Macon", "Madison", "Marion", "Meriwether", "Miller", "Mitchell", "Monroe", "Montgomery", "Morgan", "Murray", "Muscogee", "Newton", "Oconee", "Oglethorpe", "Paulding", "Peach", "Pickens", "Pierce", "Pike", "Polk", "Pulaski", "Putnam", "Quitman", "Rabun", "Randolph", "Richmond", "Rockdale", "Schley", "Screven", "Seminole", "Spalding", "Stephens", "Stewart", "Sumter", "Talbot", "Taliaferro", "Tattnall", "Taylor", "Telfair", "Terrell", "Thomas", "Tift", "Toombs", "Towns", "Treutlen", "Troup", "Turner", "Twiggs", "Union", "Upson", "Walker", "Walton", "Ware", "Warren", "Washington", "Wayne", "Webster", "Wheeler", "White", "Whitfield", "Wilcox", "Wilkes", "Wilkinson", "Worth"]
points = []
important_points = Dict()
for hour in 0:23
    important_points[hour] = Dict()
    for county in counties
        points = []
        important_points[hour][county] = Dict()
        for x in eachrow(nrel_data)
            for i in 0:6
                if x.geography == county && x.day_of_week == i && x.month == 1 && x.hour == hour # assume the shape for the different months are the same
                    push!(points, x.Load)
                    if i == 6
                        important_points[hour][county] = points./maximum(points)   
                    end               
                end
            end
        end
    end
end

## Step 1: Solve UC problems for every day seperately 
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
    ug_prev_day, vg_prev_day, wg_prev_day = save_uc_results(data, day, gen_status)
end

## Step 2: Solve DCOPF problems for every day seperately
# gen_output = Dict()
# for day in 1:31 # loop through the days and solve multiperiod dcopf problems

#     println("day $day")
#     data = read_GA_data(file_path, month, day, hour, time_horizon)

#     ## Add generator status 
#     for nw in keys(data["nw"])
#         for (i, gen) in data["nw"][nw]["gen"]
#             gen["gen_status"] = gen_status[day][i][parse(Int64, nw)]
#         end
#     end
    
#     ## Solve OPF problem
#     result = solve_mp_opf_ramp(data, DCPPowerModel, opt; multinetwork=true)

#     ## Extract the generators output
#     gen_output[day] = Dict(idx =>[haskey(result["solution"]["nw"]["$i"]["gen"], idx) ? result["solution"]["nw"]["$i"]["gen"][idx]["pg"] : 0.0  for i in 1:24] for idx in keys(data["nw"]["1"]["gen"]) )
# end

## Step 3: Save the generation results for selected generators
indices = [
    "199", "200", "201", "202", "203", "204", "80", "81", "82", "188", "189", "190", "127", "128", "129", "130",
    "205", "206", "207", "208", "98", "99", "100", "101", "102", "103", "151", "152", "153", "154", "155", "156", "126",
    "158", "159", "9", "10", "11", "12", "25", "26", "27", "28", "29", "250", "251", "5", "6", "75", "76", "77", "78", "149", "150",
    "146", "147", "148", "160", "161", "162", "224", "225", "226", "227", "228", "229", "218", "219", "220", "221", "222", "223",
    "2", "3", "176", "177", "178", "191", "192", "193", "194", "196", "197", "198", "244", "245", "246", "247", "248", "249"
]
# Arrange the generation results 
gens_data = Dict()
timestamps = [DateTime(2021, month, day, hour, 0, 0) for hour in 0:23, day in 1:31]
timestamps = reshape(timestamps, 1, :)
gens_data[Date] = timestamps
for g in keys(data["nw"]["1"]["gen"])
    gens_pg = []
    for day in 1:31
        # append!(gens_pg, gen_output[day][g])
        append!(gens_pg, uc_results[day][g])
    end
    gens_data[g] = Dict("id"=> data["nw"]["1"]["gen"][g]["source_id"][2], "type" => data["nw"]["1"]["gen"][g]["type"], "bus"=> data["nw"]["1"]["bus"]["$(data["nw"]["1"]["gen"][g]["gen_bus"])"]["source_id"][2], "output" => gens_pg)
end

# save the final generation results to a CSV file
df = DataFrame(Date = vec(gens_data[Date]))
for g in indices
    if g!= Date
        df[!, g] = gens_data[g]["output"]
    end
end

CSV.write("results/generator_outputs_for_selected_generators.csv", df, header=true)
