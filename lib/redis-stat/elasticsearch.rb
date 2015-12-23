require 'elasticsearch'
require 'date'
require 'uri'

class RedisStat
class ElasticsearchSink
  attr_reader :hosts, :info, :index, :client

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

  def initialize hosts, elasticsearch, tags = nil
    url, @index  = elasticsearch
    @hosts       = hosts
    @tags = tags || []
    @client      = Elasticsearch::Client.new :url => url
  end

  def output info
    @hosts.each do |host|
      entries = Hash[info.map { |k, v|
        if v.has_key?(host) && raw = v[host].last
          [k, raw]
        end
      }.compact]
      next if entries.empty?

      time = entries[:at]
      entry = {
        :index => index,
        :type  => "redis",
        :body  => entries.merge({
          :@timestamp => format_time(time),
          :host       => host,
          :at         => time.to_f,
          :tags       => @tags
        }),
      }

      client.index entry
    end
  end

private
  if RUBY_VERSION.start_with? '1.8.'
    def format_time time
      fmt = time.strftime("%FT%T%z")
      fmt[0..-3] + ':' + fmt[-2..-1]
    end
  else
    def format_time time
      time.strftime("%FT%T%:z")
    end
  end
end
end

