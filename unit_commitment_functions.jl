using PowerModels
using JuMP

#################### solve function ####################
function solve_uc(file, solver; kwargs...)
    return solve_model(file, DCPPowerModel, solver, build_mn_uc; kwargs...)
end

function build_mn_uc(pm::AbstractPowerModel)
    for (n, network) in nws(pm)
        variable_gen_indicator_uc(pm, nw=n)
        variable_gen_power_uc(pm, nw=n)
        variable_gen_reserve_uc(pm, nw=n)
        variable_gen_startup_uc(pm, nw=n)
        variable_gen_shutdown_uc(pm, nw=n)
        variable_energy_not_served_uc(pm, nw=n)
    end

    objective_min_gen_cost_uc(pm)

    for (n, network) in nws(pm)

        constraint_network_power_balance_uc(pm, nw=n)
        constraint_network_reserve_requirement_uc(pm, nw=n)

        for i in ids(pm, n, :gen)
            constraint_gen_on_off_uc(pm, n, i)
            constraint_gen_ramping_uc(pm, n, i)
            constraint_gen_switch_uc(pm, n, i)
            constraint_gen_min_up_down_time_uc(pm, n, i)
        end
    end
end


#################### variables ####################

function variable_gen_indicator_uc(pm::AbstractPowerModel; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)
    if !relax
        ug = var(pm, nw)[:ug] = JuMP.@variable(pm.model,
            [i in ids(pm, nw, :gen)], base_name="$(nw)_ug",
            binary = true,
            start = comp_start_value(ref(pm, nw, :gen, i), "initial_status", 1)
        )
    else
        ug = var(pm, nw)[:ug] = JuMP.@variable(pm.model,
            [i in ids(pm, nw, :gen)], base_name="$(nw)_ug",
            lower_bound = 0,
            upper_bound = 1,
            start = comp_start_value(ref(pm, nw, :gen, i), "initial_status", 1.0)
        )
    end

    report && sol_component_value(pm, nw, :gen, :ug, ids(pm, nw, :gen), ug)
end

function variable_gen_startup_uc(pm::AbstractPowerModel; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)
    if !relax
        vg = var(pm, nw)[:vg] = JuMP.@variable(pm.model,
            [i in ids(pm, nw, :gen)], base_name="$(nw)_vg",
            binary = true,
            start = 0
        )
    else
        vg = var(pm, nw)[:vg] = JuMP.@variable(pm.model,
            [i in ids(pm, nw, :gen)], base_name="$(nw)_vg",
            lower_bound = 0,
            upper_bound = 1,
            start = 0.0
        )
    end

    report && sol_component_value(pm, nw, :gen, :vg, ids(pm, nw, :gen), vg)
end

function variable_gen_shutdown_uc(pm::AbstractPowerModel; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)
    if !relax
        wg = var(pm, nw)[:wg] = JuMP.@variable(pm.model,
            [i in ids(pm, nw, :gen)], base_name="$(nw)_wg",
            binary = true,
            start = 0
        )
    else
        wg = var(pm, nw)[:wg] = JuMP.@variable(pm.model,
            [i in ids(pm, nw, :gen)], base_name="$(nw)_wg",
            lower_bound = 0,
            upper_bound = 1,
            start = 0.0
        )
    end

    report && sol_component_value(pm, nw, :gen, :wg, ids(pm, nw, :gen), wg)
end

function variable_gen_power_uc(pm::AbstractPowerModel; nw::Int=nw_id_default, report::Bool=true)
    pg = var(pm, nw)[:pg] = JuMP.@variable(pm.model,
        [i in ids(pm, nw, :gen)], base_name="$(nw)_pg",
        start = comp_start_value(ref(pm, nw, :gen, i), "pg")
    )

    for (i, gen) in ref(pm, nw, :gen)
        JuMP.set_lower_bound(pg[i], gen["pmin"])
        JuMP.set_upper_bound(pg[i], gen["pmax"])
    end

    report && sol_component_value(pm, nw, :gen, :pg, ids(pm, nw, :gen), pg)
end

function variable_gen_reserve_uc(pm::AbstractPowerModel; nw::Int=nw_id_default, report::Bool=true)
    rg = var(pm, nw)[:rg] = JuMP.@variable(pm.model,
        [i in ids(pm, nw, :gen)], base_name="$(nw)_rg",
        start = 0.0
    )

    for (i, gen) in ref(pm, nw, :gen)
        JuMP.set_lower_bound(rg[i], 0.0)
        # JuMP.set_upper_bound(rg[i], gen["pmax"])
    end

    report && sol_component_value(pm, nw, :gen, :rg, ids(pm, nw, :gen), rg)
end

function variable_energy_not_served_uc(pm::AbstractPowerModel; nw::Int=nw_id_default, report::Bool=true)
    nse = var(pm, nw)[:nse] = JuMP.@variable(pm.model,
        base_name="$(nw)_nse",
        lower_bound = 0.0,
        start = 0.0
    )

    report && sol_value_nse_uc(pm, :nse, nw, nse)
end

"given a variable that is indexed by component ids, builds the standard solution structure"
function sol_value_nse_uc(pm::AbstractPowerModel, field_name::Symbol, nws_ids, variables)
    pm.sol[:it][:pm][:nw][nws_ids][field_name] = variables
end


#################### objective ####################

