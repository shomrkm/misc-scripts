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

    def fetch_latest_issues
      snapshot_id = fetch_latest_snapshot_id
      fetch_all_issues(snapshot_id)
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

    def fetch_all_issues(snapshot_id)
      page = 1
      all_issues = { 'data' => [] }

      loop do
        uri = build_issues_uri(snapshot_id, page)
        response = send_request(uri)
        data = parse_json_response(response)
        
        break if data['data'].empty?
        
        all_issues['data'].concat(data['data'])
        page += 1
      end

      all_issues
    end

    def build_issues_uri(snapshot_id, page)
      uri = URI("#{BASE_URL}/repos/#{@config.repo_id}/snapshots/#{snapshot_id}/issues")
      uri.query = URI.encode_www_form(
        'page[size]' => '100',
        'page[number]' => page.to_s
      )
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

  class LanguageCounter
    EXTENSION_TO_LANGUAGE = {
      '.rb' => 'Ruby',
      '.js' => 'JavaScript',
      '.jsx' => 'JavaScript',
      '.ts' => 'TypeScript',
      '.tsx' => 'TypeScript',
      '.py' => 'Python',
      '.php' => 'PHP',
      '.java' => 'Java',
      '.go' => 'Go',
      '.rs' => 'Rust',
      '.c' => 'C',
      '.cpp' => 'C++',
      '.h' => 'C/C++',
      '.hpp' => 'C++',
      '.cs' => 'C#',
      '.swift' => 'Swift',
      '.kt' => 'Kotlin',
      '.scala' => 'Scala',
      '.ex' => 'Elixir',
      '.exs' => 'Elixir',
      '.erl' => 'Erlang',
      '.fs' => 'F#',
      '.r' => 'R',
      '.dart' => 'Dart',
      '.vue' => 'Vue',
      '.sql' => 'SQL',
      '.html' => 'HTML',
      '.htm' => 'HTML',
      '.css' => 'CSS',
      '.scss' => 'SCSS',
      '.sass' => 'SASS',
      '.less' => 'LESS',
      '.sh' => 'Shell',
      '.bash' => 'Shell',
      '.zsh' => 'Shell',
      '.yml' => 'YAML',
      '.yaml' => 'YAML',
      '.json' => 'JSON',
      '.md' => 'Markdown',
      '.markdown' => 'Markdown',
      '.xml' => 'XML',
      '.pl' => 'Perl',
      '.pm' => 'Perl',
      '.t' => 'Perl'
    }.freeze

    def self.count_languages(issues_data)
      return {} unless issues_data['data']

      language_counts = Hash.new(0)
      unknown_extensions = Set.new
      
      issues_data['data'].each do |issue|
        path = issue.dig('attributes', 'location', 'path')
        next unless path

        extension = File.extname(path).downcase
        if extension && !extension.empty?
          language = EXTENSION_TO_LANGUAGE[extension]
          if language
            language_counts[language] += 1
          else
            language_counts['Other'] += 1
            unknown_extensions.add(extension)
          end
        end
      end

      # Add a note about unknown extensions if any were found
      if language_counts['Other'] && !unknown_extensions.empty?
        language_counts['Other (extensions: ' + unknown_extensions.to_a.join(', ') + ')'] = 
          language_counts.delete('Other')
      end

      language_counts
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
      result = client.fetch_latest_issues
      
      # Only print language counts
      language_counts = LanguageCounter.count_languages(result)
      puts "\nProgramming Language Counts:"
      language_counts.sort.each do |lang, count|
        puts "#{lang}: #{count}"
      end
    rescue Error => e
      abort "Error: #{e.message}"
    rescue OptionParser::InvalidOption => e
      abort "Error: #{e.message}\nUse --help for usage information."
    end

    private

    def parse_options(args)
      options = {
        token: ENV['CODECLIMATE_API_TOKEN'],
        repo_id: nil
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

# Usage: fetch_codeclimate_issues_with_extension_count.rb [Options]
#     -t, --token TOKEN                CodeClimate API token (can also be set via CODECLIMATE_API_TOKEN env var)
#     -r, --repo-id REPO_ID            Repository ID
#     -h, --help                       Show this help message
#
# Example:
#   fetch_codeclimate_issues_with_extension_count.rb --token abc123 --repo-id def456
#   fetch_codeclimate_issues_with_extension_count.rb --repo-id def456  # using CODECLIMATE_API_TOKEN env var
