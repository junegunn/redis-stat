# encoding: utf-8

require "redis-stat/version"
require "redis-stat/option"
require 'insensitive_hash'
require 'redis'
require 'tabularize'
require 'ansi'
require 'csv'
require 'parallelize'

class RedisStat
  DEFAULT_TERM_WIDTH  = 180
  DEFAULT_TERM_HEIGHT = 25

  def initialize options = {}
    options      = RedisStat::Option::DEFAULT.merge options
    @hosts       = options[:hosts]
    @redises     = @hosts.map { |e| 
      host, port = e.split(':')
      Redis.new(Hash[ {:host => host, :port => port}.select { |k, v| v } ])
    }
    @interval    = options[:interval]
    @max_count   = options[:count]
    @colors      = options[:colors] || COLORS
    @csv         = options[:csv]
    @auth        = options[:auth]
    @measures    = MEASURES[ options[:verbose] ? :verbose : :default ]
    @count       = 0
    @style       = options[:style]
    @first_batch = true
  end

  def start output_stream
    @os = output_stream
    trap('INT') { Thread.main.raise Interrupt }

    begin
      csv = File.open(@csv, 'w') if @csv
      update_term_size!

      # Warm-up / authenticate only when needed
      @redises.each do |r|
        begin
          r.info
        rescue Redis::CommandError
          r.auth @auth if @auth
        end
      end

      @started_at = Time.now
      prev_info = nil
      loop do
        info = {}.insensitive
        class << info
          def sumf label
            (self[label] || []).map(&:to_f).inject(:+)
          end
        end

        info[:at] = Time.now.to_f
        @redises.pmap(@redises.length) { |redis|
          redis.info.insensitive
        }.each do |rinfo|
          rinfo.each do |k, v|
            info[k] ||= []
            info[k] << v
          end
        end

        output info, prev_info, csv

        prev_info = info
        @count += 1
        break if @max_count && @count >= @max_count
        sleep @interval
      end
      @os.puts
    rescue Interrupt
      @os.puts
      @os.puts ansi(:yellow, :bold) { "Interrupted." }
    rescue Exception => e
      @os.puts ansi(:red, :bold) { e.to_s }
      exit 1
    ensure
      csv.close if csv
    end
    @os.puts ansi(:blue, :bold) {
      "Elapsed: #{"%.2f" % (Time.now - @started_at)} sec."
    }
  end

