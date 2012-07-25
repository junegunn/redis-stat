require 'optparse'

class RedisStat
module Option
  DEFAULT = {
    :hosts    => ['127.0.0.1:6379'],
    :interval => 2,
    :count    => nil,
    :csv      => nil
  }

  def self.parse argv
    argv = argv.dup

    options = DEFAULT.dup
    opts = ::OptionParser.new { |opts|
      opts.banner = "usage: redis-stat [HOST[:PORT] ...] [INTERVAL [COUNT]]"
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

      numbers, hosts = argv.partition { |e| is_number.call e }
      interval, count = numbers.map(&:to_f)

      options[:interval] = interval if interval
      options[:count]    = count if count
      options[:hosts]    = hosts unless hosts.empty?

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

    hosts = options[:hosts]
    if hosts.empty?
      raise ArgumentError.new("Redis host not given")
    end

    hosts.each do |host|
      host, port = host.split(':')
      if port
        port = port.to_i
        unless port > 0 && port < 65536
          raise ArgumentError.new("Invalid port: #{port}")
        end
      end
    end
  end
end
end
