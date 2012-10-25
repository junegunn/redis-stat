# redis-stat

A Redis monitoring tool written in Ruby.

You can monitor Redis servers
- either with vmstat-like output from terminal
- or with the dashboard page in web browser.

(Note: it is highly likely that you are looking for the original [redis-stat](https://github.com/antirez/redis-tools/blob/master/redis-stat.c)
included in [redis-tools](https://github.com/antirez/redis-tools) written by the creator of Redis himself.)

## Installation

```
gem install redis-stat
```

## Usage

```
usage: redis-stat [HOST[:PORT] ...] [INTERVAL [COUNT]]

    -a, --auth=PASSWORD              Password
    -v, --verbose                    Show more info
        --style=STYLE                Output style: unicode|ascii
        --no-color                   Suppress ANSI color codes
        --csv=OUTPUT_CSV_FILE_PATH   Save the result in CSV format

        --server[=PORT]              Launch redis-stat web server (default port: 63790)
        --daemon                     Daemonize redis-stat. Must be used with --server option.

        --version                    Show version
        --help                       Show this message
```

## Running redis-stat for command-line monitoring

```
redis-stat
redis-stat 1
redis-stat 1 10
redis-stat --verbose
redis-stat localhost:6380 1 10
redis-stat localhost localhost:6380 localhost:6381 5
redis-stat localhost localhost:6380 1 10 --csv=/tmp/output.csv --verbose
```

<img src="https://github.com/junegunn/redis-stat/raw/master/screenshots/redis-stat-0.2.4.png" style="max-width: 700px"/>

## redis-stat in web browser

When `--server` option is set, redis-stat will open up an embedded web server
in the background so that you can monitor Redis in your browser.

```
redis-stat --server
redis-stat --verbose --server=8080 5

# redis-stat server can be daemonized
redis-stat --server --daemon
```

<img src="https://github.com/junegunn/redis-stat/raw/master/screenshots/redis-stat-web.png" style="max-width: 700px"/>

## Author
- [Junegunn Choi](https://github.com/junegunn)

## Contributors
- [Chris Meisl](https://github.com/cmeisl)

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
