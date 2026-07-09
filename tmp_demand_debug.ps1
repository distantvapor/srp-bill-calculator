require './power.rb'
require 'csv'
options = { provider: 'srp', exclude_solar_plans: true }
logger = Logger.new($stderr)
root = Plans::SRP
plans = root::PLANS.reject { |c| c.solar_eligible if true }.map { |c| c.new(logger, nil, options) }
md = plans.find { |p| p.is_a?(Plans::SRP::ManageDemand) }
CSV.open('./hourlyUsage7_1_2025_to_06_30_2026.csv', headers: true).each do |row|
  row[0] = Date.strptime(row[0], '%m/%d/%Y') rescue nil
  next unless row[0]
  date = row[0]
  time = Time.parse(row[1])
  datetime = Time.local(date.year, date.month, date.day, time.hour, time.min, time.sec)
  md.add(datetime, row[2].to_f)
end
puts "hours=#{md.instance_variable_get(:@hours)}"
puts "months=#{md.instance_variable_get(:@months)}"
puts "total=#{md.total}"
puts "usage_total=#{md.usage_total}"
puts "total_fixed=#{md.total_fixed_charges}"
puts "total_demand_charge=#{md.total_demand_charge}"
puts "energy_total=#{md.energy_total}"
puts "last_date=#{md.instance_variable_get(:@last_date)}"
puts "last_peak=#{md.demand_for_period(md.instance_variable_get(:@last_date))}"
puts "rate_last=#{md.demand_rate(md.instance_variable_get(:@last_date))}"
puts "demand_total_raw=#{md.instance_variable_get(:@demand_total)}"
puts "periods=#{md.instance_variable_get(:@demand_by_month).map{|k,v| [k,v.length, v.max]}.inspect}"
