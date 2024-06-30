using PowerModels
using JuMP

#################### solve function ####################
function solve_mp_opf_ramp(file, model_type::Type, solver; kwargs...)
    return solve_model(file, model_type, solver, build_mn_opf_ramp; kwargs...)
end

function build_mn_opf_ramp(pm::AbstractPowerModel)

    for (n, network) in nws(pm)
        variable_bus_voltage(pm, nw=n)
        variable_gen_power(pm, nw=n)
        variable_branch_power(pm, nw=n)
        variable_dcline_power(pm, nw=n)
    end
    
    for (n, network) in nws(pm)
        constraint_model_voltage(pm, nw=n)

        for i in ids(pm, :ref_buses, nw=n)
            constraint_theta_ref(pm, i, nw=n)
        end

        for i in ids(pm, :bus, nw=n)
            constraint_power_balance(pm, i, nw=n)
        end

        for i in ids(pm, :branch, nw=n)
            constraint_ohms_yt_from(pm, i, nw=n)
            constraint_ohms_yt_to(pm, i, nw=n)

            constraint_voltage_angle_difference(pm, i, nw=n)

            constraint_thermal_limit_from(pm, i, nw=n)
            constraint_thermal_limit_to(pm, i, nw=n)
        end

        for i in ids(pm, :dcline, nw=n)
            constraint_dcline_power_losses(pm, i, nw=n)
        end

        if n != 1
            for i in ids(pm, :gen, nw=n)
                constraint_gen_ramping(pm, n, i)
            end
        end
    end

    objective_min_fuel_and_flow_cost(pm)
end

#################### ramping constraints ####################

function constraint_gen_ramping(pm::AbstractPowerModel, n::Int, i::Int)
    if haskey(nws(pm)[n][:gen][i], "ramp_30")
        pg_c = var(pm, n, :pg, i)
        pg_p = var(pm, n-Int64(1), :pg, i)
        pg_ram_up = 2 * nws(pm)[n][:gen][i]["ramp_30"]
        pg_ram_down = 2 * nws(pm)[n][:gen][i]["ramp_30"]

        if !isinf(pg_ram_down) && isreal(pg_ram_down) && pg_ram_down > 0
            JuMP.@constraint(pm.model, pg_c - pg_p <= pg_ram_up)
            JuMP.@constraint(pm.model, pg_p - pg_c <= pg_ram_down)
        end
    end
end