private
  def update_term_size!
    if RUBY_PLATFORM.match(/java/)
      require 'java'
      begin
        @term ||= Java::jline.Terminal.getTerminal
        @term_width  = (@term.getTerminalWidth rescue DEFAULT_TERM_WIDTH)
        @term_height = (@term.getTerminalHeight rescue DEFAULT_TERM_HEIGHT) - 4
        return
      rescue Exception
        # Fallback to tput (which yields incorrect values as of now)
      end
    end

    @term_width  = (`tput cols`  rescue DEFAULT_TERM_WIDTH).to_i
    @term_height = (`tput lines` rescue DEFAULT_TERM_HEIGHT).to_i - 4
  end

  def move! lines
    return if lines == 0

    @os.print(
      if defined?(Win32::Console)
        if lines < 0
          "\e[#{- lines}F"
        else
          "\e[#{lines}E"
        end
      else
        if lines < 0
          "\e[#{- lines}A\e[0G"
        else
          "\e[#{lines}B\e[0G"
        end
      end)
  end

  def output info, prev_info, file
    info_output = process info, prev_info

    @table ||= init_table info_output

    movement = nil
    if @count == 0
      output_static_info info

      movement = 0
      if file
        file.puts CSV.generate_line(info_output.map { |pair|
          LABELS[pair.first] || pair.first
        })
      end
    elsif @count % @term_height == 0
      @first_batch = false
      movement = -1
      update_term_size!
      @table = init_table info_output
    end

    # Build output table
    @table << info_output.map { |pair|
      ansi(*@colors[pair.first]) { [*pair.last].first }
    }
    lines  = @table.to_s.lines.map(&:chomp)
    lines.delete_at @first_batch ? 1 : 0
    width  = lines.first.length
    height = lines.length

    # Calculate the number of lines to go upward
    if movement.nil?
      if @prev_width && @prev_width == width
        lines = lines[-2..-1]
        movement = -1
      else
        movement = -(height - 1)
      end
    end
    @prev_width = width

    move! movement
    begin
      @os.print $/ + lines.join($/)

      if file
        file.puts CSV.generate_line(info_output.map { |pair|
          [*pair.last].last
        })
      end
    rescue Interrupt
      move! -movement
      raise
    end
  end

  def output_static_info info
    tab = Tabularize.new(
      :unicode => false, :align => :right,
      :border_style => @style
    )
    tab << [nil] + @hosts.map { |h| ansi(:bold, :green) { h } }
    tab.separator!
    [
      :redis_version,
      :process_id,
      :uptime_in_seconds,
      :uptime_in_days,
      :gcc_version,
      :role,
      :connected_slaves,
      :aof_enabled,
      :vm_enabled
    ].each do |key|
      tab << [ansi(:bold) { key }] + info[key] if info[key]
    end
    @os.puts tab
  end

  def init_table info_output
    table = Tabularize.new :unicode => false,
                       :align        => :right,
                       :border_style => @style,
                       :border_color => ANSI::Code.red,
                       :vborder      => ' ',
                       :pad_left     => 0,
                       :pad_right    => 0,
                       :screen_width => @term_width
    table.separator!
    table << info_output.map { |pair|
      ansi(*((@colors[pair.first] || []) + [:underline])) {
        LABELS[pair.first] || pair.first
      } 
    }
    table.separator!
    table
  end

  def process info, prev_info
    @measures.map { |key|
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
      Time.now.strftime('%H:%M:%S')
    when :used_cpu_user, :used_cpu_sys
      val = get_diff.call(key)
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
    when :total_commands_processed, :evicted_keys, :expired_keys, :keyspace_hits, :keyspace_misses
      val = info.sumf(key)
      [humanize_number(val.to_i), val]
    when :used_memory, :used_memory_rss, :aof_current_size, :aof_base_size
      val = info.sumf(key)
      [humanize_number(val.to_i, 1024, 'B'), val]
    else
      format_number info.sumf(key)
    end
  end

  def format_number num
    if num.to_i == num
      num.to_i
    elsif num < 10
      "%.2f" % num
    elsif num < 100
      "%.1f" % num
    else
      num.to_i
    end.to_s
  end

  def humanize_number num, k = 1000, suffix = ''
    return '-' if num.nil?

    sign = num >= 0 ? '' : '-'
    num  = num.abs
    mult = k.to_f
    ['', 'K', 'M', 'G', 'T', 'P', 'E'].each do |mp|
      return sign + format_number(num * k / mult) + mp + suffix if num < mult || mp == 'E'
      mult *= k
    end
    return nil
  end

  def ansi *args, &block
    if args.empty?
      block.call
    else
      ANSI::Code.ansi *args, &block
    end
  end

  MEASURES = {
    :default => [
      :at,
      :used_cpu_user,
      :used_cpu_sys,
      :connected_clients,
      :blocked_clients,
      :used_memory,
      :used_memory_rss,
      :keys,
      :total_commands_processed_per_second,
      :expired_keys_per_second,
      :evicted_keys_per_second,
      :keyspace_hits_per_second,
      :keyspace_misses_per_second,
      :aof_current_size,
      :pubsub_channels,
    ],
    :verbose => [
      :at,
      :used_cpu_user,
      :used_cpu_sys,
      :connected_clients,
      :blocked_clients,
      :used_memory,
      :used_memory_rss,
      :mem_fragmentation_ratio,
      :keys,
      :total_commands_processed_per_second,
      :total_commands_processed,
      :expired_keys_per_second,
      :expired_keys,
      :evicted_keys_per_second,
      :evicted_keys,
      :keyspace_hits_per_second,
      :keyspace_hits,
      :keyspace_misses_per_second,
      :keyspace_misses,
      :aof_current_size,
      :aof_base_size,
      :pubsub_channels,
      :pubsub_patterns,
    ]
  }

  COLORS = {
    :at                                  => [:bold],
    :used_cpu_user                       => [:yellow, :bold],
    :used_cpu_sys                        => [:yellow],
    :connected_clients                   => [:cyan, :bold],
    :blocked_clients                     => [:cyan, :bold],
    :used_memory                         => [:green],
    :used_memory_rss                     => [:green],
    :mem_fragmentation_ratio             => [:green],
    :keys                                => [:bold],
    :total_commands_processed            => [:blue, :bold],
    :total_commands_processed_per_second => [:blue, :bold],
    :expired_keys                        => [:red],
    :expired_keys_per_second             => [:red],
    :evicted_keys                        => [:red, :bold],
    :evicted_keys_per_second             => [:red, :bold],
    :keyspace_hits                       => [:magenta, :bold],
    :keyspace_hits_per_second            => [:magenta, :bold],
    :keyspace_misses                     => [:magenta],
    :keyspace_misses_per_second          => [:magenta],
    :aof_current_size                    => [:cyan],
    :aof_base_size                       => [:cyan],
    :pubsub_channels                     => [:cyan, :bold],
    :pubsub_patterns                     => [:cyan, :bold],
  }

  LABELS = {
    :at                                  => 'time',
    :used_cpu_user                       => 'us',
    :used_cpu_sys                        => 'sy',
    :connected_clients                   => 'cl',
    :blocked_clients                     => 'bcl',
    :used_memory                         => 'mem',
    :used_memory_rss                     => 'rss',
    :mem_fragmentation_ratio             => 'frag',
    :total_commands_processed            => 'cmd',
    :total_commands_processed_per_second => 'cmd/s',
    :expired_keys                        => 'exp',
    :expired_keys_per_second             => 'exp/s',
    :evicted_keys                        => 'evt',
    :evicted_keys_per_second             => 'evt/s',
    :keyspace_hits                       => 'hit',
    :keyspace_hits_per_second            => 'hit/s',
    :keyspace_misses                     => 'mis',
    :keyspace_misses_per_second          => 'mis/s',
    :aof_current_size                    => 'aofcs',
    :aof_base_size                       => 'aofbs',
    :pubsub_channels                     => 'psch',
    :pubsub_patterns                     => 'psp',
  }
end
