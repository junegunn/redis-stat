require 'sinatra/base'
require 'json'

class RedisStat
class Server < Sinatra::Base
  HISTORY_LENGTH  = 50
  STAT_TABLE_ROWS = 10

  configure do
    unless RUBY_PLATFORM == 'java'
      require 'thin'
      set :server, :thin
    end
    set :environment, :production
    set :root, File.join( File.dirname(__FILE__), 'server' )
    set :clients, []
    set :history, []
  end

  get '/' do
    @hosts    = settings.redis_stat.hosts
    @info     = settings.redis_stat.info
    @measures = settings.redis_stat.measures
    @verbose  = settings.redis_stat.verbose ? 'verbose' : ''
    @history  = settings.history
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
        sleep 0.5
      end
    end

    def push info, data
      static = Hash[RedisStat::MEASURES[:static].map { |stat|
        [stat, info[stat]]
      }]
      data = {:static => static, :dynamic => data}

      @history = settings.history
      @history << data
      @history.shift if @history.length > HISTORY_LENGTH

      resp = "data: #{data.to_json}\n\n"
      settings.clients.each do |cl|
        cl << resp
      end
    end
  end
end#Server
end#RedisStat

