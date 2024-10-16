# This script is used to aggregate the json data produced from running the simulation in 
# different ways for data visualization.

import json
import csv

# Compare Raw OPF and Unit Commitment for a single generator at every time point
# Load JSON data from a file
with open('/Users/hannakhor/multiperiod_optimization/results/generator_outputs_50_percent_raw_opf.json', 'r') as file:
    data_raw = json.load(file)

with open('/Users/hannakhor/multiperiod_optimization/results/generator_outputs_50_percent.json', 'r') as file:
    data_uc = json.load(file)

# Initialize a list to store the summed vectors
vector_sum = []
sums = {}

# Code to compare time points for one bus
key = "28"
uc = data_uc.get(key, {}).get('output',[])
raw = data_raw.get(key, {}).get('output',[])

length = min(len(uc), len(raw))
difference = [uc[i]-raw[i] for i in range(length)]

for key in data_uc:
    # Compute the sum of the 'output' list
    sums[key] = sum(data_uc[key]['output'])

output_vector_uc = list(sums.values())

# Code to compare buses by finding total output from each bus
for key in data_raw:
    # Compute the sum of the 'output' list
    sums[key] = sum(data_raw[key]['output'])

output_vector_raw = list(sums.values())
buses_vector_raw = list(sums.keys())

for key in data_uc:
    # Compute the sum of the 'output' list
    sums[key] = sum(data_uc[key]['output'])

output_vector_uc = list(sums.values())
buses_vector_uc = list(sums.keys())

'''

# Code to add loads across all time points - Total Generation for each time point
for key, value in data.items():
    if isinstance(value, dict) and 'output' in value:
        output_vector = value['output']
        # Ensure the vector_sum list is long enough to accommodate the current vector
        if len(vector_sum) < len(output_vector):
            vector_sum.extend([0] * (len(output_vector) - len(vector_sum)))
        
        # Sum the elements of the vectors
        for i in range(len(output_vector)):
            vector_sum[i] += output_vector[i]
    else:
        print(f"Skipping entry with incorrect format: {value}")

'''

# Define the CSV file path
csv_file_path = 'results/summed_vectors_opf2.csv'

# Write the summed vector to a CSV file
with open(csv_file_path, 'a', newline='') as file:
    writer = csv.writer(file)
    writer.writerow(difference)
    # writer.writerow(buses_vector_raw)
    # writer.writerow(output_vector_raw)  # Write the summed vector as a single row
    # writer.writerow(buses_vector_uc)
    # writer.writerow(output_vector_uc)

print(f'Summed vector has been saved to {csv_file_path}')