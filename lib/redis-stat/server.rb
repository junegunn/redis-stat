require 'sinatra/base'
require 'json'
require 'thread'
require 'set'

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
    set :mutex, Mutex.new

    set :clients,    Set.new
    set :history,    []
    set :last_error, nil
  end

  helpers do
    def sync
      settings.mutex.synchronize { yield }
    end
  end

  not_found do
    redirect '/'
  end

  get '/' do
    redis_stat    = settings.redis_stat
    @hosts        = redis_stat.hosts
    @measures     = redis_stat.measures
    @tab_measures = redis_stat.tab_measures
    @interval     = redis_stat.interval
    @verbose      = redis_stat.verbose ? 'verbose' : ''
    @history      = sync { settings.history.dup }

    info = redis_stat.info rescue nil
    sync do
      @info = info ? (settings.last_info = info) : settings.last_info
    end
    erb :index
  end

  get '/pull' do
    content_type 'text/event-stream'

    if RUBY_PLATFORM == 'java'
      data =
        sync {
          if settings.last_error
            { :error => settings.last_error }
          elsif last = settings.history.last
            last
          else
            {}
          end
        }.to_json
      body "retry: #{settings.redis_stat.interval * 900}\ndata: #{data}\n\n"
    else
      stream(:keep_open) do |out|
        sync do
          settings.clients << out
          out.callback { settings.clients.delete out }
        end
      end
    end
  end

  class << self
    def wait_until_running
      while !RedisStat::Server.running?
        sleep 0.5
      end
    end

    def push hosts, info, data, error
      static = Hash[settings.redis_stat.tab_measures.map { |stat|
        [stat, hosts.map { |h| info[:instances][h][stat] }]
      }]
      data = {:at      => (Time.now.to_f * 1000).to_i,
              :static  => static,
              :dynamic => data,
              :error   => error}

      settings.mutex.synchronize do
        settings.last_error = nil
        hist = settings.history
        hist << data
        hist.shift if hist.length > HISTORY_LENGTH
      end
      publish data
    end

    def alert error
      settings.mutex.synchronize do
        settings.last_error = error
      end
      publish({ :error => error })
    end

  private
    def publish data
      clients = settings.mutex.synchronize { settings.clients.dup }
      return if clients.empty?

      resp = "data: #{data.to_json}\n\n"
      clients.each do |cl|
        cl << resp
      end
    end
  end
end#Server
end#RedisStat

