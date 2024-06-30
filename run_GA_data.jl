## Overview:
## This file sets up a Julia Dictionary with all necessary data to run PowerModel functions.
## Detailed below is how each element of the dictionary is built.
## For more information, look at the link below.
## https://lanl-ansi.github.io/PowerModels.jl/stable/network-data/#:~:text=PowerModels%20has%20extensive%20support%20for,illustrated%20by%20the%20following%20examples.

using PowerModels
using CSV
using DataFrames
using Gurobi

include("unit_commitment_functions.jl")
include("multiperiod_opf_functions.jl")
include("opf_violation_functions.jl")
include("read_GA_data.jl")

opt = Gurobi.Optimizer
reserve_requirment = 0.2
energy_not_served_cost = 10000.0

## file_path is the folder which contains files and excel sheets for data.
## Use file_path to indicates the data location 
file_path = "/Users/mohannad/Library/CloudStorage/OneDrive-GeorgiaInstituteofTechnology/BTE_Model/BreakthroughEnergyGrid to PowerMod Code/Bus Data + Scripts/"
## CHANGE DATE: latest you can pick is december 31 hour 0
## DATE: Must be stored in these 3 variables
hour = 0 ## hour: 0-23
month = 1 ## month: 1-12
time_horizon = 24 ## Horizon is it will run 24 hours from the hour you pick

gen_output = Dict()
for day in 1:31 # loop through the days and solve multiperiod dcopf problems

    println("day $day")
    data = read_GA_data(file_path, month, day, hour, time_horizon)
    ## example for solving multiperiod OPF
    result = solve_mp_opf_ramp(data, DCPPowerModel, opt; multinetwork=true)
    gen_output[day] = Dict(idx =>[result["solution"]["nw"]["$i"]["gen"][idx]["pg"]  for i in 1:24] for idx in keys(data["nw"]["1"]["gen"]) )
end

# extract the generation results
gens_data = Dict()
for g in keys(data["nw"]["1"]["gen"])
    gens_pg = []
    for day in 1:31
        append!(gens_pg, gen_output[day][g])
    end
    gens_data[g] = Dict("id"=> data["nw"]["1"]["gen"][g]["source_id"][2], "type" => data["nw"]["1"]["gen"][g]["type"], "bus"=> data["nw"]["1"]["bus"]["$(data["nw"]["1"]["gen"][g]["gen_bus"])"]["source_id"][2], "output" => gens_pg)
end

# save the results 
open("simulation_july.json","w") do f 
    JSON.print(f, gens_data) 
end

# arranging the generation results
gens_ids = unique([gens_data[i]["bus"] for i in keys(gens_data)])

gens_data_new = Dict()
for i in gens_ids
    g_ids = findall(x -> x["bus"] == i, gens_data)
    if !isempty(g_ids)
        gens_data_new[i] = Dict("id"=> g_ids, "bus"=> i, "output" => sum(gens_data[j]["output"] for j in g_ids, dims =1))
    end
end

open("simulation_july_gen.json","w") do f 
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
open("simulation_july_load.json","w") do f 
    JSON.print(f, load_data) 
end

# calculate the total load of GA
ga_load = []
for h in 1:24
    append!(ga_load ,sum(load_data[i]["output"][h]*100 for i in keys(load_data)))
end


# plotting the hourly demand
xticks = [1:24]
ax = plot(1:24, ga_load,  lw=3, label ="")
xlabel!("Hour")
ylabel!("Demand (MW)")
plot!(xticks=([1,7,13,19],["12AM", "6AM", "12PM", "6PM"]))
xlims!((1,24))
savefig(ax,"ga_d.pdf")


########################################
# the code we used to generate the branch violations needed to make the problem feasiable
########################################
branch_vio = Dict()
for day in 1:31
    println("day $day")
    data = read_GA_data(file_path, month, day, hour, time_horizon)
    for h in 1:24
        d = data["nw"]["$h"]
        d["per_unit"] = true
        result = solve_opf_violation(d, DCPPowerModel ,opt)
        bus_shaded = Dict(idx => bus["nse"] for (idx, bus) in result["solution"]["bus"] if bus["nse"] > 0)
        branch_violation = Dict(idx => branch["sp"] + branch["sn"]  for (idx, branch) in result["solution"]["branch"] if branch["sp"] > 0 || branch["sn"] > 0)

        for (idx,val) in branch_violation
            if haskey(branch_vio, idx)
                branch_vio[idx] = maximum([branch_vio[idx], val])
            else
                branch_vio[idx] = val
            end
        end
    end
end 



########################################
## solve unit commitment problem (this code doesn't work yet, we need to fix it)
########################################
reserve_requirment = 0
for nw in keys(data["nw"])
    data["nw"][nw]["option"] = Dict("reserve_requirment" => reserve_requirment, "energy_not_served_cost" => energy_not_served_cost)
end

# example for solving unit commitment problem
result = solve_uc(data, opt; multinetwork=true)
# pm = PowerModels.instantiate_model(data_mp, DCPPowerModel, build_mn_uc);

# result = solve_mp_opf_ramp(data_mp, ACPPowerModel, Ipopt.Optimizer; multinetwork=true)
