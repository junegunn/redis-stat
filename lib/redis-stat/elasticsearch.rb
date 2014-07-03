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
    results = convert_to_i info
    results.map do |host, entries|
      time = entries[:at]
      entry = {
        :index => index,
        :type  => "redis",
        :body  => entries.merge({
          :@timestamp => Time.at(time).strftime("%FT%T%:z"),
          :host       => host
        }),
      }

      client.index entry
    end
  end

private
  def link_hosts_to_info info
    {}.tap do |output|
      hosts.each_with_index do |host, index|
        output[host] = {}.tap do |host_output|
          info.each do |name, entries|
            value = name == :at ? entries : entries[index]
            host_output[name] = value
          end
        end
      end
    end
  end

  def convert_to_i info
    info = link_hosts_to_info info
    info.each do |host, entries|
      entries.each do |name, value|
        convert = RedisStat::LABELS[name] || TO_I[name]
        if convert
          entries[name] = value.to_i
        end
      end
    end
  end
end
end

