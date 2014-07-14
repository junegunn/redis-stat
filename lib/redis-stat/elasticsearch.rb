require 'elasticsearch'
require 'date'
require 'uri'

class RedisStat
class ElasticsearchSink
  attr_reader :hosts, :info, :index, :client

  TO_I = {
    :process_id              => true,
    :uptime_in_seconds       => true,
    :uptime_in_days          => true,
    :connected_slaves        => true,
    :aof_enabled             => true,
    :rdb_bgsave_in_progress  => true,
    :rdb_last_save_time      => true,
  }

  DEFAULT_INDEX = 'redis-stat'

  def self.parse_url elasticsearch
    unless elasticsearch.match(%r[^https?://])
      elasticsearch = "http://#{elasticsearch}"
    end

    uri      = URI.parse elasticsearch
    path     = uri.path
    index    = path == '' ? DEFAULT_INDEX : path.split('/').last
    uri.path = ''

    [uri.to_s, index]
  end

  def initialize hosts, elasticsearch
    url, @index  = elasticsearch
    @hosts       = hosts
    @client      = Elasticsearch::Client.new :url => url
  end

  def output info
    convert_to_i(info).each do |host, entries|
      time = info[:at].to_i
      entry = {
        :index => index,
        :type  => "redis",
        :body  => entries.merge({
          :@timestamp => format_time(time),
          :host       => host,
          :at         => time
        }),
      }

      client.index entry
    end
  end

private
  if RUBY_VERSION.start_with? '1.8.'
    def format_time time
      fmt = Time.at(time).strftime("%FT%T%z")
      fmt[0..-3] + ':' + fmt[-2..-1]
    end
  else
    def format_time time
      Time.at(time).strftime("%FT%T%:z")
    end
  end

  def convert_to_i info
    Hash[info[:instances].map { |host, entries|
      output = {}
      entries.each do |name, value|
        convert = RedisStat::LABELS[name] || TO_I[name]
        if convert
          output[name] = value.to_i
        end
      end
      output.empty? ? nil : [host, output]
    }.compact]
  end
end
end

