# encoding: utf-8

require 'redis-stat/version'
require 'redis-stat/constants'
require 'redis-stat/option'
require 'redis-stat/server'
require 'insensitive_hash'
require 'redis'
require 'tabularize'
require 'ansi256'
require 'csv'
require 'parallelize'
require 'si'
require 'rbconfig'
require 'lps'

class RedisStat
  attr_reader :hosts, :measures, :tab_measures, :verbose, :interval

  def initialize options = {}
    options = RedisStat::Option::DEFAULT.merge options
    windows = RbConfig::CONFIG['target_os'] =~ /mswin|mingw/

    Ansi256.enabled = STDOUT.tty? && !(windows || options[:mono])
    options[:style] = :ascii if windows

    @hosts       = options[:hosts]
    @redises     = @hosts.map { |e|
      host, port = e.split(':')
      Redis.new(Hash[ {:host => host, :port => port, :timeout => DEFAULT_REDIS_TIMEOUT}.select { |k, v| v } ])
    }
    @interval    = options[:interval]
    @max_count   = options[:count]
    @colors      = options[:colors] || COLORS
    @csv         = options[:csv]
    @auth        = options[:auth]
    @verbose     = options[:verbose]
    @measures    = MEASURES[ @verbose ? :verbose : :default ].map { |m| [*m].first }
    @tab_measures= MEASURES[:static].map { |m| [*m].first }
    @all_measures= MEASURES.values.inject(:+).uniq - [:at]
    @count       = 0
    @style       = options[:style]
    @varwidth    = STDOUT.tty? && !windows
    @first_batch = true
    @server_port = options[:server_port]
    @server_thr  = nil
    @daemonized  = options[:daemon]
  end

  def info
    collect
  end

  def start output_stream
    @os = output_stream
    trap('INT') { Thread.main.raise Interrupt }

    begin
      csv = File.open(@csv, 'w') if @csv
      update_term_size!
      authenticate!

      @started_at = Time.now
      prev_info   = nil
      server      = start_server if @server_port

      LPS.interval(@interval).loop do
        errs = 0
        info =
          begin
            collect
          rescue Interrupt
            raise
          rescue Exception => e
            if need_auth?(e)
              authenticate!
              retry
            end

            errs += 1
            if server || errs < NUM_RETRIES
              @os.puts if errs == 1
              @os.puts "#{e} (#{ server ? "#{errs}" : [errs, NUM_RETRIES].join('/') })".red.bold
              sleep @interval
              retry
            else
              raise
            end
          end
        info_output = process info, prev_info
        output info, info_output, csv unless @daemonized
        server.push info, Hash[info_output] if server
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
    rescue Exception => e
      @os.puts e.to_s.red.bold
      raise
    ensure
      csv.close if csv
    end
    @os.puts "Elapsed: #{"%.2f" % (Time.now - @started_at)} sec.".blue.bold
  end

private
  def start_server
    RedisStat::Server.set :port, @server_port
    RedisStat::Server.set :redis_stat, self
    @server_thr = Thread.new { RedisStat::Server.run! }
    RedisStat::Server.wait_until_running
    trap('INT') { Thread.main.raise Interrupt }
    RedisStat::Server
  end

  def collect
    {}.insensitive.tap do |info|
      class << info
        def sumf label
          (self[label] || []).map(&:to_f).inject(:+)
        end
      end

      info[:at] = Time.now.to_f
      @redises.pmap(@redises.length) { |redis|
        redis.info.insensitive
      }.each do |rinfo|
        (@all_measures + rinfo.keys.select { |k| k =~ /^db[0-9]+$/ }).each do |k|
          ks = [*k]
          v = ks.map { |e| rinfo[e] }.compact.first
          k = ks.first
          info[k] ||= []
          info[k] << v
        end
      end
    end
  end

  def update_term_size!
    if RUBY_PLATFORM == 'java'
      require 'java'
      begin
        case JRUBY_VERSION
        when /^1\.7/
          # TODO Currently Windows terminal is not supported: always returns 80x24
          @term ||= Java::jline.console.ConsoleReader.new.getTerminal
          @term_width  = (@term.width rescue DEFAULT_TERM_WIDTH)
          @term_height = (@term.height rescue DEFAULT_TERM_HEIGHT) - 4
          return
        when /^1\.6/
          @term ||= Java::jline.ConsoleReader.new.getTerminal
          @term_width  = (@term.getTerminalWidth rescue DEFAULT_TERM_WIDTH)
          @term_height = (@term.getTerminalHeight rescue DEFAULT_TERM_HEIGHT) - 4
          return
        end
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

  def output_file info_output, file
    file.puts CSV.generate_line(info_output.map { |pair|
      LABELS[pair.first] || pair.first
    }) if @count == 0

    file.puts CSV.generate_line(info_output.map { |pair|
      [*pair.last].last
    })
  end

  def output_term info_output
    @table ||= init_table info_output

    movement = nil
    if @count == 0
      output_static_info info

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
      move! -movement
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
      tab << [key.to_s.bold] + info[key] unless info[key].compact.empty?
    end
    @os.puts tab
  end

  def output info, info_output, file
    output_term info_output
    output_file info_output, file if file
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
      val = Hash[ info.select { |k, v| k =~ /^db[0-9]+$/ } ].values.inject(0) { |sum, vs|
        sum + vs.map { |v| Hash[ v.split(',').map { |e| e.split '=' } ]['keys'].to_i }.inject(:+)
      }
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
    @redises.each do |r|
      r.ping rescue (r.auth @auth)
    end if @auth
  end
end
