# Function to read GA data. 
## Use file_path to indicates the data location 
## CHANGE DATE: latest you can pick is december 31 hour 0
## DATE: Must be stored in these 3 variables
## hour: 0-23
# day: 1-max, depending on month. See array below for each month's last day
# month: 1-12
## time_horizon is it will run 24 hours from the hour you pick

function read_GA_data(file_path, month, day, hour, time_horizon)

    ## Sets up the dictionary in Julia.
    ## This comes from the Powermod documentation in Julia.
    ## Most will lead to separate dictionaires which are filled in the later blocks as documented below.
    data = Dict{String, Any}()
    data["bus"] = Dict{String, Any}()
    data["source_type"] = "matpower"
    data["name"] = "GA_test_system"
    data["gen"] = Dict{String, Any}()
    data["branch"]= Dict{String, Any}()
    data["storage"] = Dict{String, Any}()
    data["switch"] = Dict{String, Any}()
    data["baseMVA"] = 100.0
    data["per_unit"] = true
    data["shunt"] = Dict{String, Any}()
    data["load"] = Dict{String, Any}()
    data["dcline"] = Dict{String, Any}()
    data["source_version"] = "2"

    # Relaxed branch thermal limit values after solving DCOPF using solve_opf_violation
    branch_violation = Dict{Any, Any}("1261" => 0.01680382970460048, "2325" => 0.10838821464751436, "2153" => 0.09970077003625133, "831" => 0.08908124204872525, "1979" => 0.2000024118977588, "564" => 0.08349879529334081, "1995" => 0.07747992266596149, "8" => 0.21875435911800845, "2098" => 0.8282357926038164, "2156" => 0.3976789999999999, "1187" => 0.5988394610155541, "2147" => 0.3642789999999998, "2747" => 0.6144280816871648, "2154" => 0.06415336424221674, "2089" => 0.3131856310314336, "1978" => 0.3327680466354961, "1482" => 0.5710899999999999, "2088" => 0.4838136113846163, "2592" => 0.1495119627357171,"2489" => 0.037335307176020294, "1671" => 0.10825830713288709, "681" => 0.019742864227433543, "1233" => 0.02360300000000004, "2098" => 0.8630087142931544, "2144" => 0.21237899999999987, "2752" => 0.8408399600561465, )

    ## Bus data is read to fill bus, load, and shunt dictionaries.
    ## The county_buses.csv file contains all filtered bus information with county names and county ids.
    bus1 = CSV.read("$file_path/county_buses.csv", DataFrame)

    ## Need to calculate total p for zones 19 north and 20 south. Achieves this in the loop below.
    p19Total = 0
    p20Total = 0

    ## We need to get the total for each county as well for a percentage. We store this with a dictionary.
    countyTotal = Dict{String, Any}()

    ## For loop will iterate over every bus in the county_buses file.
    for x in eachrow(bus1)
        
        ## newZone exists so that the "zone_id" entry will be either 1, 2, or 3.
        ## 1 stands for Georgia North, 2 stands for Georgia South, and 3 stands for all other states.
        newZone = 3
        if x.zone_id == 19
            newZone = 1
        elseif x.zone_id == 20
            newZone = 2
        end

        ## State name is not held within the county_buses file.
        ## This logic checks zone_id to find and stores the state name to be used in the bus dictionary.
        newState = "Tennessee"
        if x.zone_id == 17
            newState = "Western North Carolina"
        elseif x.zone_id == 18
            newState = "South Carolina"
        elseif x.zone_id == 19
            newState = "Georgia North"
        elseif x.zone_id == 20
            newState = "Georgia South"
        elseif x.zone_id == 21
            newState = "Florida Panhandle"
        elseif x.zone_id == 22
            newState = "Florida North"
        elseif x.zone_id == 24
            newState = "Alabama"
        end

        if x.zone_id == 19
            p19Total += x.Pd/100
        elseif x.zone_id == 20
            p20Total += x.Pd/100
        end

        ## Code to get the total voltage for each county.
        if get!(countyTotal, x.county_name, 0) == 0
            countyTotal[x.county_name] = x.Pd/100
        else
            countyTotal[x.county_name] += x.Pd/100
        end

        ## This adds bus, load, and shunt data to the dictionaries
        ## All fields from the powers mod link from above are added.
        ## All fields from the excel spreadsheet are also added.
        ## The dictionaries are indexed by bus_id as the key.
        data["bus"]["$(x.bus_id)"] = Dict("source_id" => Any["bus", x.bus_id], "va" => x.Va, "vm" => x.Vm, "vmax" => x.Vmax, "vmin" => x.Vmin, "index" => x.bus_id, "bus_i" => x.bus_id, "bus_type" => x.type, "zone_id" => newZone, "base_kv" => x.baseKV, "location" => newState, "county_id" => x.county_id, "county_name" => x.county_name)
        data["load"]["$(x.bus_id)"] = Dict("source_id" => Any["bus", x.bus_id], "load_bus" => x.bus_id, "index" => x.bus_id, "status" => 1, "pd" => x.Pd/100, "qd" => x.Qd/100, "pf" => (x.Pd/100) / sqrt((x.Pd/100)^2 + (x.Qd/100)^2), "percentage" => 0, "percentage_county" => 0)
        data["shunt"]["$(x.bus_id)"] = Dict("source_id" => Any["bus", x.bus_id], "shunt_bus" => x.bus_id, "index" => x.bus_id, "status" => 1, "gs" => x.Gs, "bs" => x.Bs)
        
    end

    ## Add buses percentage of system based on zone_id 19 or 20
    for g in keys(data["bus"])
        if data["bus"][g]["zone_id"] == 1
            data["load"][g]["percentage"] = data["load"][g]["pd"] / p19Total
        elseif data["bus"][g]["zone_id"] == 2
            data["load"][g]["percentage"] = data["load"][g]["pd"] / p20Total
        end

        ## Also adds the percentage in a county based on the dictionary defined above.
        data["load"][g]["percentage_county"] = data["load"][g]["pd"] / countyTotal[data["bus"][g]["county_name"]]
    end


    ## This section will now fill out the branch dictionary.
    ## county_branches holds all county_branches data.
    branch = CSV.read("$file_path/county_branches.csv", DataFrame)

    ## Note: Counter is used here as the new key. bus_id cannot be used as buses within branches are no longer unique
    global counter = 1

    ## Loops over every entry in county_branches
    for x in eachrow(branch)

        ## Similar to the bus logic, newZone ids will be changed to represent Georgia South, Georgia North, and other.
        ## Branches have 2 buses, so both buses need to be checked and changed appropriately.
        newZone1 = 3
        if x.from_zone_id == 19
            newZone1 = 1
        elseif x.from_zone_id == 20
            newZone1 = 2
        end
        newZone2 = 3
        if x.to_zone_id == 19
            newZone = 1
        elseif x.to_zone_id == 20
            newZone = 2
        end

        ## Ratio needs to be changed to 1.0 if it is 0.0 in the data. This logic achieves this and stores it.
        newRatio = x.ratio
        if newRatio == 0
            newRatio = 1.0
        end

        ## Transformer needs to be stored as a bool, but is not stored like that in the database.
        ## This logic will hold is_transformer so it can be added to the dictionary.
        is_transformer = false
        if x.branch_device_type == "Transformer"
            is_transformer = true
        end

        ## Adds all fields in the dictionary according to the link and spreadsheet.
        # data["branch"]["$counter"] = Dict("source_id" => Any["branch", counter], "transformer" => is_transformer, "index" => counter, "f_bus" => x.from_bus_id, "t_bus" => x.to_bus_id, "br_r" => x.r, "br_x" => x.x, "br_status" => x.status, "rate_a" => x.rateA/100, "rate_b" => x.rateB/100, "rate_c" => x.rateC/100, "tap" => newRatio, "shift" => x.angle, "angmin" => -1.57, "angmax" => 1.57, "pf" => x.Pf/100, "qf" => x.Qf/100, "pt" => x.Pt/100, "qt" => x.Qt/100, "b_fr" => x.b/2, "b_to" => x.b/2, "g_fr" => 0.0, "g_to" => 0.0, "branch_device_type" => x.branch_device_type, "from_zone_id" => newZone1, "to_zone_id" => newZone2, "from_county_id" => x.from_county_id, "from_county_name" => x.from_county_name, "to_county_id" => x.to_county_id, "to_county_name" => x.to_county_name)
        data["branch"]["$counter"] = Dict("source_id" => Any["branch", counter], "transformer" => is_transformer, "index" => counter, "f_bus" => x.from_bus_id, "t_bus" => x.to_bus_id, "br_r" => x.r, "br_x" => x.x, "br_status" => x.status, "rate_a" => x.rateA/100 * 1.01, "rate_b" => x.rateB/100 *1.01, "rate_c" => x.rateC/100 * 1.01, "tap" => newRatio, "shift" => x.angle, "angmin" => -1.57, "angmax" => 1.57, "pf" => x.Pf/100, "qf" => x.Qf/100, "pt" => x.Pt/100, "qt" => x.Qt/100, "b_fr" => x.b/2, "b_to" => x.b/2, "g_fr" => 0.0, "g_to" => 0.0, "branch_device_type" => x.branch_device_type, "from_zone_id" => newZone1, "to_zone_id" => newZone2, "from_county_id" => x.from_county_id, "from_county_name" => x.from_county_name, "to_county_id" => x.to_county_id, "to_county_name" => x.to_county_name)

        if "$counter" in keys(branch_violation)
            data["branch"]["$counter"]["rate_a"] = ceil((data["branch"]["$counter"]["rate_a"] + branch_violation["$counter"]) *1.2)
            data["branch"]["$counter"]["rate_b"] = ceil((data["branch"]["$counter"]["rate_b"] + branch_violation["$counter"]) *1.2)
            data["branch"]["$counter"]["rate_c"] = ceil((data["branch"]["$counter"]["rate_c"] + branch_violation["$counter"]) *1.2)
        end
        global counter += 1

    end

    ## This section will now fill out the gen dictionary.
    ## county_gen holds all the gen data.
    gen = CSV.read("$file_path/county_gen.csv", DataFrame)

    ## Loops over all gens in county_gen
    for x in eachrow(gen)

        ## Same logic as other 2. Changes zone_id to represent Georgia North, Georgia South, and other.
        newZone = 3
        if x.zone_id == 19
            newZone = 1
        elseif x.zone_id == 20
            newZone = 2
        end

        ## Startup and shutdown costs were not stored within the genereator dataset. These needed to be calculated manually based on generator type.
        ## This logic sets the cost for each generator appropriately. 
        cost = 0.0
        minup = 1
        if x.type == "hydro"
            cost = 0.0
            minup = 0
        elseif x.type == "solar"
            cost = 0.0
            minup = 0
        elseif x.type == "ng"
            if x.Pmax <= 100
                cost = 5665.23
            else
                cost = 28046.68
            end
            if x.plant_id == 3927 || x.plant_id == 3928 || x.plant_id == 3929 || x.plant_id == 3930 || x.plant_id == 3931 || x.plant_id == 3932
                minup = 6.2 
            elseif x.plant_id == 3987 || x.plant_id == 3988 || x.plant_id == 3989
                minup = 6.2
            elseif x.plant_id == 4004 || x.plant_id == 4005 || x.plant_id == 4006
                minup = 6.2 
            elseif x.plant_id == 3997 || x.plant_id == 3801 || x.plant_id == 3802
                minup = 6.2
            elseif x.plant_id == 4031 || x.plant_id == 4032 || x.plant_id == 4033
                minup = 6.2
            elseif x.plant_id == 4064 || x.plant_id == 4065 || x.plant_id == 4066 
                minup = 6.2
            elseif x.plant_id == 4116 || x.plant_id == 4117 || x.plant_id == 4118 || x.plant_id == 4119 || x.plant_id == 4120 ||x.plant_id == 4121
                minup = 6.2
            end
        elseif x.type == "dfo"
            if x.Pmax < 5
                cost = 51.747
            elseif x.plant_id == 3851
                cost = 51.747
            elseif x.plant_id == 4025 || x.plant_id == 4026 || x.plant_id == 4027 || x.plant_id == 4028 || x.plant_id == 4029 || x.plant_id == 4030
                cost = 51.747
            elseif x.plant_id == 4042 || x.plant_id == 4043
                cost = 51.747
            elseif x.plant_id == 4074 || x.plant_id == 4075
                cost = 51.747
            elseif x.plant_id == 4076 || x.plant_id == 4077
                cost = 51.747
            elseif x.plant_id == 4099 || x.plant_id == 4100 || x.plant_id == 4101 || x.plant_id == 4102 || x.plant_id == 4103 || x.plant_id == 4104
                cost = 703.759
            end
        elseif x.type == "coal"
            cost = 11172.01435
            minup = 12
        end

        ## Note: plant_id is the new key instead of bus_id. Generators have multiple buses, and thus bus_id will contain duplicates and cannot be used as a key.
        data["gen"]["$(x.plant_id)"] = Dict("source_id" => Any["gen", x.plant_id], "startup" => cost, "shutdown" => cost, "index" => x.plant_id, "gen_bus" => x.bus_id, "plant_id" => x.plant_id, "pg" => (x.Pg)/100, "qg" => x.Qg/100, "pmax" => x.Pmax/100, "pmin" => x.Pmin/100, "qmax" => x.Qmax/100, "qmin" => x.Qmin/100, "gen_status" => x.status, "vg" => x.Vg, "mBase" => 100, "ramp_30" => x.ramp_30, "apf" => x.apf, "type" => x.type, "GenFuelCost" => x.GenFuelCost, "GenIOB" => x.GenIOB, "GenIOC" => x.GenIOC, "zone_id" => newZone, "zone_name" => x.zone_name, "county_id" => x.county_id, "county_name" => x.county_name, "minup" => minup)
    end


    ## Add ncost, model, and cost to generators based on supply
    costs = CSV.read("$file_path/filtered_supply.csv", DataFrame)

    ## This loops over every gen currenty in the generator dictionary.
    for g in keys(data["gen"])

        ## Default data is set for ncost and model. cost may be changed as seen below.
        data["gen"][g]["ncost"] = 3
        data["gen"][g]["model"] = 2
        data["gen"][g]["cost"] = [0.0; 0.0; 0.0]

        ## The key in g is seen as a string. Needs to be parsed as an int to be compared with x.plant_id, which is an int
        plantId = parse(Int64, g)

        ## Once setup is done, need to check over the supply data to find a match in plant_ids.
        ## If a match is found, then the cost of that gen can be set appropriately.
        for x in eachrow(costs)
            if x.plant_id == plantId
                data["gen"][g]["cost"] = [x.c2; x.c1; x.c0]
                break
            end
        end
    end

    ## Fill out gen dictionary for non Georgia states.
    ## Power flows into Georgia, but the current gen dictionary does not show this. This is meant to simulate the power flowing in from other states.

    ## Most values are currently dummy values as the fake generators do not have values in the data. These can be changed in the declaration line.
    ## Pf and Qf are gathered from filtered_out_state. This will need to change to get value from dictionary later.

    ## Note: filtered_out_state was built from the filtered_buses because it could capture everything out of state.
    ##          Thus, it has a bus_id which is used to compare with branch data.
    outState = CSV.read("$file_path/filtered_out_state.csv", DataFrame)
    global counter = 100000
    for x in eachrow(outState)
        pg = x.Pd
        qg = x.Qd

        ## Branch holds the necessary pf and pt data we need to simulate power.
        ## Because of this, we can loop through the branch dictionary and see if we find a bus_id that matches our filtered_out_state bus_id.
        for g in keys(data["branch"])
            if data["branch"][g]["f_bus"] == x.bus_id
                pg = data["branch"][g]["pf"]
                qg = data["branch"][g]["qf"]
                break
            elseif  data["branch"][g]["t_bus"] == x.bus_id
                pg = data["branch"][g]["pt"]
                qg = data["branch"][g]["qt"]
                break
            end
        end

        ## Note: The current key is counter. It used to be bus_id, but there were duplicate ones in the gen due to plants having multiple buses.
        ## Counter is temporary until something better is found. Counter set at 100,000 as no plant_id comes close to this value.
        
        ## This line creates the fake generator data.
        data["gen"]["$(counter)"] = Dict("source_id" => Any["gen", counter], "startup" => 0.0, "shutdown" => 0.0, "index" => counter, "gen_bus" => x.bus_id, "plant_id" => counter, "pg" => pg/100, "qg" => qg/100, "pmax" => pg/100, "pmin" => pg/100, "qmax" => qg/100, "qmin" => qg/100, "gen_status" => 1, "vg" => 1.05, "mBase" => 100.0, "ramp_30" => 1000.0, "apf" => 1, "type" => "v", "zone_id" => 3, "GenFuelCost" => 0, "GenIOB" => 0, "GenIOC" => 0, "county_id" => -1, "county_name" => "NA", "model" => 2, "ncost" => 3, "cost" =>[0.0; 0.0; 0.0])
        global counter += 1
    end

    ## These methods will optimize the dataset within the Julia dictionary and send it to Matpower.
    select_largest_component!(data)
    propagate_topology_status!(data)

    ## clean and arrange to data using PowerModels
    new_data = make_basic_network(data)

    # ## change the line flow to make the problem feasiable
    # result = solve_opf_violation(new_data, DCPPowerModel ,opt)
    # bus_shaded = Dict(idx => bus["nse"] for (idx, bus) in result["solution"]["bus"] if bus["nse"] > 0)
    # branch_violation = Dict(idx => branch["sp"] + branch["sn"]  for (idx, branch) in result["solution"]["branch"] if branch["sp"] > 0 || branch["sn"] > 0)

    # for (idx, val) in branch_violation 
    #     new_data["branch"][idx]["rate_a"] = ceil(new_data["branch"][idx]["rate_a"]) * 1.5
    # end

    ## Duplicates the model to allow for 24 hour slots. 
    data = PowerModels.replicate(new_data, time_horizon)    
    
    ## DO NOT CHANGE
    year = 2016
    dayOfWeek = 5
    
    ## Code to find day of week for accessing EV data.
    days = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] ## February has 29 days as it is a leap year.
    for i in 1:month
        if i == month
            for i in 1:day - 1
                dayOfWeek = (dayOfWeek + 1) % 7
            end
            break
        else
            for i in 1:days[month - 1]
                dayOfWeek = (dayOfWeek + 1) % 7
            end
        end
    end
    
    ## Logic to get the 24 hours of EV information
    countyData = Dict{Int, Any}()
    countyData[1] = Dict{String, Any}()
    global counter = 1
    flag = false
    pastHour = 0
    nrel_data = CSV.read("$file_path/aggregatedCounties.csv", DataFrame)

    counties = ["Appling", "Atkinson", "Bacon", "Baker", "Baldwin", "Banks", "Barrow", "Bartow", "Ben Hill", "Berrien", "Bibb", "Bleckley", "Brantley", "Brooks", "Bryan", "Bulloch", "Burke", "Butts", "Calhoun", "Camden", "Candler", "Carroll", "Catoosa", "Charlton", "Chatham", "Chattahoochee", "Chattooga", "Cherokee", "Clarke", "Clay", "Clayton", "Clinch", "Cobb", "Coffee", "Colquitt", "Columbia", "Cook", "Coweta", "Crawford", "Crisp", "Dade", "Dawson", "De Kalb", "Decatur", "Dodge", "Dooly", "Dougherty", "Douglas", "Early", "Echols", "Effingham", "Elbert", "Emanuel", "Evans", "Fannin", "Fayette", "Floyd", "Forsyth", "Franklin", "Fulton", "Gilmer", "Glascock", "Glynn", "Gordon", "Grady", "Greene", "Gwinnett", "Habersham", "Hall", "Hancock", "Haralson", "Harris", "Hart", "Heard", "Henry", "Houston", "Irwin", "Jackson", "Jasper", "Jeff Davis", "Jefferson", "Jenkins", "Johnson", "Jones", "Lamar", "Lanier", "Laurens", "Lee", "Liberty", "Lincoln", "Long", "Lowndes", "Lumpkin", "Mcduffie", "Mcintosh", "Macon", "Madison", "Marion", "Meriwether", "Miller", "Mitchell", "Monroe", "Montgomery", "Morgan", "Murray", "Muscogee", "Newton", "Oconee", "Oglethorpe", "Paulding", "Peach", "Pickens", "Pierce", "Pike", "Polk", "Pulaski", "Putnam", "Quitman", "Rabun", "Randolph", "Richmond", "Rockdale", "Schley", "Screven", "Seminole", "Spalding", "Stephens", "Stewart", "Sumter", "Talbot", "Taliaferro", "Tattnall", "Taylor", "Telfair", "Terrell", "Thomas", "Tift", "Toombs", "Towns", "Treutlen", "Troup", "Turner", "Twiggs", "Union", "Upson", "Walker", "Walton", "Ware", "Warren", "Washington", "Wayne", "Webster", "Wheeler", "White", "Whitfield", "Wilcox", "Wilkes", "Wilkinson", "Worth"]
    points = []
    important_points = Dict()
    for hour in 0:23
        important_points[hour] = Dict()
        for county in counties
            points = []
            important_points[hour][county] = Dict()
            for x in eachrow(nrel_data)
                for i in 0:6
                    if x.geography == county && x.day_of_week == i && x.month == 1 && x.hour == hour # assume the shape for the different months are the same
                        push!(points, x.Load)
                        if i == 6
                            important_points[hour][county] = points./maximum(points)   
                        end               
                    end
                end
            end
        end
    end

    ## Gets the demand so that pd and qd can be set accurately
    econs_data = CSV.read("$file_path/econs_data.csv", DataFrame)
    for row in eachrow(econs_data)
        row.countyname = uppercase(string(row.countyname[1])) * lowercase(row.countyname[2:end])
    end
    demand = CSV.read("$file_path/demand_vJan2021.csv", DataFrame)
    global counter = 1
    flag = false
    
    ## Logic to convert date to indexable format.
    stringHour = string(hour)
    stringDay = string(day)
    stringMonth = string(month)
    if length(stringHour) == 1
        stringHour = "0" * stringHour
    end
    if length(stringDay) == 1
        stringDay = "0" * stringDay
    end
    if length(stringMonth) == 1
        stringMonth = "0" * stringMonth
    end
    stringDate = string(year) * "-" * stringMonth * "-" * stringDay * " " * stringHour * ":00:00"
    
    ## Loop over each row in the demand to find the right time
    for x in eachrow(demand)
    
        ## Once time is found or the flag is true, then we are in the right timeslot
        if x["UTC Time"] == stringDate || flag
            flag = true
            newPd19 = x["19"] / 100
            newPd20 = x["20"] / 100
            newPd = 0
            countyLoadDict = important_points[counter-1]
    
            ## Logic to set the new pd and qd for each entry in the hour.
            hourData = data["nw"][string(counter)]["load"]
            for g in keys(hourData)
                if data["nw"][string(counter)]["bus"][g]["zone_id"] == 1
                    newPd = hourData[g]["percentage"] * newPd19
                elseif data["nw"][string(counter)]["bus"][g]["zone_id"] == 2
                    newPd = hourData[g]["percentage"] * newPd20
                end
    
                ## We do not qd and pf to be NaN. This ensures they are set to 0.0. This is only done when the zone_id isn't 1 or 2.
                if newPd == 0 || isnan(newPd)
                    hourData[g]["qd"] = 0.0
                    hourData[g]["pf"] = 0.0
                    hourData[g]["pd"] = 0.0
                else
                    ## Set qd
                    hourData[g]["qd"] = sqrt((newPd / hourData[g]["pf"])^2 - newPd^2)
                end
    
                ## set pd
                if data["nw"][string(counter)]["bus"][g]["county_name"] != "NA" && get(countyLoadDict, data["nw"][string(counter)]["bus"][g]["county_name"], 0) != 0
                    for rows in eachrow(econs_data)
                        if rows.month == month && data["nw"][string(counter)]["bus"][g]["county_name"] == rows.countyname && rows.year == future_year
                            multiplying_factor = rows.ev_count * 2363 * 1000 / 8760  ## 2363 kilowatts hour, 1000 to convert to watts, 8760 hours in a year
                            newPd = newPd + important_points[counter-1][data["nw"][string(counter)]["bus"][g]["county_name"]][day] * hourData[g]["percentage_county"] * multiplying_factor
                        end
                    end
                end
                hourData[g]["pd"] = newPd
            end
    
            ## Only 24 hours are being tracked. Once this is reached, break the loop.
            global counter += 1
            if counter > time_horizon
                break
            end
        end
    
    end

    # remnove NaN loads
    # nan_load = [(i,n) for i in keys(data["nw"]["1"]["load"]) for n in 1:time_horizon if isnan(data["nw"]["$n"]["load"][i]["pd"]) ]
    for i in 1:time_horizon
        for j in keys(data["nw"]["$i"]["load"])
            if isnan(data["nw"]["$i"]["load"][j]["pd"])
            data["nw"]["$i"]["load"][j]["pd"] = 0
            end
        end
    end

    return data
end
