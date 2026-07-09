#!/usr/bin/env ruby
require 'csv'
require 'optparse'
require 'date'

options = { dir: nil, out: 'merged.csv', files: [] , sort: true }

optparser = OptionParser.new do |opts|
  opts.banner = "Usage: merge_csvs.rb [options] [file1.csv file2.csv ...]"

  opts.on('-d', '--dir DIR', 'Directory containing CSVs to merge') do |d|
    options[:dir] = d
  end

  opts.on('-o', '--out FILE', 'Output CSV file (default merged.csv)') do |o|
    options[:out] = o
  end

  opts.on('--[no-]sort', 'Sort output by date/time when possible (default: on)') do |s|
    options[:sort] = s
  end

  opts.on('-h', '--help', 'Prints this help') do
    puts opts
    exit
  end
end

optparser.parse!(ARGV)
options[:files] = ARGV.dup

if options[:dir]
  Dir.chdir(options[:dir]) do
    options[:files] += Dir.glob('*.csv').map { |f| File.join(options[:dir], f) }
  end
end

options[:files].uniq!

if options[:files].empty?
  puts "No files specified. Provide file paths or use --dir DIR"
  exit 1
end

puts "Merging #{options[:files].length} files into #{options[:out]}"

all_headers = []
rows = []

options[:files].each do |file|
  begin
    csv = CSV.read(file, headers: true)
  rescue => e
    warn "Failed reading #{file}: #{e.message} - skipping"
    next
  end

  headers = csv.headers.map(&:to_s)
  all_headers |= headers

  csv.each do |r|
    h = {}
    headers.each { |hh| h[hh] = r[hh] }
    # Keep original filename for traceability
    h['__source_file'] = File.basename(file)
    # Try to build a sortable datetime if possible
    dt = nil
    if h.key?('Date_Time') && h['Date_Time']
      begin
        dt = DateTime.parse(h['Date_Time'])
      rescue
      end
    elsif h.key?('Date') && h.key?('Time') && h['Date'] && h['Time']
      begin
        dt = DateTime.parse("#{h['Date']} #{h['Time']}")
      rescue
      end
    elsif h.key?('Usage date') && h.key?('Interval') && h['Usage date'] && h['Interval']
      begin
        dt = DateTime.parse("#{h['Usage date']} #{h['Interval']}")
      rescue
      end
    end
    h['__datetime'] = dt
    rows << h
  end
end

# Ensure source column included
all_headers |= ['__source_file']

if options[:sort]
  rows.sort_by! { |r| r['__datetime'] || DateTime.new(1970) }
end

CSV.open(options[:out], 'w', write_headers: true, headers: all_headers) do |out_csv|
  rows.each do |r|
    out_csv << all_headers.map { |h| r[h] }
  end
end

puts "Wrote #{rows.length} rows to #{options[:out]}"