function objective_min_gen_cost_uc(pm::AbstractPowerModel)
    gen_cost = Dict()
    nse_cost = Dict()
    for (n, nw_ref) in nws(pm)

        if haskey(ref(pm, n, :option),"energy_not_served_cost")
            nse_cost_mw = ref(pm, n, :option)["energy_not_served_cost"]
        else
            nse_cost_mw = 10000.0
        end

        pg = var(pm, n)[:pg] 
        ug = var(pm, n)[:ug]
        vg = var(pm, n)[:vg]
        wg = var(pm, n)[:wg]
        gen_cost[n] = Dict()
        for (i,gen) in ref(pm, n, :gen)
            pmin = gen["pmin"]
            pmax = gen["pmax"]
            cost_terms = reverse(gen["cost"])
            startup_cost = gen["startup"]
            shutdown_cost = gen["shutdown"]

            pg_expr = JuMP.@expression(pm.model, cost_terms[1] * ug[i] + cost_terms[2] * pg[i])
            su_expr = JuMP.@expression(pm.model, startup_cost * vg[i])
            sd_expr = JuMP.@expression(pm.model, shutdown_cost * wg[i])

            gen_cost[n][i] = pg_expr + su_expr + sd_expr
        end
        nse_cost[n] = nse_cost_mw * var(pm, n, :nse)
    end

    return JuMP.@objective(pm.model, Min,
        sum(
            (sum( gen_cost[n][i] for (i,gen) in nw_ref[:gen]) + nse_cost[n])
        for (n, nw_ref) in nws(pm))
    )
end


#################### constraints ####################

function constraint_network_power_balance_uc(pm::AbstractPowerModel; nw::Int=nw_id_default)
    pg_terms = sum( var(pm, nw, :pg, i) for i in ids(pm, nw, :gen))
    pd_terms = sum( ref(pm, nw, :load, i)["pd"] for i in ids(pm, nw, :load))
    nse = var(pm, nw, :nse)

    JuMP.@constraint(pm.model, pg_terms == pd_terms - nse)
end

function constraint_network_reserve_requirement_uc(pm::AbstractPowerModel; nw::Int=nw_id_default, kwargs...)

    if haskey(ref(pm, nw, :option),"reserve_requirment")
        reserve_requirment = ref(pm, nw, :option)["reserve_requirment"]
    else
        reserve_requirment = 0.2
    end

    rg_terms = sum( var(pm, nw, :rg, i) for i in ids(pm, nw, :gen))
    pd_terms = sum( ref(pm, nw, :load, i)["pd"] for i in ids(pm, nw, :load))
    
    reserve = reserve_requirment * pd_terms

    JuMP.@constraint(pm.model, rg_terms >= reserve)
end

function constraint_gen_on_off_uc(pm::AbstractPowerModel, n::Int, i::Int)
    gen = ref(pm, n, :gen, i)
    pmin = gen["pmin"]
    pmax = gen["pmax"]

    pg = var(pm, n, :pg, i)
    rg = var(pm, n, :rg, i)
    ug = var(pm, n, :ug, i)

    JuMP.@constraint(pm.model, pg + rg <= pmax*ug)
    JuMP.@constraint(pm.model, pg >= pmin*ug)
end


function constraint_gen_ramping_uc(pm::AbstractPowerModel, n::Int, i::Int)
    if n > 1 && haskey(nws(pm)[n][:gen][i], "ramp_30")
        pg_c = var(pm, n, :pg, i)
        pg_p = var(pm, n-Int64(1), :pg, i)
        rg_c = var(pm, n, :rg, i)
        pg_ram_up = 2 * nws(pm)[n][:gen][i]["ramp_30"]
        pg_ram_down = 2 * nws(pm)[n][:gen][i]["ramp_30"]
        
        if !isinf(pg_ram_down) && isreal(pg_ram_down) && pg_ram_down > 0
            JuMP.@constraint(pm.model, pg_c + rg_c - pg_p <= pg_ram_up)
            JuMP.@constraint(pm.model, pg_p - pg_c <= pg_ram_down)
        end
    end
end

function constraint_gen_switch_uc(pm::AbstractPowerModel, n::Int, i::Int)
    ug = var(pm, n, :ug, i)
    vg = var(pm, n, :vg, i)
    wg = var(pm, n, :wg, i)

    if n > 1
        ug_p = var(pm, n-Int64(1), :ug, i)
    else
        if haskey(nws(pm)[n][:gen][i], "initial_status")
            ug_p = nws(pm)[n][:gen][i]["initial_status"]
        else
            ug_p = nws(pm)[n][:gen][i]["gen_status"]
        end
    end

    JuMP.@constraint(pm.model, ug - ug_p == vg - wg)
end

function constraint_gen_min_up_down_time_uc(pm::AbstractPowerModel, n::Int, i::Int)
    if haskey(nws(pm)[n][:gen][i], "minup")
        minup = nws(pm)[n][:gen][i]["minup"]
    else
        minup = 1
    end

    if haskey(nws(pm)[n][:gen][i], "mindown")
        mindown = nws(pm)[n][:gen][i]["mindown"]
    else
        mindown = 1
    end

    ug = var(pm, n, :ug, i)
    
    if n >= minup 
        vg_terms = sum( var(pm, t, :vg, i) for t in n-minup+1:n)
        JuMP.@constraint(pm.model, vg_terms <= ug)
    end
    
    
    if n >= mindown 
        wg_terms = sum( var(pm, t, :wg, i) for t in n-mindown+1:n)
        JuMP.@constraint(pm.model, wg_terms <= 1 - ug)
    end
end
