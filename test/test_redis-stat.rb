require 'rubygems'
require 'test/unit'
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'redis-stat'

class TestRedisStat < Test::Unit::TestCase
  def test_option_parse
    options = RedisStat::Option.parse([])
    assert_equal RedisStat::Option::DEFAULT.sort, options.sort

    options = RedisStat::Option.parse(%w[localhost:1000 20])
    assert_equal({
      :host => 'localhost',
      :port => 1000,
      :interval => 20,
      :count => nil,
      :csv => nil
    }.sort, options.sort)

    options = RedisStat::Option.parse(%w[localhost:1000 20 30])
    assert_equal({
      :host => 'localhost',
      :port => 1000,
      :interval => 20,
      :count => 30,
      :csv => nil
    }.sort, options.sort)

    options = RedisStat::Option.parse(%w[20])
    assert_equal({
      :host => '127.0.0.1',
      :port => 6379,
      :interval => 20,
      :count => nil,
      :csv => nil
    }.sort, options.sort)

    options = RedisStat::Option.parse(%w[20 30])
    assert_equal({
      :host => '127.0.0.1',
      :port => 6379,
      :interval => 20,
      :count => 30,
      :csv => nil
    }.sort, options.sort)

    options = RedisStat::Option.parse(%w[localhost:8888 10 --csv=/tmp/a.csv])
    assert_equal({
      :port => 8888,
      :host => 'localhost',
      :interval => 10,
      :count => nil,
      :csv => '/tmp/a.csv',
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
  end

  def test_start
    rs = RedisStat.new :interval => 0.1, :count => 200, :verbose => true, :csv => '/tmp/redis-stat.csv'
    rs.start
  end
end


