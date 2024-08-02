## Overview:
## This script reads GA data, solves UC problem, solves DCOPF problem, and save the generators dispaches
## Make sure to open this file inside the MULTIPERIOD_OPTIMIZATION folder 

using PowerModels
using CSV
using DataFrames
using Gurobi
using JSON

include("unit_commitment_functions.jl")
include("multiperiod_opf_functions.jl")
include("opf_violation_functions.jl")
include("read_GA_data.jl")



## Step 0: Initilize the parameters, options, and files path 

opt = Gurobi.Optimizer
reserve_requirment = 0.2
energy_not_served_cost = 10000.0

file_path = "/Users/mohannad/Library/CloudStorage/OneDrive-GeorgiaInstituteofTechnology/BTE_Model/BreakthroughEnergyGrid to PowerMod Code/Bus Data + Scripts/"
## CHANGE DATE: latest you can pick is december 31 hour 0
## DATE: Must be stored in these 3 variables
hour = 0 ## hour: 0-23
month = 1 ## month: 1-12
time_horizon = 24 ## Horizon is it will run 24 hours from the hour you pick


## Step 1: Solve UC problems for every day seperatlly 
## TODO: initialize UC problems using the previous day solution via (1) including initial values fields for the generators status and up time, and (2) modifying the minimum up/down time constraints 

gen_status = Dict()
for day in 1:31 # loop through the days and solve multiperiod dcopf problems

    println("day $day")
    data = read_GA_data(file_path, month, day, hour, time_horizon)

    ## Add reserve requirments and ENS cost
    for nw in keys(data["nw"])
        data["nw"][nw]["option"] = Dict("reserve_requirment" => reserve_requirment, "energy_not_served_cost" => energy_not_served_cost)
    end
    
    ## Solve UC problem
    result = solve_uc(data, opt; multinetwork=true)

    ## Extract the generators status
    gen_status[day] = Dict(idx =>[result["solution"]["nw"]["$i"]["gen"][idx]["ug"]  for i in 1:24] for idx in keys(data["nw"]["1"]["gen"]) )
end

gen_output = Dict()
for day in 1:31 # loop through the days and solve multiperiod dcopf problems

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

# Arrange the generation results 
gens_data = Dict()
for g in keys(data["nw"]["1"]["gen"])
    gens_pg = []
    for day in 1:31
        append!(gens_pg, gen_output[day][g])
    end
    gens_data[g] = Dict("id"=> data["nw"]["1"]["gen"][g]["source_id"][2], "type" => data["nw"]["1"]["gen"][g]["type"], "bus"=> data["nw"]["1"]["bus"]["$(data["nw"]["1"]["gen"][g]["gen_bus"])"]["source_id"][2], "output" => gens_pg)
end



# save the results 
open("simulation_july_no_ev.json","w") do f 
    JSON.print(f, gens_data) 
end

# arranging the generation results via summing the generators power outputs in each bus
gens_ids = unique([gens_data[i]["bus"] for i in keys(gens_data)])

gens_data_new = Dict()
for i in gens_ids
    g_ids = findall(x -> x["bus"] == i, gens_data)
    if !isempty(g_ids)
        gens_data_new[i] = Dict("id"=> g_ids, "bus"=> i, "output" => sum(gens_data[j]["output"] for j in g_ids, dims =1))
    end
end

open("simulation_july_gen_no_ev.json","w") do f 
    JSON.print(f, gens_data_new) 
end

# extract the demand data
load_data = Dict()
data = read_GA_data(file_path, 7, 1, 0, 24*31)
for l in keys(data["nw"]["1"]["load"])
    loads_pd = []
    c = 1
    for day in 1:31
        
        for hour in 1:24
            append!(loads_pd, data["nw"]["$c"]["load"][l]["pd"])
            c += 1
        end
    end
    load_data[data["nw"]["1"]["load"][l]["source_id"][2]] = Dict("id"=> l, "bus"=> data["nw"]["1"]["bus"]["$(data["nw"]["1"]["load"][l]["load_bus"])"]["source_id"][2], "output" => loads_pd)
end

open("simulation_july_load_no_ev.json","w") do f 
    JSON.print(f, load_data) 
end