# redis-stat

_redis-stat_ is a simple Redis monitoring tool written in Ruby.

It is based on [INFO](http://redis.io/commands/info) command of Redis,
and thus generally won't affect the performance of the Redis instance
unlike the other monitoring tools based on [MONITOR](http://redis.io/commands/monitor) command.

_redis-stat_ allows you to monitor Redis instances
- either with vmstat-like output from the terminal
- or with the dashboard page served by its embedded web server.

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Installation](#installation)
- [Usage](#usage)
- [Running redis-stat for command-line monitoring](#running-redis-stat-for-command-line-monitoring)
  - [Screenshot](#screenshot)
- [redis-stat in web browser](#redis-stat-in-web-browser)
  - [Screenshot](#screenshot-1)
- [redis-stat in Docker](#redis-stat-in-docker)
- [Windows support](#windows-support)
- [Author](#author)
- [Contributors](#contributors)
- [Contributing](#contributing)
- [About the name _redis-stat_](#about-the-name-_redis-stat_)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Installation

```
gem install redis-stat
```

If you have trouble setting up a Ruby environment, you can [download the
executable JAR file](https://github.com/junegunn/redis-stat/releases) and use
it instead.

## Usage

```
usage: redis-stat [HOST[:PORT] ...] [INTERVAL [COUNT]]

    -a, --auth=PASSWORD              Password
    -v, --verbose                    Show more info
        --style=STYLE                Output style: unicode|ascii
        --no-color                   Suppress ANSI color codes
        --csv=OUTPUT_CSV_FILE_PATH   Save the result in CSV format
        --es=ELASTICSEARCH_URL       Send results to ElasticSearch: [http://]HOST[:PORT][/INDEX]

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

### Screenshot

![Terminal output](https://github.com/junegunn/redis-stat/raw/master/screenshots/redis-stat-0.3.0.png)

## redis-stat in web browser

When `--server` option is set, redis-stat will open up an embedded web server (default port: 63790)
in the background so that you can monitor Redis in your browser.

Since _redis-stat_ pushes updates every interval via [Server-sent events](http://www.w3.org/TR/eventsource/),
modern browsers are required to view the page.

```
redis-stat --server
redis-stat --verbose --server=8080 5

# redis-stat server can be daemonized
redis-stat --server --daemon

# Kill the daemon
killall -9 redis-stat-daemon
```

### Screenshot

![Dashboard](https://github.com/junegunn/redis-stat/raw/master/screenshots/redis-stat-web.png)

## redis-stat in Docker

_redis-stat_ has packaged into a 15Mb Alpine-linux docker image and has been pushed to
[Docker Hub](https://hub.docker.com/r/richardhull/redis-stat/). The image is built from the
`Dockerfile` in this project.

A new image can be locally provisioned and started with:

```
docker build redis-stat .`
docker run --name redis-stat -d -p 63790:63790 redis-stat --server 192.165.1.54
```

To pull the pre-built image:

```
docker pull richardhull/redis-stat
docker run --name redis-stat -d -p 63790:63790 richardhull/redis-stat --server 192.165.1.54
```

## Windows support

If you're running Windows, you can only install redis-stat on
[JRuby](http://jruby.org/). Notice that fancy terminal colors will not be
printed as they are not supported in the default Windows command prompt.

## Author
- [Junegunn Choi](https://github.com/junegunn)

## Contributors
- [Chris Meisl](https://github.com/cmeisl)
- [Hyunseok Hwang](https://github.com/frhwang)
- [Sent Hil](https://github.com/sent-hil)
- [Richard Hull](https://github.com/rm-hull)

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## About the name _redis-stat_

Since this project was supposed to be a vmstat-like monitoring script for Redis,
naming it _redis-stat_ seemed like a nice idea. That was when I was unaware of the existence of
the original [redis-stat](https://github.com/antirez/redis-tools/blob/master/redis-stat.c)
included in [redis-tools](https://github.com/antirez/redis-tools) written by the creator of Redis himself. (My bad)
Although the original C-version hasn't been updated for the past couple of years, you might want to check it out first.

