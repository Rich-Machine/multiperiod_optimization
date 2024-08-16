function save_uc_results(data, day, gen_status)
    global ug_prev_day = Dict(g => [] for g in keys(data["nw"]["1"]["gen"]))
    global wg_prev_day = Dict(g => [] for g in keys(data["nw"]["1"]["gen"]))
    global vg_prev_day = Dict(g => [] for g in keys(data["nw"]["1"]["gen"]))
    
    for g in keys(data["nw"]["1"]["gen"])
        for i in 1:24
            push!(ug_prev_day[g], gen_status[day][g][i])
        end
    end
    
    for g in keys(data["nw"]["1"]["gen"])
        prev_status = ug_prev_day[g]
        wg_prev_day[g] = fill(0, length(prev_status))
        vg_prev_day[g] = fill(0, length(prev_status))
        for i in 2:24
            if prev_status[i] == 1 && prev_status[i-1] == 0
                vg_prev_day[g][i] = 1
            end
            if prev_status[i] == 0 && prev_status[i-1] == 1
                wg_prev_day[g][i] = 1
            end
        end
    end
    return ug_prev_day, vg_prev_day, wg_prev_day
end