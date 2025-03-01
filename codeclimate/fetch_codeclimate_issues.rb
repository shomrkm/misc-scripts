#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'optparse'

module CodeClimate
  class Error < StandardError; end
  class APIError < Error; end
  class ConfigurationError < Error; end

  class Configuration
    attr_reader :token, :repo_id

    def initialize(token:, repo_id:)
      validate_params(token, repo_id)
      @token = token
      @repo_id = repo_id
    end

    private

    def validate_params(token, repo_id)
      raise ConfigurationError, 'Token is required' if token.nil? || token.empty?
      raise ConfigurationError, 'Repository ID is required' if repo_id.nil? || repo_id.empty?
    end
  end

  class Client
    BASE_URL = 'https://api.codeclimate.com/v1'
    ACCEPT_HEADER = 'application/vnd.api+json'

    def initialize(config)
      @config = config
    end

    def fetch_latest_issues(page_size: 3)
      snapshot_id = fetch_latest_snapshot_id
      fetch_issues(snapshot_id, page_size)
    rescue JSON::ParserError => e
      handle_json_error(e)
    rescue StandardError => e
      handle_general_error(e)
    end

    private

    def fetch_latest_snapshot_id
      uri = URI("#{BASE_URL}/repos/#{@config.repo_id}")
      response = send_request(uri)
      data = parse_json_response(response)
      
      snapshot_id = extract_snapshot_id(data)
      raise APIError, 'No snapshot ID found in response' unless snapshot_id

      snapshot_id
    end

    def extract_snapshot_id(data)
      return nil unless data['data'] && data['data']['relationships']
      return nil unless data['data']['relationships']['latest_default_branch_snapshot']
      
      data['data']['relationships']['latest_default_branch_snapshot']['data']['id']
    end

    def fetch_issues(snapshot_id, page_size)
      uri = build_issues_uri(snapshot_id, page_size)
      response = send_request(uri)
      parse_json_response(response)
    end

    def build_issues_uri(snapshot_id, page_size)
      uri = URI("#{BASE_URL}/repos/#{@config.repo_id}/snapshots/#{snapshot_id}/issues")
      uri.query = URI.encode_www_form('page[size]' => page_size.to_s)
      uri
    end

    def send_request(uri)
      request = build_request(uri)
      send_http_request(uri, request)
    end

    def build_request(uri)
      request = Net::HTTP::Get.new(uri)
      request['Accept'] = ACCEPT_HEADER
      request['Authorization'] = "Token token=#{@config.token}"
      request
    end

    def send_http_request(uri, request)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      handle_response_status(response)
      response
    end

    def handle_response_status(response)
      return if response.is_a?(Net::HTTPSuccess)

      raise APIError, "Request failed with status: #{response.code} - #{response.message}"
    end

    def parse_json_response(response)
      JSON.parse(response.body)
    end

    def handle_json_error(error)
      {
        'error' => {
          'type' => 'JSON Parse Error',
          'message' => error.message
        }
      }
    end

    def handle_general_error(error)
      {
        'error' => {
          'type' => error.class.name,
          'message' => error.message
        }
      }
    end
  end

  class CLI
    def self.run(args)
      new.run(args)
    end

    def run(args)
      options = parse_options(args)
      
      config = Configuration.new(
        token: options[:token],
        repo_id: options[:repo_id]
      )

      client = Client.new(config)
      result = client.fetch_latest_issues(page_size: options[:page_size])

      puts JSON.pretty_generate(result)
    rescue Error => e
      abort "Error: #{e.message}"
    rescue OptionParser::InvalidOption => e
      abort "Error: #{e.message}\nUse --help for usage information."
    end

    private

    def parse_options(args)
      options = {
        token: ENV['CODECLIMATE_API_TOKEN'],
        repo_id: nil,
        page_size: 3
      }

      parser = create_option_parser(options)
      parser.parse!(args)

      validate_options(options, parser)
      options
    end

    def create_option_parser(options)
      OptionParser.new do |opts|
        opts.banner = "Usage: #{File.basename($PROGRAM_NAME)} [options]"

        opts.on('-t', '--token TOKEN', 'CodeClimate API token (can also be set via CODECLIMATE_API_TOKEN env var)') do |token|
          options[:token] = token
        end

        opts.on('-r', '--repo-id REPO_ID', 'Repository ID') do |repo_id|
          options[:repo_id] = repo_id
        end

        opts.on('-p', '--page-size SIZE', Integer, 'Number of issues per page (default: 3)') do |size|
          options[:page_size] = size
        end

        opts.on('-h', '--help', 'Show this help message') do
          puts opts
          exit
        end

        opts.separator "\nExample:"
        opts.separator "  #{File.basename($PROGRAM_NAME)} --token abc123 --repo-id def456"
        opts.separator "  #{File.basename($PROGRAM_NAME)} --repo-id def456  # using CODECLIMATE_API_TOKEN env var"
      end
    end

    def validate_options(options, parser)
      if options[:token].nil? || options[:token].empty?
        puts parser
        abort "\nError: API token is required. Provide it via --token option or CODECLIMATE_API_TOKEN env var."
      end

      if options[:repo_id].nil? || options[:repo_id].empty?
        puts parser
        abort "\nError: Repository ID is required. Provide it via --repo-id option."
      end
    end
  end
end

CodeClimate::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__

# Usage: fetch_codeclimate_issues.rb [Options]
#     -t, --token TOKEN                CodeClimate API token (can also be set via CODECLIMATE_API_TOKEN env var)
#     -r, --repo-id REPO_ID            Repository ID
#     -p, --page-size SIZE             Number of issues per page (default: 3)
#     -h, --help                       Show this help message
#
# Example:
#   fetch_codeclimate_issues.rb --token abc123 --repo-id def456
#   fetch_codeclimate_issues.rb --repo-id def456  # using CODECLIMATE_API_TOKEN env var
#