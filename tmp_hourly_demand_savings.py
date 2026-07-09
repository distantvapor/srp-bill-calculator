import csv
from datetime import datetime
from collections import defaultdict

path = './hourlyUsage7_1_2025_to_06_30_2026.csv'

season_rate = {
    'winter': 0.1119,
    'summer': 0.1257,
    'summer_peak': 0.1654,
}

rates = {
    'winter': 0.1119,
    'summer': 0.1257,
    'summer_peak': 0.1654,
}

season_month = {
    'winter': set([11,12,1,2,3,4]),
    'summer': set([5,6,9,10]),
    'summer_peak': set([7,8]),
}

def season(month):
    for name, months in season_month.items():
        if month in months:
            return name
    return None

# one kWh reduction at 9pm every day
count_9pm = 0
sum_energy_saving = 0.0
season_counts = defaultdict(int)
season_energy_saving = defaultdict(float)

# Demand savings estimate if 9pm is the daily on-peak max
days_with_9pm_max = defaultdict(int)
month_day = defaultdict(lambda: defaultdict(float))

with open(path, newline='') as f:
    reader = csv.reader(f)
    headers = next(reader)
    data = list(reader)

# group by date
by_date = defaultdict(list)
for row in data:
    if not row or not row[0].strip():
        continue
    date = datetime.strptime(row[0], '%m/%d/%Y').date()
    interval = row[1]
    kwh = float(row[2])
    by_date[date].append((interval, kwh))

for date, rows in sorted(by_date.items()):
    # compute 9pm row
    for interval, kwh in rows:
        # parse interval like '9:0 PM'
        parts = interval.split()
        if len(parts) != 2:
            continue
        hm, ampm = parts
        hour = int(hm.split(':')[0])
        if ampm == 'PM' and hour != 12:
            hour += 12
        if ampm == 'AM' and hour == 12:
            hour = 0
        if hour == 21:
            count_9pm += 1
            s = season(date.month)
            sum_energy_saving += rates[s]
            season_counts[s] += 1
            season_energy_saving[s] += rates[s]
            break
    # determine if 9pm is the max on-peak hour
    # on-peak hours are 17-21 inclusive, both weekdays and weekends? E-16 says Mon-Fri only, but if weekend then no on-peak.
    weekday = date.weekday() < 5
    peak_hours = []
    if weekday:
        for interval, kwh in rows:
            parts = interval.split()
            if len(parts) != 2: continue
            hm, ampm = parts
            hour = int(hm.split(':')[0])
            if ampm == 'PM' and hour != 12:
                hour += 12
            if ampm == 'AM' and hour == 12:
                hour = 0
            if 17 <= hour < 22:
                peak_hours.append((hour, kwh))
    else:
        peak_hours = []
    if peak_hours:
        max_kwh = max(kwh for _, kwh in peak_hours)
        max_hours = [hour for hour,kwh in peak_hours if kwh == max_kwh]
        if 21 in max_hours:
            days_with_9pm_max[date.strftime('%Y-%m')] += 1

print('9pm days:', count_9pm)
print('energy savings total if reduce 1 kWh each 9pm day: $', round(sum_energy_saving, 2))
print('season counts', dict(season_counts))
print('season energy', {k: round(v,2) for k,v in season_energy_saving.items()})
print('days where 9pm is daily on-peak max by month:')
for m, c in sorted(days_with_9pm_max.items()):
    print(m, c)
print('total days where 9pm is max on-peak:', sum(days_with_9pm_max.values()))

# estimate demand savings if each day with 9pm max loses 1 kW
# monthly demand rate by season using last day of month season
monthly_rate = {
    '2025-10': 13.56,
    '2025-11': 9.61,
    '2025-12': 9.61,
    '2026-01': 9.61,
    '2026-02': 9.61,
    '2026-03': 9.61,
    '2026-04': 9.61,
    '2026-05': 13.56,
    '2026-06': 13.56,
    '2025-07': 17.78,
    '2025-08': 17.78,
    '2025-09': 17.78,
}
# The rate is per kW averaged daily; if 1 day drops by 1 kW, monthly average decreases by 1/numdays kW, so demand saving = rate * (1/numdays).
# But if we reduce 1 kWh each day at 9pm on every day, and if 9pm is the max on all days, then monthly average drops by 1 kW.
# To simplify, assume it affects only the days where 9pm is the max, proportionally.
print('--- demand savings estimate assuming 1kW reduction on 9pm max days ---')
for month, count in sorted(days_with_9pm_max.items()):
    year, mon = month.split('-')
    numdays = len([d for d in by_date if d.strftime('%Y-%m') == month])
    rate = monthly_rate.get(month, 13.56)
    saving = rate * (count / numdays)
    print(month, 'count', count, 'days', numdays, 'rate', rate, 'saving', round(saving,2))
print('total demand saving estimate', round(sum(monthly_rate.get(month,13.56)*(count/len([d for d in by_date if d.strftime("%Y-%m") == month])) for month,count in days_with_9pm_max.items()),2))
