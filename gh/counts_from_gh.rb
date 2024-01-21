require 'octokit'
require 'dotenv'
require 'set'

Dotenv.load

client = Octokit::Client.new(access_token: ENV['GITHUB_ACCESS_TOKEN'])
# ページネーションせずに一括でデータ取得するように設定する
client.auto_paginate = true

repo = 'kufu/smarthr-ui'
pull_requests = client.pull_requests(repo, state: 'closed')

one_year_ago = Date.today.prev_year

file_changes = Hash.new { |h, k| h[k] = Set.new }
pull_requests.each do |pr|
  next if Date.parse(pr.created_at.to_s) < one_year_ago

  files = client.pull_request_files(repo, pr.number)
  files.each do |file|
    file_changes[file.filename].add(pr.number)
  end
end

file_changes.each do |file, prs|
  puts "#{file}: #{prs.size} times changed"
end
