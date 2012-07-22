require 'optparse'

class RedisStat
module Option
  DEFAULT = {
    :host     => '127.0.0.1',
    :port     => 6379,
    :interval => 2,
    :count    => nil,
    :csv      => nil
  }

  def self.parse argv
    argv = argv.dup

    options = DEFAULT.dup
    opts = ::OptionParser.new { |opts|
      opts.banner = "usage: redis-stat [HOST[:PORT]] [INTERVAL [COUNT]]"
      opts.separator ''

      opts.on('--csv=OUTPUT_CSV_FILE_PATH', 'Save the result in CSV format') do |v|
        options[:csv] = v
      end

      opts.on('-v', '--verbose', 'Show more info') do |v|
        options[:verbose] = v
      end

      opts.on('--version', 'Show version') do
        puts RedisStat::VERSION
        exit 0
      end

      opts.on_tail('--help', 'Show this message') do
        puts opts
        exit 0
      end
    }
    
    begin
      opts.parse! argv

      is_number   = lambda { |str| str =~ /^([0-9]\.?[0-9]*)$|^([1-9][0-9]*)$/ }
      set_options = lambda { |host_port, interval, count|
        if host_port
          host, port = host_port.split(':')
          options[:host] = host
          options[:port] = port.to_i if port
        end

        options[:interval] = interval.to_f if interval
        options[:count] = count.to_i if count
      }

      case argv.length
      when 1
        if is_number.call argv.first
          set_options.call nil, argv.first, nil
        else
          set_options.call argv.first, nil, nil
        end
      when 2
        if is_number.call argv.first
          set_options.call nil, argv.first, argv.last
        else
          set_options.call argv.first, argv.last, nil
        end
      when 3
        set_options.call *argv
      end

      validate options

      return options
    rescue SystemExit => e
      exit e.status
    rescue Exception => e
      puts e.to_s
      puts opts
      exit 1
    end
  end

  def self.validate options
    interval = options[:interval]
    unless interval.is_a?(Numeric) && interval > 0
      raise ArgumentError.new("Invalid interval: #{interval}")
    end

    count = options[:count]
    unless count.nil? || (count.is_a?(Numeric) && count > 0)
      raise ArgumentError.new("Invalid count: #{count}")
    end

    port = options[:port]
    unless port.is_a?(Fixnum) && port > 0 && port < 65536
      raise ArgumentError.new("Invalid port: #{port}")
    end
  end
end
end
