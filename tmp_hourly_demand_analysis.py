import csv
from collections import defaultdict
path = './hourlyUsage7_1_2025_to_06_30_2026.csv'
counts = defaultdict(int)
usage = defaultdict(float)
rows = 0
with open(path, newline='') as f:
    reader = csv.reader(f)
    next(reader)
    for row in reader:
        if not row or not row[0].strip():
            continue
        time = row[1]
        try:
            parts = time.split()
            hm = parts[0]
            ampm = parts[1]
            hour = int(hm.split(':')[0])
            if ampm.upper() == 'PM' and hour != 12:
                hour += 12
            if ampm.upper() == 'AM' and hour == 12:
                hour = 0
        except Exception:
            continue
        if 17 <= hour < 22:
            kwh = float(row[2])
            counts[hour] += 1
            usage[hour] += kwh
            rows += 1
print('rows', rows)
for h in range(17, 22):
    avg = usage[h] / counts[h] if counts[h] else 0
    print(f'{h}:00 - count={counts[h]}, total={usage[h]:.2f}, avg={avg:.4f}')
print('rank by avg')
for h, avg in sorted(((h, usage[h] / counts[h] if counts[h] else 0) for h in range(17, 22)), key=lambda x: -x[1]):
    print(h, avg)
