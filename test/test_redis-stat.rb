#!/usr/bin/env ruby
# encoding: utf-8

require 'rubygems'
require 'test-unit'
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'redis-stat'
require 'redis'
require 'stringio'

class TestRedisStat < Test::Unit::TestCase
  def test_humanize_number
    rs = RedisStat.new
    assert_equal '0', rs.send(:humanize_number, 0.00)
    assert_equal '7', rs.send(:humanize_number, 7)
    assert_equal '0.01', rs.send(:humanize_number, 0.00751)
    assert_equal '0.08', rs.send(:humanize_number, 0.0751)
    assert_equal '0.75', rs.send(:humanize_number, 0.751)
    assert_equal '7.51', rs.send(:humanize_number,  7.51)
    assert_equal '75.1', rs.send(:humanize_number,  75.1)
    assert_equal '7.51K', rs.send(:humanize_number, 7510)
    assert_equal '75.1K', rs.send(:humanize_number, 75100)
    assert_equal '751K', rs.send(:humanize_number,  751000)
    assert_equal '7.51M', rs.send(:humanize_number, 7510000)
    assert_equal '75.1M', rs.send(:humanize_number, 75100000)
    assert_equal '751M', rs.send(:humanize_number,  751000000)
    assert_equal '7.51G', rs.send(:humanize_number, 7510000000)
    assert_equal '75.1G', rs.send(:humanize_number, 75100000000)
    assert_equal '751G', rs.send(:humanize_number,  751000000000)
    assert_equal '7.51T', rs.send(:humanize_number, 7510000000000)
    assert_equal '75.1T', rs.send(:humanize_number, 75100000000000)
    assert_equal '751T', rs.send(:humanize_number,  751000000000000)
    assert_equal '7.51P', rs.send(:humanize_number, 7510000000000000)
    assert_equal '75.1P', rs.send(:humanize_number, 75100000000000000)
    assert_equal '751P', rs.send(:humanize_number,  751000000000000000)
    assert_equal '7.51E', rs.send(:humanize_number, 7510000000000000000)
    assert_equal '75.1E', rs.send(:humanize_number, 75100000000000000000)
    assert_equal '751E',  rs.send(:humanize_number, 751000000000000000000)
    assert_equal '7510E', rs.send(:humanize_number, 7510000000000000000000)

    assert_equal '7.51PB', rs.send(:humanize_number, 7.51 * (1024 ** 5), 1024, 'B')
    assert_equal '-7.51PB', rs.send(:humanize_number, -7.51 * (1024 ** 5), 1024, 'B')
  end

  def test_option_parse
    options = RedisStat::Option.parse([])
    assert_equal RedisStat::Option::DEFAULT.sort, options.sort

    options = RedisStat::Option.parse(%w[localhost:1000 20])
    assert_equal({
      :hosts => ['localhost:1000'],
      :interval => 20,
      :count => nil,
      :csv => nil,
      :style => :unicode
    }.sort, options.sort)

    options = RedisStat::Option.parse(%w[localhost:1000 20 30])
    assert_equal({
      :hosts => ['localhost:1000'],
      :interval => 20,
      :count => 30,
      :csv => nil,
      :style => :unicode
    }.sort, options.sort)

    options = RedisStat::Option.parse(%w[20])
    assert_equal({
      :hosts => ['127.0.0.1:6379'],
      :interval => 20,
      :count => nil,
      :csv => nil,
      :style => :unicode
    }.sort, options.sort)

    options = RedisStat::Option.parse(%w[20 30])
    assert_equal({
      :hosts => ['127.0.0.1:6379'],
      :interval => 20,
      :count => 30,
      :csv => nil,
      :style => :unicode
    }.sort, options.sort)

    options = RedisStat::Option.parse(%w[localhost:8888 10 --csv=/tmp/a.csv --style=ascii])
    assert_equal({
      :hosts => ['localhost:8888'],
      :interval => 10,
      :count => nil,
      :csv => '/tmp/a.csv',
      :style => :ascii
    }.sort, options.sort)
  end

  def test_option_parse_invalid
    [
      %w[localhost 0],
      %w[localhost 5 0]
    ].each do |argv|
      assert_raise(SystemExit) {
        options = RedisStat::Option.parse(argv)
      }
    end

    assert_raise(SystemExit) {
      RedisStat::Option.parse(%w[--style=html])
    }
  end

  def test_start
    csv = '/tmp/redis-stat.csv'
    cnt = 100
    rs = RedisStat.new :hosts => %w[localhost] * 5, :interval => 0.02, :count => cnt,
            :verbose => true, :csv => csv, :auth => 'pw'
    rs.start $stdout

    assert_equal cnt + 1, File.read(csv).lines.to_a.length
  ensure
    File.unlink csv
  end

  def test_static_info_of_mixed_versions
    # prerequisite
    r1 = Redis.new(:host => 'localhost')
    r2 = Redis.new(:host => 'localhost', :port => 6380)

    if r1.info['redis_version'] =~ /^2\.4/ && r2.info['redis_version'] =~ /^2\.2/
      rs = RedisStat.new :hosts => %w[localhost:6380 localhost], :interval => 1, :count => 1,
            :auth => 'pw', :style => :ascii
      output = StringIO.new
      rs.start output
      vline = output.string.lines.select { |line| line =~ /gcc_version/ }.first
      puts vline.gsub(/ +/, ' ')
      assert vline.gsub(/ +/, ' ').include?('| | 4.2.1 |')
    else
      raise NotImplementedError.new # FIXME
    end
  rescue Redis::CannotConnectError, NotImplementedError 
    pend "redises not ready"
  end
end

