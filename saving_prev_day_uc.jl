function save_uc_results(gen_status)
#    global ug_prev_day = Dict(g => [] for g in keys(data["nw"]["1"]["gen"]))  
    global ug_prev_day = Dict()
    global wg_prev_day = Dict()
   global vg_prev_day = Dict()
    
    for g in 1:length(keys(data["nw"]["1"]["gen"]))
        if haskey(data["nw"]["1"]["gen"]["$g"], "minup") 
            println("Generator $g has minup: $(data["nw"]["1"]["gen"]["$g"]["minup"]) and mindown: $(data["nw"]["1"]["gen"]["$g"]["mindown"])")
        else 
            push!(data["nw"]["1"]["gen"]["$g"], "minup" => 1)
            push!(data["nw"]["1"]["gen"]["$g"], "mindown" => 1)
        end
    end
    
    for g in keys(data["nw"]["1"]["gen"])
        for i in 24 - data["nw"]["1"]["gen"]["$g"]["minup"]:24
            push!(ug_prev_day[g], gen_status[day][g][i])
        end
    end
    
    for g in keys(data["nw"]["1"]["gen"])
        prev_status = ug_prev_day[g]
        if prev_status[1] == 1 && any(prev_status .== 0)
            transition_idx = findfirst(x -> x == 0, prev_status)
            wg_prev_day[g] = fill(0, length(prev_status))
            wg_prev_day[g][transition_idx] = 1
        elseif prev_status[1] == 0 && any(prev_status .== 1)
            transition_idx = findfirst(x -> x == 1, prev_status)
            vg_prev_day[g] = fill(1, length(prev_status))
            vg_prev_day[g][transition_idx] = 0
        else
            wg_prev_day[g] = fill(0, length(prev_status))
            vg_prev_day[g] = fill(0, length(prev_status))
        end
    end
    return ug_prev_day, wg_prev_day, vg_prev_day
end