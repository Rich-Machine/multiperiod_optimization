
## Mohanad did this to plot in Python
# arranging the generation results via summing the generators power outputs in each bus
gens_ids = unique([gens_data[i]["bus"] for i in keys(gens_data)])

gens_data_new = Dict()
for i in gens_ids
    g_ids = findall(x -> x["bus"] == i, gens_data)
    if !isempty(g_ids)
        gens_data_new[i] = Dict("id"=> g_ids, "bus"=> i, "output" => sum(gens_data[j]["output"] for j in g_ids, dims = 1))
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