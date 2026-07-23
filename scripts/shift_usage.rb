#!/usr/bin/env ruby
# shift_usage.rb -- Preprocess a power.rb CSV by shifting kWh from one time
# window to another. Useful for modelling hypothetical load shifts
# (e.g. moving a pool pump from an overnight window to a super-off-peak window).
require "csv"
require "date"
require "optparse"

# Parse an inclusive 24h hour range like "21-4" -> [21,22,23,0,1,2,3,4]
# or "8-15" -> [8,9,10,11,12,13,14,15]. Wrap-around midnight is supported.
def parse_hour_range(str)
  parts = str.split("-")
  raise "Invalid range #{str} -- use START-END in 24h integers (e.g. 21-4 or 8-15)" unless parts.length == 2
  sh = parts[0].to_i % 24
  eh = parts[1].to_i % 24
  hours = []
  h = sh
  loop do
    hours << h
    break if h == eh
    h = (h + 1) % 24
    raise "Range #{str} exceeds 24 hours" if hours.length > 24
  end
  hours
end

# Parse SRP interval strings like "1:0 AM", "12:0 PM", "11:30 PM" into 0-23
def parse_hour(time_str)
  return nil unless time_str =~ /(\d+):\d+\s*(AM|PM)/i
  h    = $1.to_i
  ampm = $2.upcase
  ampm == "AM" ? (h == 12 ? 0 : h) : (h == 12 ? 12 : h + 12)
end

def matches_day?(date, spec)
  return true if spec.strip.downcase == "all"
  spec.split(",").map(&:strip).any? do |s|
    case s.downcase
    when "weekday", "weekdays" then (1..5).cover?(date.wday)
    when "weekend", "weekends" then [0, 6].include?(date.wday)
    when "sunday",  "sun"      then date.wday == 0
    when "monday",  "mon"      then date.wday == 1
    when "tuesday", "tue"      then date.wday == 2
    when "wednesday","wed"     then date.wday == 3
    when "thursday","thu"      then date.wday == 4
    when "friday",  "fri"      then date.wday == 5
    when "saturday","sat"      then date.wday == 6
    else
      abort "Unknown day specifier: #{s}. Use: all, weekday, weekend, mon, tue, wed, thu, fri, sat, sun"
    end
  end
end

options = { days: "all" }
parser = OptionParser.new do |opts|
  opts.banner = <<~BANNER

    Usage: shift_usage.rb -f INPUT -o OUTPUT -s SOURCE -t DEST -k KWH [--days DAYS]

    Simulates a load shift by redistributing a fixed kWh amount from one set of
    hours to another across matching days (e.g. moving a pool pump to a cheaper
    time window). Source and destination ranges must span the same number of hours.
    Hour ranges are inclusive 24h integers; midnight wrap-around is supported.

    Pool pump example -- shift 1.5 kWh/hr from 9PM-4:59AM to 8AM-3:59PM, every day:
      ruby shift_usage.rb -f usage.csv -o shifted.csv -s 21-4 -t 8-15 -k 1.5

    Weekdays only:
      ruby shift_usage.rb -f usage.csv -o shifted.csv -s 21-4 -t 8-15 -k 1.5 --days weekday

    Options:
  BANNER
  opts.on("-f", "--file FILE",    "Input CSV (same format as power.rb)")          { |v| options[:file]   = v }
  opts.on("-o", "--output FILE",  "Output CSV file")                               { |v| options[:output] = v }
  opts.on("-s", "--source RANGE", "Source hours to shift FROM (e.g. 21-4 = 9PM-4:59AM)") { |v| options[:source] = v }
  opts.on("-t", "--dest RANGE",   "Destination hours to shift TO (e.g. 8-15 = 8AM-3:59PM)") { |v| options[:dest] = v }
  opts.on("-k", "--kwh AMOUNT",   Float, "kWh per hour to shift")                  { |v| options[:kwh]    = v }
  opts.on("-d", "--days DAYS",    "Days: all | weekday | weekend | mon,tue,... (default: all)") { |v| options[:days] = v }
