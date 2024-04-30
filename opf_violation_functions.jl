using PowerModels
using JuMP

#################### solve function ####################
function solve_opf_violation(file, model_type::Type, solver; kwargs...)
    return solve_model(file, model_type, solver, build_opf_violation; kwargs...)
end

function build_opf_violation(pm::AbstractPowerModel)

    variable_bus_voltage(pm)
    variable_gen_power(pm)
    variable_branch_power_real_violation(pm)
    variable_dcline_power(pm)
    variable_branch_limit_slack(pm)

    
    constraint_model_voltage(pm)

    for i in ids(pm, :ref_buses)
        constraint_theta_ref(pm, i)
    end

    for i in ids(pm, :bus)
        constraint_power_balance(pm, i)
    end

    for i in ids(pm, :branch)
        constraint_ohms_yt_from(pm, i)
        constraint_ohms_yt_to(pm, i)

        constraint_voltage_angle_difference(pm, i)

        constraint_thermal_limit_from_violation(pm, i)
    end

    for i in ids(pm, :dcline)
        constraint_dcline_power_losses(pm, i)
    end

    objective_min_fuel_and_flow_cost_violation(pm)
end

function variable_branch_power_real_violation(pm::AbstractAPLossLessModels; nw::Int=nw_id_default, report::Bool=true)
    p = var(pm, nw)[:p] = JuMP.@variable(pm.model,
        [(l,i,j) in ref(pm, nw, :arcs_from)], base_name="$(nw)_p",
        start = comp_start_value(ref(pm, nw, :branch, l), "p_start")
    )


    # this explicit type erasure is necessary
    p_expr = Dict{Any,Any}( ((l,i,j), p[(l,i,j)]) for (l,i,j) in ref(pm, nw, :arcs_from) )
    p_expr = merge(p_expr, Dict( ((l,j,i), -1.0*p[(l,i,j)]) for (l,i,j) in ref(pm, nw, :arcs_from)))
    var(pm, nw)[:p] = p_expr

    report && sol_component_value_edge(pm, nw, :branch, :pf, :pt, ref(pm, nw, :arcs_from), ref(pm, nw, :arcs_to), p_expr)
end


function variable_branch_limit_slack(pm::AbstractPowerModel; nw::Int=nw_id_default, report::Bool=true)
    sp = var(pm)[:sp] = JuMP.@variable(pm.model,
        [i in ids(pm, :branch)],
        base_name="$(nw)_sp",
        lower_bound = 0.0,
        start = 0.0
    )

    sn = var(pm)[:sn] = JuMP.@variable(pm.model,
        [i in ids(pm, :branch)],
        base_name="$(nw)_sn",
        lower_bound = 0.0,
        start = 0.0
    )

    report && sol_component_value(pm, nw, :branch, :sp, ids(pm, nw, :branch), sp)
    report && sol_component_value(pm, nw, :branch, :sn, ids(pm, nw, :branch), sn)
end

function objective_min_fuel_and_flow_cost_violation(pm::AbstractPowerModel)
    
    s_cost_mw = 10000.0
    pg = var(pm)[:pg] 
    
    gen_cost = Dict()
    for (i,gen) in ref(pm, :gen)
        cost_terms = reverse(gen["cost"])
        gen_cost[i] = JuMP.@expression(pm.model, cost_terms[1] + cost_terms[2] * pg[i])
    end
    s_cost = sum(s_cost_mw .* var(pm, :sp) .+ s_cost_mw .* var(pm, :sn))

    return JuMP.@objective(pm.model, Min, sum(gen_cost[i] for i in ids(pm, :gen)) + s_cost)
end

function constraint_thermal_limit_from_violation(pm::AbstractPowerModel, i::Int; nw::Int=nw_id_default)
    branch = ref(pm, nw, :branch, i)
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)

    if haskey(branch, "rate_a")
        constraint_thermal_limit_from_violation(pm, nw, f_idx, branch["rate_a"])
    end
end


"nothing to do, this model is symetric"
function constraint_thermal_limit_from_violation(pm::AbstractAPLossLessModels, n::Int, t_idx, rate_a)
    # NOTE correct?
    l,i,j = t_idx
    p_fr = var(pm, n, :p, (l,j,i))
    sp = var(pm, n, :sp, l)
    sn = var(pm, n, :sn, l)

    JuMP.@constraint(pm.model, p_fr + sp - sn <= rate_a)
    JuMP.@constraint(pm.model, p_fr + sp - sn >= -rate_a)

end