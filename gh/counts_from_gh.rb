require 'octokit'
require 'dotenv'
require 'set'
require 'csv'

Dotenv.load

REPO = 'kufu/utsuwa'
OUTPUT_FILE = './count.csv'

puts "### Start: #{DateTime.now.strftime("%Y-%m-%d %H:%M:%S")}"

per_page = 50
page = 1
one_year_ago = Date.today.prev_year

file_to_prs = Hash.new { |h, k| h[k] = Set.new }
while(true) do
  client = Octokit::Client.new(access_token: ENV['GITHUB_ACCESS_TOKEN'])
  pull_requests = client.pull_requests(REPO, state: 'closed', page: page, per_page: per_page)
  pull_requests.each do |pr|
    next if Date.parse(pr.created_at.to_s) < one_year_ago

    files = client.pull_request_files(REPO, pr.number)
    files.each do |file|
      ext = File.extname(file.filename)
      next unless %w[.ts .tsx].include?(ext)

      file_to_prs[file.filename].add(pr.number)
    end
  end

  puts "### Finished getting #{(page-1) * per_page + pull_requests.count} PRs"

  break if pull_requests.count != per_page
  page += 1
end

puts "### Finished All PRs"

CSV.open(OUTPUT_FILE, "w") do |csv|
  file_to_prs
    .sort_by { |file, prs| -prs.size }
    .each do |file, prs|
      csv << ["#{file}", "#{prs.size}"]
  end
end
puts "### Finished writing down to CSV file"

puts "### End: #{DateTime.now.strftime("%Y-%m-%d %H:%M:%S")}"
