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

file_path = "/Users/hannakhor/Library/CloudStorage/OneDrive-GeorgiaInstituteofTechnology/BTE_Model/BreakthroughEnergyGrid to PowerMod Code/Bus Data + Scripts/"
## CHANGE DATE: latest you can pick is december 31 hour 0
## DATE: Must be stored in these 3 variables
day = 1 ## day: 1-31
hour = 0 ## hour: 0-23
month = 7 ## month: 1-12
time_horizon = 24 ## Horizon is it will run 24 hours from the hour you pick
percentage = 30 ## percentage of EV in the total cars
data = read_GA_data(file_path, month, day, hour, time_horizon)

# Record starting time
start_time = time()
## Step 1: Solve UC problems for every day seperately 
gen_status = Dict()
for day in 1:30 # loop through the days and solve multiperiod dcopf problems

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

    ## Save the previous day status
    ug_prev_day, vg_prev_day, wg_prev_day = save_uc_results(data, day, gen_status)
end

## Step 2: Solve DCOPF problems for every day seperately
gen_output = Dict()
for day in 1:30 # loop through the days and solve multiperiod dcopf problems

    println("day $day")
    data = read_GA_data(file_path, month, day, hour, time_horizon)

    ## Add generator status 
    for nw in keys(data["nw"])
        for (i, gen) in data["nw"][nw]["gen"]
            gen["gen_status"] = gen_status[day][i][parse(Int64, nw)]
        end
    end
    
    ## Solve OPF problem
    result = solve_mp_opf_ramp(data, DCPPowerModel, opt; multinetwork=true)

    ## Extract the generators output
    gen_output[day] = Dict(idx =>[haskey(result["solution"]["nw"]["$i"]["gen"], idx) ? result["solution"]["nw"]["$i"]["gen"][idx]["pg"] : 0.0  for i in 1:24] for idx in keys(data["nw"]["1"]["gen"]) )
end

# Calculate training time
calculation_time = time() - start_time
println("Solving time: $calculation_time seconds")

# Arrange the generation results 
gens_data = Dict()
timestamps = [DateTime(2021, month, day, hour, 0, 0) for hour in 0:23, day in 1:30]
timestamps = reshape(timestamps, 1, :)
gens_data[Date] = timestamps
for g in keys(data["nw"]["1"]["gen"])
    gens_pg = []
    for day in 1:30
        append!(gens_pg, gen_output[day][g])
    end
    gens_data[g] = Dict("id"=> data["nw"]["1"]["gen"][g]["source_id"][2], "type" => data["nw"]["1"]["gen"][g]["type"], "bus"=> data["nw"]["1"]["bus"]["$(data["nw"]["1"]["gen"][g]["gen_bus"])"]["source_id"][2], "output" => gens_pg)
end

# save the final generation results to a JSON file
open("results/generator_outputs_for_June_at_30_percent_EV_penetration.json","w") do f 
    JSON.print(f, gens_data) 
end

# save the final generation results to a CSV file
df = DataFrame(Date = vec(gens_data[Date]))
for g in keys(gens_data)
    if g!= Date
        df[!, g] = gens_data[g]["output"]
    end
end

CSV.write("results/generator_outputs_for_June_at_30_percent_EV_penetration.csv", df, header=true)

filtered_gen = CSV.read("$file_path/filtered_gen.csv", DataFrame)
count = 0
for i in 1:length(filtered_gen[!, "plant_id"])
    
    for g in keys(data["nw"]["1"]["gen"])
        if filtered_gen[i, "plant_id"] == data["nw"]["1"]["gen"][g]["plant_id"]
            data["nw"]["1"]["gen"][g]["lat"] = filtered_gen[i, "lat"]
            data["nw"]["1"]["gen"][g]["lon"] = filtered_gen[i, "lon"]
            count = count+1
        end
    end
    display(count)
end
for g in keys(data["nw"]["1"]["gen"])
    if !haskey(data["nw"]["1"]["gen"][g], "lat")
        data["nw"]["1"]["gen"][g]["lat"] = "NA"
        data["nw"]["1"]["gen"][g]["lon"] = "NA"
    end
end
generator_data = ["plant_id", "type", "county_name", "zone_id", "lat", "lon"]
df = DataFrame()
for g in keys(data["nw"]["1"]["gen"])
    # if data["nw"]["1"]["gen"][g]["type"] == "coal" || data["nw"]["1"]["gen"][g]["type"] == "dfo" || data["nw"]["1"]["gen"][g]["type"] == "ng" || data["nw"]["1"]["gen"][g]["type"] == "hydro" || data["nw"]["1"]["gen"][g]["type"] == "nuclear" || data["nw"]["1"]["gen"][g]["type"] == "wind" || data["nw"]["1"]["gen"][g]["type"] == "solar"
        df[!, g] = [data["nw"]["1"]["gen"][g][key] for key in generator_data]
    # end
end

CSV.write("results/full_generator_data.csv", df, header = true)

