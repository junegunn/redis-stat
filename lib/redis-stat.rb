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
    @redises       = @hosts.inject({}) { |hash, e|
      host, port   = e.split(':')
      hash[e] = Redis.new(Hash[ {:host => host, :port => port, :timeout => DEFAULT_REDIS_TIMEOUT}.select { |k, v| v } ])
      hash
    }
    @interval      = options[:interval]
    @max_count     = options[:count]
    @colors        = options[:colors] || COLORS
    @csv           = options[:csv]
    @auth          = options[:auth]
    @verbose       = options[:verbose]
    @measures      = MEASURES[ @verbose ? :verbose : :default ].map { |m| [*m].first }
    @tab_measures  = MEASURES[:static].map { |m| [*m].first }
    @all_measures  = MEASURES.values.inject(:+).uniq - [:at]
    @count         = 0
    @style         = options[:style]
    @varwidth      = STDOUT.tty? && !windows
    @first_batch   = true
    @server_port   = options[:server_port]
    @server_thr    = nil
    @daemonized    = options[:daemon]
    @elasticsearch = options[:es] && ElasticsearchSink.new(@hosts, options[:es])
  end

  def start output_stream
    @started_at = Time.now
    @os = output_stream
    trap('INT') { Thread.main.raise Interrupt }

    begin
      csv = File.open(File.expand_path(@csv), 'w') if @csv
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
          output_es info
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

        begin
          output_es info if @elasticsearch && @count > 0
        rescue Exception => e
          exceptions[:elasticsearch] = e.to_s
        end
        error_messages = format_exceptions(exceptions)
        info_output = process info, prev_info
        unless @daemonized
          output_static_info info if @count == 0
          output_term info_output, error_messages
        end
        server.push @hosts, info, Hash[info_output], error_messages if server
        output_file info_output, csv if csv

        prev_info = info

        @count += 1
        break if @max_count && @count >= @max_count
      end
      @os.puts
    rescue Interrupt
      @os.puts
      @os.puts "Interrupted.".yellow.bold
      if @server_thr
        @server_thr.raise Interrupt
        @server_thr.join
      end
    rescue SystemExit
      raise
    rescue Exception => e
      @os.puts e.to_s.red.bold
      raise
    ensure
      csv.close if csv
    end
    @os.puts "Elapsed: #{"%.2f" % (Time.now - @started_at)} sec.".blue.bold
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
    }
    RedisStat::Server.wait_until_running
    trap('INT') { Thread.main.raise Interrupt }
    RedisStat::Server
  end

  def collect
    info = {
      :at => Time.now.to_f,
      :instances => Hash.new { |h, k| h[k] = {}.insensitive }
    }
    class << info
      def sumf label
        self[:instances].values.map { |hash| hash[label].to_f }.inject(:+) || 0
      end
    end
    exceptions = {}

    @hosts.pmap(@hosts.length) { |host|
      begin
        [host, @redises[host].info.insensitive]
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
          info[:instances][host][k] = v
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

    @term_width  = (`tput cols`  rescue DEFAULT_TERM_WIDTH).to_i
    @term_height = (`tput lines` rescue DEFAULT_TERM_HEIGHT).to_i - 4
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
      [*pair.last].last
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
    @os.puts error_messages.join($/).red.bold
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
      tab << [key.to_s.bold] + @hosts.map { |host| info[:instances][host][key] }
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
    @measures.map { |key|
      # [ key, [humanized, raw] ]
      [ key, process_how(info, prev_info, key) ]
    }.select { |pair| pair.last }
  end

  def process_how info, prev_info, key
    dur = prev_info && (info[:at] - prev_info[:at])

    get_diff = lambda do |label|
      if dur && dur > 0
        (info.sumf(label) - prev_info.sumf(label)) / dur
      else
        nil
      end
    end

    case key
    when :at
      val = Time.now.strftime('%H:%M:%S')
      [val, val]
    when :used_cpu_user, :used_cpu_sys
      val = get_diff.call(key)
      val &&= (val * 100).round
      [humanize_number(val), val]
    when :keys
      val = info[:instances].values.map { |hash|
        Hash[hash.select { |k, _| k =~ /^db[0-9]+$/ }].values.map { |v|
          Hash[ v.split(',').map { |e| e.split '=' } ]['keys'].to_i
        }
      }.flatten.inject(:+) || 0
      [humanize_number(val), val]
    when :evicted_keys_per_second, :expired_keys_per_second, :keyspace_hits_per_second,
         :keyspace_misses_per_second, :total_commands_processed_per_second
      val = get_diff.call(key.to_s.gsub(/_per_second$/, '').to_sym)
      [humanize_number(val), val]
    when :used_memory, :used_memory_rss, :aof_current_size, :aof_base_size
      val = info.sumf(key)
      [humanize_number(val.to_i, true), val]
    when :keyspace_hit_ratio
      hits = info.sumf(:keyspace_hits)
      misses = info.sumf(:keyspace_misses)
      val = ratio(hits, misses)
      [humanize_number(val), val]
    when :keyspace_hit_ratio_per_second
      hits = get_diff.call(:keyspace_hits) || 0
      misses = get_diff.call(:keyspace_misses) || 0
      val = ratio(hits, misses)
      [humanize_number(val), val]
    else
      val = info.sumf(key)
      [humanize_number(val), val]
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
    @auth && e.is_a?(Redis::CommandError) && e.to_s =~ /operation not permitted/
  end

  def authenticate!
    @redises.values.each do |r|
      r.ping rescue (r.auth @auth)
    end if @auth
  end
end
