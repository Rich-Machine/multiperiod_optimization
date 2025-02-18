using PowerModels
using CSV
using DataFrames
using Gurobi
using JSON
using Dates
using Plots


file_path = "/Users/rasiamah3/Library/CloudStorage/OneDrive-GeorgiaInstituteofTechnology/BTE_Model/BreakthroughEnergyGrid to PowerMod Code/Bus Data + Scripts/"
## CHANGE DATE: latest you can pick is december 31 hour 0
## DATE: Must be stored in these 3 variables
day = 1 ## day: 1-31
hour = 0 ## hour: 0-23
month = 1 ## month: 1-12
time_horizon = 24 ## Horizon is it will run 24 hours from the hour you pick
global future_year = 2025
percentage = 1

econs_data = CSV.read("$file_path/econs_data.csv", DataFrame)
ev_shares = []
for year in 2025:2049
    total_ev = []
    total_vehicles = []
    for month in 1:12
        for row in eachrow(econs_data)
            if row.year == year && row.month == month
                push!(total_ev, row.ev_count)
                push!(total_vehicles, row.total_vehicles)    
            end
            # display(total_ev)
        end
        ev_share = sum(total_ev)/sum(total_vehicles)
        display(ev_share)
        push!(ev_shares, ev_share)
    end
end

# Define x-ticks to represent hours for plotting
x_ticks = 1:24:300
x_labels = 2025:2:2049
xticks=(x_ticks, x_labels)
plot(ev_shares, xticks=xticks, xlabel="Year", ylabel="EV Share", title="EV Share Over Time", legend=false)


## Since month 102 ( June 2033) is when we hit 30% EV share, we will compare the increase in EV share across each county to assess if they each increased at the same rate.
## We will use the slope of the line to determine the rate of increase in EV share for each county.

year = 2033
month = 6
future_ev_share_per_county = []
for row in eachrow(econs_data)
    if row.year == year && row.month == month
        ev_share = row.ev_count/row.total_vehicles
        push!(future_ev_share_per_county, ev_share)
    end
end

year = 2025
month = 1
current_ev_share_per_county = []
for row in eachrow(econs_data)
    if row.year == year && row.month == month
        ev_share = row.ev_count/row.total_vehicles
        push!(current_ev_share_per_county, ev_share)
    end
end
