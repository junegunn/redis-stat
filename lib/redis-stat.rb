# encoding: utf-8

require 'redis-stat/version'
require 'redis-stat/constants'
require 'redis-stat/option'
require 'redis-stat/server'
require 'redis-stat/elasticsearch'
require 'insensitive_hash'
require 'redis'
require 'tabularize'
require 'ansi256'
require 'csv'
require 'parallelize'
require 'si'
require 'rbconfig'
require 'lps'
require 'readline'

class RedisStat
  attr_reader :hosts, :measures, :tab_measures, :verbose, :interval

  def initialize options = {}
    options = RedisStat::Option::DEFAULT.merge options
    windows = RbConfig::CONFIG['target_os'] =~ /mswin|mingw/

    Ansi256.enabled = STDOUT.tty? && !(windows || options[:mono])
    options[:style] = :ascii if windows

    @hosts         = options[:hosts]
    @interval      = options[:interval]
    @redises       = @hosts.inject({}) { |hash, e|
      host, port   = e.split(':')
      hash[e] = Redis.new(Hash[ {:host => host,
                                 :port => port,
                                 :timeout => @interval}.select { |k, v| v } ])
      hash
    }
    @max_count     = options[:count]
    @colors        = options[:colors] || COLORS
    @csv_file      = options[:csv_file]
    @csv_output    = options[:csv_output]
    @auth          = options[:auth]
    @verbose       = options[:verbose]
    @measures      = MEASURES[ @verbose ? :verbose : :default ].map { |m| [*m].first }
    @tab_measures  = MEASURES[:static].map { |m| [*m].first }
    @all_measures  = TYPES.keys
    @count         = 0
    @style         = options[:style]
    @varwidth      = STDOUT.tty? && !windows
    @first_batch   = true
    @server_port   = options[:server_port]
    @server_thr    = nil
    @daemonized    = options[:daemon]
    @elasticsearch = options[:es] && ElasticsearchSink.new(@hosts, options[:es])
  end

  def output_stream! stream
    if @csv_output
      class << $stderr
        alias puts! puts
        def puts(*args); end
        def print(*args); end
      end
      $stderr
    else
      class << stream
        alias puts! puts
      end
      stream
    end
  end

  def start stream
    @started_at = Time.now
    @os = output_stream!(stream)
    trap('INT') { Thread.main.raise Interrupt }

    begin
      csv = if @csv_file
              File.open(File.expand_path(@csv_file), 'w')
            elsif @csv_output
              $stdout
            end
      update_term_size!
      authenticate!

      # Initial info collection
      info, x = collect
      unless x.empty?
        output_term_errors! format_exceptions(x)
        exit 1
      end

      # Check elasticsearch status
      if @elasticsearch
        begin
          output_es Hash[process(info, nil)]
        rescue Exception => e
          output_term_errors! format_exceptions({ :elasticsearch => e })
          exit 1
        end
      end

      # Start web servers
      server = start_server(info) if @server_port

      # Main loop
      prev_info = nil
      LPS.interval(@interval).loop do
        info, exceptions =
          begin
            collect
          rescue Interrupt
            raise
          end

        if exceptions.any? { |k, v| need_auth? v }
          authenticate!
          next
        end

        info_output_all = process info, prev_info
        begin
          output_es Hash[info_output_all] if @elasticsearch && @count > 0
        rescue Interrupt
          raise
        rescue Exception => e
          exceptions[:elasticsearch] = e.to_s
        end
        error_messages = format_exceptions(exceptions)
        info_output = @measures.map { |key| [key, info_output_all[key][:sum]] }
        if !@daemonized && !@csv_output
          output_static_info info if @count == 0
          output_term info_output, error_messages
        end
        server.push @hosts, info, info_output_all, error_messages if server
        output_file info_output, csv if csv

        prev_info = info

        @count += 1
        break if @max_count && @count >= @max_count
      end
      @os.puts
    rescue Interrupt
      @os.puts
      @os.puts! "Interrupted.".yellow.bold
      if @server_thr
        @server_thr.raise Interrupt
        begin
          @server_thr.join
        rescue Interrupt
        end
      end
    rescue SystemExit
      raise
    rescue Exception => e
      @os.puts! e.to_s.red.bold
      raise
    ensure
      csv.close if csv
    end
    @os.puts! "Elapsed: #{"%.2f" % (Time.now - @started_at)} sec.".blue.bold
  end

