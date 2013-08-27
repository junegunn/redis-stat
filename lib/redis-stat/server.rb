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
    set :error, nil
    set :last_info, nil
    set :mutex, Mutex.new
  end

  get '/' do
    @hosts        = settings.redis_stat.hosts
    @measures     = settings.redis_stat.measures
    @tab_measures = settings.redis_stat.tab_measures
    @interval     = settings.redis_stat.interval
    @verbose      = settings.redis_stat.verbose ? 'verbose' : ''
    @history      = settings.history
    @info         =
      begin
        settings.mutex.synchronize do
          settings.last_info = settings.redis_stat.info
        end
      rescue Exception => e
        settings.last_info || raise
      end
    erb :index
  end

  get '/pull' do
    content_type 'text/event-stream'

    if RUBY_PLATFORM == 'java'
      data =
        settings.mutex.synchronize {
          if settings.error
            { :error => settings.error }
          elsif last = settings.history.last
            last
          else
            {}
          end
        }.to_json
      body "retry: #{settings.redis_stat.interval * 900}\ndata: #{data}\n\n"
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
      data = {:at => (Time.now.to_f * 1000).to_i, :static => static, :dynamic => data}

      settings.mutex.synchronize do
        settings.error = nil
        hist = settings.history
        hist << data
        hist.shift if hist.length > HISTORY_LENGTH
      end

      return if settings.clients.empty?

      resp = "data: #{data.to_json}\n\n"
      settings.clients.each do |cl|
        cl << resp
      end
    end

    def alert error
      settings.error = error

      return if settings.clients.empty?
      resp = "data: #{{ :error => error }.to_json}\n\n"
      settings.clients.each do |cl|
        cl << resp
      end
    end
  end
end#Server
end#RedisStat

