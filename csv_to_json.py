#!/usr/bin/env python3

import csv
import json
from typing import Dict

csv_file = '/Users/jkline/Downloads/Lewward Movement Allowance Table - movement.csv'

# Dict[str, Dict[str, Dict[int, Dict[int, Dict[str, int]]]]]
data: Dict[str, Dict[str, Dict[int, Dict[int, Dict[str, int]]]]] = {}

with open(csv_file, 'r') as f:
    reader = csv.reader(f)
    next(reader)  # Skip first row
    
    for row in reader:
        key1 = row[0]
        key2 = row[1]
        key3 = int(row[2])
        key4 = int(row[3])
        key5 = row[4]
        value = int(row[5])
        
        # Build nested structure
        if key1 not in data:
            data[key1] = {}
        if key2 not in data[key1]:
            data[key1][key2] = {}
        if key3 not in data[key1][key2]:
            data[key1][key2][key3] = {}
        if key4 not in data[key1][key2][key3]:
            data[key1][key2][key3][key4] = {}
        
        data[key1][key2][key3][key4][key5] = value

print(json.dumps(data, indent=2))