private
  def start_server info
    RedisStat::Server.set :port, @server_port
    RedisStat::Server.set :redis_stat, self
    RedisStat::Server.set :last_info, info
    @server_thr = Thread.new {
      begin
        RedisStat::Server.run!
      rescue Interrupt
      end
      Thread.main.raise Interrupt
    }
    RedisStat::Server.wait_until_running
    trap('INT') { Thread.main.raise Interrupt }
    RedisStat::Server
  end

  module ExtendedHash
    def hosts host
      host == :sum ? self.values : [self[host]]
    end

    def vals host, label
      hosts(host).map { |hash| hash[label] }
    end

    def s host, label
      hosts(host).map { |hash| hash[label] }.join('/')
    end

    def i host, label
      f(host, label).to_i
    end

    def f host, label
      hosts(host).map { |hash|
        case label
        when Proc
          label.call(hash)
        else
          hash[label].to_f
        end
      }.inject(:+) || 0
    end

    def sub host, label, other
      case host
      when :sum
        keys.inject(0) { |sum, h| sum + sub(h, label, other) }
      else
        other[host].empty? ? 0 : (f(host, label) - other.f(host, label))
      end
    end
  end

  def collect
    info = Hash.new { |h, k| h[k] = {}.insensitive }.extend(ExtendedHash)
    exceptions = {}

    @hosts.pmap(@hosts.length) { |host|
      begin
        hash = { :at => Time.now }.insensitive
        [host, hash.merge(@redises[host].info)]
      rescue Exception => e
        [host, e]
      end
    }.each do |host, rinfo|
      if rinfo.is_a?(Exception)
        exceptions[host] = rinfo
      else
        (@all_measures + rinfo.keys.select { |k| k =~ /^db[0-9]+$/ }).each do |k|
          ks = [*k]
          v = ks.map { |e| rinfo[e] }.compact.first
          k = ks.first
          info[host][k] = v
        end
      end
    end
    [info, exceptions]
  end

  def update_term_size!
    if RUBY_PLATFORM == 'java'
      require 'java'
      begin
        @term ||= (Java::jline.console.ConsoleReader.new.getTerminal) rescue
                  (Java::jline.ConsoleReader.new.getTerminal)
        @term_width  = (@term.width rescue DEFAULT_TERM_WIDTH)
        @term_height = (@term.height rescue DEFAULT_TERM_HEIGHT) - 4
        return
      rescue Exception
        # Fallback to tput (which yields incorrect values as of now)
      end
    end

    @term_width, @term_height = tput_term_size
  end

  def tput_term_size
    return [DEFAULT_TERM_WIDTH, DEFAULT_TERM_HEIGHT - 4] if @term_fixed

    dim = %w[cols lines].map { |attr| (`tput #{attr}` || nil).to_i }
    if dim.index(0)
      @term_fixed = true
      return tput_term_size
    end
    [dim.first, dim.last - 4]
  end

  def move! lines
    return if lines == 0 || !@varwidth

    @os.print(
      if lines < 0
        "\e[#{- lines}A\e[0G"
      else
        "\e[#{lines}B\e[0G"
      end
    )
  end

  def format_exceptions exceptions
    if exceptions.empty?
      []
    else
      now = Time.now.strftime('%Y/%m/%d %H:%M:%S')
      exceptions.map { |h, x| "[#{now}@#{h}] #{x}" }
    end
  end

  def output_file info_output, file
    file.puts CSV.generate_line(info_output.map { |pair|
      LABELS[pair.first] || pair.first
    }) if @count == 0

    file.puts CSV.generate_line(info_output.map { |pair|
      case val = [*pair.last].last
      when Time
        val.to_f
      else
        val
      end
    })
    file.flush
  end

  def output_term_errors error_messages
    @_term_error_reported ||= false
    if error_messages.empty?
      @_term_error_reported = false
    else
      unless @_term_error_reported
        @os.puts
      end
      output_term_errors! error_messages
      @_term_error_reported = true
    end
  end

  def output_term_errors! error_messages
    @os.puts! error_messages.join($/).red.bold
  end

  def output_term info_output, error_messages
    return if output_term_errors error_messages

    @table ||= init_table info_output

    movement = nil
    if @count == 0
      movement = 0
    elsif @count % @term_height == 0
      @first_batch = false
      movement = -1
      update_term_size!
      @table = init_table info_output
    end

    # Build output table
    @table << info_output.map { |pair|
      # [ key, [ humanized, raw ] ]
      msg = [*pair.last].first
      colorize msg, *@colors[pair.first]
    }
    lines = @table.to_s.lines.map(&:chomp)
    lines.delete_at @first_batch ? 1 : 0
    width  = lines.first.length
    height = lines.length

    if @varwidth
      # Calculate the number of lines to go upward
      if movement.nil?
        if @prev_width && @prev_width == width
          lines = lines[-2..-1]
          movement = -1
        else
          movement = -(height - 1)
        end
      end
    else
      lines = movement ? lines[0..-2] : lines[-2..-2]
    end
    @prev_width = width

    move! movement
    begin
      @os.print $/ + lines.join($/)
      @os.flush
    rescue Interrupt
      move!(-movement)
      raise
    end
  end

  def output_static_info info
    tab = Tabularize.new(
      :unicode => false, :align => :right,
      :border_style => @style,
      :screen_width => @term_width
    )
    tab << [nil] + @hosts.map { |h| h.bold.green }
    tab.separator!
    @tab_measures.each do |key|
      tab << [key.to_s.bold] + @hosts.map { |host| info[host][key] }
    end
    @os.puts tab
  end

  def output_es info
    @elasticsearch.output info
  rescue Exception
    raise unless @daemonized
  end

  def init_table info_output
    table = Tabularize.new(
      :unicode      => false,
      :align        => :right,
      :border_style => @style,
      :border_color => (Ansi256.enabled? ? Ansi256.red : nil),
      :vborder      => ' ',
      :pad_left     => 0,
      :pad_right    => 0,
      :screen_width => @term_width)
    table.separator!
    table << info_output.map { |pair|
      key = pair.first
      colorize LABELS.fetch(key, key), :underline, *@colors[key]
    }
    table.separator!
    table
  end

  def process info, prev_info
    hosts = [:sum].concat(@hosts)
    Hash[@all_measures.map { |key|
      [ key,
        hosts.select { |h| info.has_key?(h) || h == :sum }.inject({}) { |sum, h|
          sum[h] = process_how(h, info, prev_info, key)
          sum
        }
      ]
    }]
  end

  def process_how host, info, prev_info, key
    dur = prev_info && begin
      max = info.vals(host, :at).compact.max
      min = prev_info.vals(host, :at).compact.min
      max && min && (max - min)
    end

    get_diff = lambda do |label|
      if dur && dur > 0
        [info.sub(host, label, prev_info) / dur, 0].max
      else
        nil
      end
    end

    case key
    when :at
      now = info.vals(host, :at).compact.max || Time.now
      [now.strftime('%H:%M:%S'), now]
    when :used_cpu_user, :used_cpu_sys
      val = get_diff.call(key)
      val &&= (val * 100).round
      [humanize_number(val), val]
    when :keys
      val = info.f(host, proc { |hash|
        Hash[ hash.select { |k, v| k =~ /^db[0-9]+$/ } ].values.inject(0) { |sum, vs|
          sum + Hash[ vs.split(',').map { |e| e.split '=' } ]['keys'].to_i
        }
      })
      [humanize_number(val), val]
    when :evicted_keys_per_second, :expired_keys_per_second, :keyspace_hits_per_second,
         :keyspace_misses_per_second, :total_commands_processed_per_second
      val = get_diff.call(key.to_s.gsub(/_per_second$/, '').to_sym)
      [humanize_number(val), val]
    when :used_memory, :used_memory_rss, :aof_current_size, :aof_base_size
      val = info.f(host, key)
      [humanize_number(val.to_i, true), val]
    when :keyspace_hit_ratio
      hits = info.f(host, :keyspace_hits)
      misses = info.f(host, :keyspace_misses)
      val = ratio(hits, misses)
      [humanize_number(val), val]
    when :keyspace_hit_ratio_per_second
      hits = get_diff.call(:keyspace_hits) || 0
      misses = get_diff.call(:keyspace_misses) || 0
      val = ratio(hits, misses)
      [humanize_number(val), val]
    else
      conv = TYPES.fetch key, :s
      val = info.send(conv, host, key)
      val.is_a?(String) ?
        [val, val] : [humanize_number(val), val]
    end
  end

  def ratio x, y
    if x > 0 || y > 0
      x / (x + y) * 100
    else
      nil
    end
  end

  def humanize_number num, byte = false
    return '-' if num.nil?

    num = num.to_i if num == num.to_i
    if byte
      num.si_byte
    else
      num.si(:min_exp => 0)
    end
  end

  def colorize str, *colors
    colors.each do |color|
      str = str.send color
    end
    str
  end

  def need_auth? e
    @auth && e.is_a?(Redis::CommandError) &&
      e.to_s =~ /NOAUTH|operation not permitted/
  end

  def authenticate!
    @redises.values.each do |r|
      r.ping rescue (r.auth @auth)
    end if @auth
  end
end
