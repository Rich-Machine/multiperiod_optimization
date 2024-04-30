using Gurobi
using Ipopt
using JuMP
using PowerModels

## solve unit commitment problem

include("unit_commitment_functions.jl")
include("multiperiod_opf_functions.jl")
include("opf_violation_functions.jl")

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

# example for solving unit commitment problem
result = solve_uc(data_mp, opt; multinetwork=true)
# pm = PowerModels.instantiate_model(data_mp, DCPPowerModel, build_mn_uc)

## example for solving multiperiod OPF
result = solve_mp_opf_ramp(data_mp, DCPPowerModel, opt; multinetwork=true)
# pm = PowerModels.instantiate_model(data_mp, DCPPowerModel, build_mn_opf_ramp)

## example for finding line limit violations

data["branch"]["1"]["rate_a"] = 0 
data["branch"]["2"]["rate_a"] = 0 
data["branch"]["3"]["rate_a"] = 0 
result = solve_opf_violation(data, DCPPowerModel ,opt)
# pm = PowerModels.instantiate_model(data, DCPPowerModel,build_opf_violation)