require 'sinatra/base'
require 'json'

class RedisStat
class Server < Sinatra::Base
  configure do
    unless RUBY_PLATFORM == 'java'
      require 'thin'
      set :server, :thin
    end
    set :environment, :production
    set :root, File.join( File.dirname(__FILE__), 'server' )
    set :clients, []
  end

  get '/' do
    @hosts    = settings.redis_stat.hosts
    @info     = settings.redis_stat.info
    @measures = settings.redis_stat.measures
    erb :index
  end

  get '/pull' do
    content_type 'text/event-stream'

    stream(:keep_open) do |out|
      settings.clients << out
      out.callback { settings.clients.delete out }
    end
  end

  class << self
    def wait_until_running
      while !RedisStat::Server.running?
        sleep 1
      end
    end

    def push info, data
      static = Hash[RedisStat::MEASURES[:static].map { |stat|
        [stat, info[stat]]
      }]

      data = [
        "retry: 1000",
        "data: #{{:static => static, :dynamic => data}.to_json}",
        "\n"
      ].join("\n")

      settings.clients.each do |cl|
        cl << data
      end
    end
  end
end#Server
end#RedisStat

