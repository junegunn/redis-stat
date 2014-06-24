require 'elasticsearch'
require 'date'

class ElasticsearchOutputter
  attr_reader :hosts, :info, :client

  TO_I = {
    :process_id              => true,
    :uptime_in_seconds       => true,
    :uptime_in_days          => true,
    :connected_slaves        => true,
    :aof_enabled             => true,
    :rdb_bgsave_in_progress  => true,
    :rdb_last_save_time      => true,
  }

  def initialize hosts, info, elasticsearch, index
    @hosts  = hosts
    @info   = info
    @client = Elasticsearch::Client.new url: elasticsearch
    @index  = index
  end

  def link_hosts_to_info
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

  def convert_to_i
    info = link_hosts_to_info
    info.each do |host, entries|
      entries.each do |name, value|
        convert = RedisStat::LABELS[name] || TO_I[name]
        if convert
          entries[name] = value.to_i
        end
      end
    end
  end

  def index
    @index ||= "services"
  end

  def output
    results = convert_to_i
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
end
