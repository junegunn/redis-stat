require 'sinatra/base'
require 'json'
require 'thread'

class RedisStat
class Server < Sinatra::Base
  HISTORY_LENGTH  = 50
  STAT_TABLE_ROWS = 10

  configure do
    if RUBY_PLATFORM == 'java'
      require 'puma'
      set :server, :puma
    else
      require 'thin'
      set :server, :thin
    end
    set :environment, :production
    set :root, File.join( File.dirname(__FILE__), 'server' )
    set :clients, []
    set :history, []
    set :mutex, Mutex.new
  end

  get '/' do
    @hosts        = settings.redis_stat.hosts
    @info         = settings.redis_stat.info
    @measures     = settings.redis_stat.measures
    @tab_measures = settings.redis_stat.tab_measures
    @interval     = settings.redis_stat.interval
    @verbose      = settings.redis_stat.verbose ? 'verbose' : ''
    @history      = settings.history
    erb :index
  end

  get '/pull' do
    content_type 'text/event-stream'

    if RUBY_PLATFORM == 'java'
      if last = settings.mutex.synchronize { settings.history.last }
        body "retry: #{settings.redis_stat.interval * 900}\ndata: #{last.to_json}\n\n"
      end
    else
      stream(:keep_open) do |out|
        settings.clients << out
        out.callback { settings.clients.delete out }
      end
    end
  end

  class << self
    def wait_until_running
      while !RedisStat::Server.running?
        sleep 0.5
      end
    end

    def push info, data
      static = Hash[settings.redis_stat.tab_measures.map { |stat|
        [stat, info[stat]]
      }]
      data = {:at => Time.now.to_i, :static => static, :dynamic => data}

      hist = settings.history
      settings.mutex.synchronize do
        hist << data
        hist.shift if hist.length > HISTORY_LENGTH
      end

      return if settings.clients.empty?

      resp = "data: #{data.to_json}\n\n"
      settings.clients.each do |cl|
        cl << resp
      end
    end
  end
end#Server
end#RedisStat

