using Gurobi
using Ipopt
using JuMP
using PowerModels

## solve unit commitment problem

include("unit_commitment_functions.jl")

time_horizon = 24
reserve_requirment = 0.2
energy_not_served_cost = 10000.0

opt = Gurobi.Optimizer

## test data example
data = parse_file("pglib_opf_case3_lmbd.m")
data["gen"]["1"]["ramp_30"] = 2.0
data["gen"]["2"]["ramp_30"] = 4.0
data["gen"]["3"]["ramp_30"] = 2.0

data["gen"]["1"]["startup"] = 1000.0
data["gen"]["2"]["startup"] = 2000.0
data["gen"]["3"]["startup"] = 1500.0

data["gen"]["1"]["shutdown"] = 1000.0
data["gen"]["2"]["shutdown"] = 2000.0
data["gen"]["3"]["shutdown"] = 1500.0


data["gen"]["1"]["minup"] = 4
data["gen"]["2"]["minup"] = 2
data["gen"]["3"]["minup"] = 1

data["gen"]["1"]["mindown"] = 4
data["gen"]["2"]["mindown"] = 2
data["gen"]["3"]["mindown"] = 1

data["option"] = Dict("reserve_requirment" => reserve_requirment, "energy_not_served_cost" => energy_not_served_cost)
data_mp = PowerModels.replicate(data, time_horizon)

result = solve_uc(data_mp, opt; multinetwork=true)