end
parser.parse!

%i[file output source dest kwh].each do |key|
  abort "Missing required option: --#{key.to_s.tr("_", "-")}\n\n#{parser.help}" if options[key].nil?
end
abort "Input file not found: #{options[:file]}" unless File.exist?(options[:file])

source_hours = parse_hour_range(options[:source])
dest_hours   = parse_hour_range(options[:dest])

if source_hours.length != dest_hours.length
  abort "Source range spans #{source_hours.length} hour(s) but destination spans #{dest_hours.length} -- they must match.\n" \
        "  Source (#{options[:source]}): #{source_hours.join(", ")}\n" \
        "  Dest   (#{options[:dest]}):   #{dest_hours.join(", ")}"
end

overlap = source_hours & dest_hours
warn "Warning: source and destination overlap at hours #{overlap.join(", ")} -- results may be unexpected." unless overlap.empty?

hour_map = source_hours.zip(dest_hours).to_h

# -- Load CSV ------------------------------------------------------------------
raw_rows    = []
csv_headers = nil
CSV.open(options[:file], headers: true) do |csv|
  csv.each { |row| raw_rows << row.to_h }
  csv_headers = csv.headers
end
abort "CSV is empty or has no header row" if csv_headers.nil? || raw_rows.empty?

date_col = csv_headers[0]
time_col = csv_headers[1]
kwh_col  = csv_headers[2]

# Parse metadata and build [date_str, hour] -> row-index lookup
meta = raw_rows.map.with_index do |row, i|
  date = Date.strptime(row[date_col], "%m/%d/%Y") rescue nil
  hour = parse_hour(row[time_col])
  [i, date, hour]
end

lookup = {}
meta.each do |(i, date, hour)|
  next unless date && hour
  lookup[[raw_rows[i][date_col], hour]] = i
end

# -- Compute deltas so overlapping shifts are handled correctly ----------------
deltas  = Array.new(raw_rows.length, 0.0)
skipped = 0

meta.each do |(i, date, hour)|
  next unless date && hour
  next unless hour_map.key?(hour)
  next unless matches_day?(date, options[:days])

  dest_key = [raw_rows[i][date_col], hour_map[hour]]
  dest_idx = lookup[dest_key]
  unless dest_idx
    skipped += 1
    next
  end

  deltas[i]        -= options[:kwh]
  deltas[dest_idx] += options[:kwh]
end

# -- Write output --------------------------------------------------------------
negative_count = 0
CSV.open(options[:output], "w") do |csv|
  csv << csv_headers
  raw_rows.each_with_index do |row, i|
    new_row = row.dup
    unless deltas[i].zero?
      new_val = (row[kwh_col].to_f + deltas[i]).round(4)
      negative_count += 1 if new_val < 0
      new_row[kwh_col] = new_val.to_s
    end
    csv << csv_headers.map { |h| new_row[h] }
  end
end

modified      = deltas.count { |d| !d.zero? }
total_per_day = source_hours.length * options[:kwh]

puts ""
puts "Load shift applied."
puts "  Source:         #{options[:source]}  (#{source_hours.map { |h| "#{h}:00" }.join(", ")})"
puts "  Destination:    #{options[:dest]}  (#{dest_hours.map { |h| "#{h}:00" }.join(", ")})"
puts "  kWh/hr:         #{options[:kwh]}"
puts "  Max shift/day:  #{total_per_day} kWh  (#{source_hours.length} hrs x #{options[:kwh]} kWh)"
puts "  Days:           #{options[:days]}"
puts "  Rows modified:  #{modified}"
puts "  Output:         #{options[:output]}"
warn "  Skipped #{skipped} source rows with no matching destination row." if skipped > 0
warn "  Warning: #{negative_count} rows have negative kWh after shifting (source had less than #{options[:kwh]} kWh available)." if negative_count > 0
