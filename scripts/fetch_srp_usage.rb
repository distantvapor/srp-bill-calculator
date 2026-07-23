#!/usr/bin/env ruby
# fetch_srp_usage.rb -- Fetch hourly kWh usage from the SRP myaccount API
# and write a CSV compatible with power.rb.
#
# Uses curl for all HTTP requests -- curl's TLS fingerprint passes Cloudflare's
# JA3 bot detection where Ruby's Net::HTTP does not.
#
# Credentials resolved in order:
#   1. Environment variables  (SRP_USERNAME, SRP_PASSWORD, SRP_ACCOUNT_ID)
#   2. .env file in current dir or script parent dir
#   3. Interactive prompt

require "json"
require "csv"
require "date"
require "optparse"
require "io/console"
require "open3"
require "tempfile"
require "uri"

BASE_URL   = "https://myaccount.srpnet.com"
API_BASE   = "#{BASE_URL}/myaccountapi/api"
PORTAL_URL = "#{BASE_URL}/myaccount/"
LOGIN_URL  = "#{API_BASE}/login/authorize"
XSRF_URL   = "#{API_BASE}/login/antiforgerytoken"
USAGE_URL  = "#{API_BASE}/usage/hourlydetail"

BROWSER_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

# -- .env loader ---------------------------------------------------------------
def load_dotenv
  candidates = [
    File.join(Dir.pwd, ".env"),
    File.join(File.dirname(File.expand_path(__FILE__)), "..", ".env"),
  ]
  candidates.each do |path|
    next unless File.exist?(path)
    File.readlines(path).each do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")
      key, value = line.split("=", 2)
      next unless key && value
      ENV[key.strip] ||= value.strip.gsub(/\A['"]|['"]\z/, "")
    end
    break
  end
end

def prompt_credential(name, label, secret: false)
  val = ENV[name]
  return val if val && !val.empty?
  $stderr.print "  #{label}: "
  val = secret ? $stdin.noecho(&:gets).tap { $stderr.puts } : $stdin.gets
  val&.chomp
end

# -- curl wrapper --------------------------------------------------------------
def curl_request(method, url, cookie_jar:, data: nil, headers: {}, extra: [])
  cmd = [
    "curl", "-s", "--compressed", "-L",
    "-A", BROWSER_UA,
    "-b", cookie_jar,
    "-c", cookie_jar,
    "-w", "\n===HTTP_CODE===%{http_code}",
    "-H", "Origin: #{BASE_URL}",
    "-H", "Referer: #{PORTAL_URL}",
    "-H", "Accept: application/json, text/plain, */*",
    "-H", "Accept-Language: en-US,en;q=0.9",
    "-H", "sec-fetch-dest: empty",
    "-H", "sec-fetch-mode: cors",
    "-H", "sec-fetch-site: same-origin",
    "-H", "sec-ch-ua: \"Chromium\";v=\"124\", \"Google Chrome\";v=\"124\"",
    "-H", "sec-ch-ua-mobile: ?0",
    "-H", "sec-ch-ua-platform: \"Windows\"",
  ]
  if method == :post
    cmd += ["-X", "POST", "-H", "Content-Type: application/x-www-form-urlencoded"]
    cmd += ["--data-raw", data.to_s]
  end
  headers.each { |k, v| cmd += ["-H", "#{k}: #{v}"] }
  cmd += extra
  cmd << url

  stdout, stderr, _status = Open3.capture3(*cmd)

  if (m = stdout.match(/\n===HTTP_CODE===(\d+)\z/))
    code = m[1].to_i
    body = stdout[0, stdout.rindex("\n===HTTP_CODE===")]
  else
    $stderr.puts "curl stderr: #{stderr}" unless stderr.empty?
    code = 0
    body = stdout
  end
  [code, body]
end

def safe_print(body)
  body.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")[0, 600]
end

# -- Auth sequence -------------------------------------------------------------
def authenticate(username, password, cookie_jar)
  $stderr.puts "Warming up session..."
  code, _body = curl_request(:get, PORTAL_URL, cookie_jar: cookie_jar,
    extra: ["-H", "Accept: text/html,application/xhtml+xml,*/*",
            "-H", "sec-fetch-dest: document",
            "-H", "sec-fetch-mode: navigate"])
  $stderr.puts "  Warm-up HTTP #{code}"

  $stderr.puts "Logging in as #{username}..."
  data = URI.encode_www_form("username" => username, "password" => password)
  code, body = curl_request(:post, LOGIN_URL, cookie_jar: cookie_jar, data: data)

  unless (200..399).cover?(code)
    $stderr.puts "Login response: #{safe_print(body)}"
    abort "Login failed (HTTP #{code}). Check username/password."
  end
  $stderr.puts "Login OK (HTTP #{code})"

  $stderr.puts "Fetching XSRF token..."
  code, body = curl_request(:get, XSRF_URL, cookie_jar: cookie_jar)

  xsrf_token = nil
  File.readlines(cookie_jar).each do |line|
    next if line.start_with?("#") || line.strip.empty?
    parts = line.strip.split("\t")
    if parts.last(2).first&.downcase == "xsrf-token"
      xsrf_token = URI.decode_www_form_component(parts.last.to_s)
      break
    end
  end

  if (xsrf_token.nil? || xsrf_token.empty?) && !body.empty?
    parsed = JSON.parse(body) rescue {}
    xsrf_token = parsed["xsrfToken"] || parsed["token"]
  end

  if xsrf_token.nil? || xsrf_token.empty?
    $stderr.puts "Cookie jar contents:"
    $stderr.puts File.read(cookie_jar)
    $stderr.puts "Response body: #{safe_print(body)}"
    abort "Could not retrieve xsrf-token from cookie jar or response body."
  end

  $stderr.puts "XSRF token acquired."
  xsrf_token
end

# -- CSV helpers ---------------------------------------------------------------
def to_srp_interval(iso_str)
  h = iso_str[11, 2].to_i
  if    h == 0  then "12:0 AM"
  elsif h < 12  then "#{h}:0 AM"
  elsif h == 12 then "12:0 PM"
  else               "#{h - 12}:0 PM"
  end
end

def to_srp_date(iso_str)
  y, m, d = iso_str[0, 10].split("-").map(&:to_i)
  "#{m}/#{d}/#{y}"
end

# -- Option parsing ------------------------------------------------------------
options = {}
parser = OptionParser.new do |opts|
  opts.banner = <<~BANNER

    Usage: fetch_srp_usage.rb --start MM-DD-YYYY --end MM-DD-YYYY [options]

    Fetches hourly kWh usage from the SRP myaccount API and writes a CSV
    compatible with power.rb. Credentials resolved from (in order):
      1. Env vars:  SRP_USERNAME, SRP_PASSWORD, SRP_ACCOUNT_ID
      2. .env file in current dir or script parent dir
      3. Interactive prompt

    Options:
  BANNER
  opts.on("--start DATE",  "Start date MM-DD-YYYY") { |v| options[:start]  = v }
  opts.on("--end DATE",    "End date MM-DD-YYYY")   { |v| options[:end]    = v }
  opts.on("--output FILE", "Output CSV (default: srp_usage_START_END.csv)") { |v| options[:output] = v }
end
parser.parse!

%i[start end].each { |k| abort "Missing --#{k}\n\n#{parser.help}" if options[k].nil? }
begin
  Date.strptime(options[:start], "%m-%d-%Y")
  Date.strptime(options[:end],   "%m-%d-%Y")
rescue ArgumentError
  abort "Dates must be in MM-DD-YYYY format (e.g. 07-01-2025)"
end

# -- Resolve credentials -------------------------------------------------------
load_dotenv
needs_prompt = [ENV["SRP_USERNAME"], ENV["SRP_PASSWORD"], ENV["SRP_ACCOUNT_ID"]].any?(&:nil?)
$stderr.puts "Enter SRP credentials (press Enter to skip fields already in .env/env vars):" if needs_prompt

username = prompt_credential("SRP_USERNAME", "SRP username (email)")
abort "Username is required." if username.nil? || username.empty?

password = prompt_credential("SRP_PASSWORD", "SRP password", secret: true)
abort "Password is required." if password.nil? || password.empty?

account_id = prompt_credential("SRP_ACCOUNT_ID", "SRP billing account number (9 digits)")
abort "Account ID is required." if account_id.nil? || account_id.empty?
abort "Account ID must be exactly 9 digits (got: #{account_id.inspect})." unless account_id =~ /\A\d{9}\z/

# -- Run -----------------------------------------------------------------------
cookie_jar = Tempfile.new(["srp_cookies", ".txt"])
cookie_jar.write("# Netscape HTTP Cookie File\n")
cookie_jar.flush
cookie_jar_path = cookie_jar.path

begin
  xsrf_token = authenticate(username, password, cookie_jar_path)

  # -- Build monthly chunks ---------------------------------------------------
  # <=31 days total: single API call.
  # >31 days: split on calendar month boundaries, first/last chunk clipped to
  # the requested start/end dates.
  start_date = Date.strptime(options[:start], "%m-%d-%Y")
  end_date   = Date.strptime(options[:end],   "%m-%d-%Y")
  total_days = (end_date - start_date).to_i + 1

  chunks = if total_days <= 31
    [[start_date, end_date]]
  else
    result = []
    chunk_start = start_date
    while chunk_start <= end_date
      chunk_end = Date.new(chunk_start.year, chunk_start.month, -1)  # last day of month
      chunk_end = end_date if chunk_end > end_date
      result << [chunk_start, chunk_end]
      chunk_start = chunk_end + 1
    end
    result
  end

  output_file = options[:output] || "srp_usage_#{options[:start].tr('-','')}_#{options[:end].tr('-','')}.csv"
  chunk_label = chunks.length > 1 ? " (#{chunks.length} monthly chunks)" : ""
  $stderr.puts "Fetching hourly usage #{options[:start]} to #{options[:end]}#{chunk_label}..."

  # -- Fetch each chunk and accumulate ----------------------------------------
  all_entries = []
  chunks.each_with_index do |(chunk_start, chunk_end), i|
    fmt_start = chunk_start.strftime("%m-%d-%Y")
    fmt_end   = chunk_end.strftime("%m-%d-%Y")
    $stderr.puts "  [#{i + 1}/#{chunks.length}] #{fmt_start} -> #{fmt_end}"

    query = URI.encode_www_form("billaccount" => account_id,
                                "beginDate"   => fmt_start,
                                "endDate"     => fmt_end)
    code, body = curl_request(:get, "#{USAGE_URL}?#{query}", cookie_jar: cookie_jar_path,
                              headers: { "x-xsrf-token" => xsrf_token })

    unless (200..299).cover?(code)
      $stderr.puts "  Raw: #{safe_print(body)}"
      abort "Usage request failed on chunk #{fmt_start}-#{fmt_end} (HTTP #{code})"
    end

    data    = JSON.parse(body)
    entries = data["hourlyUsageList"] || []
    if entries.empty?
      $stderr.puts "  Warning: no hourlyUsageList for #{fmt_start}-#{fmt_end}. Keys: #{data.keys.join(', ')}"
    else
      $stderr.puts "  #{entries.length} records"
      all_entries.concat(entries)
    end
  end

  abort "No records returned for any chunk." if all_entries.empty?
  $stderr.puts "Total: #{all_entries.length} hourly records."

  # -- Write consolidated CSV -------------------------------------------------
  CSV.open(output_file, "w") do |csv|
    csv << ["Usage date", "Interval", "Total kWh"]
    all_entries.each do |row|
      kwh = row["totalKwh"].to_f == 0.0 ?
        [row["onPeakKwh"], row["offPeakKwh"], row["shoulderKwh"], row["superOffPeakKwh"]].map(&:to_f).sum.round(4) :
        row["totalKwh"].to_f
      csv << [to_srp_date(row["date"]), to_srp_interval(row["hour"]), kwh]
    end
  end

  puts ""
  puts "SRP usage fetched."
  puts "  Period:   #{options[:start]} to #{options[:end]}"
  puts "  Chunks:   #{chunks.length}"
  puts "  Records:  #{all_entries.length}"
  puts "  Output:   #{output_file}"
  puts ""
  puts "Run power.rb with:"
  puts "  ruby power.rb -f #{output_file} [options]"

ensure
  cookie_jar.close
  cookie_jar.unlink rescue nil
end
