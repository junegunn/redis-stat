FROM alpine:latest
RUN apk add --update make g++ ncurses ruby ruby-dev ruby-rdoc ruby-irb && \
  gem install redis-stat && \
  apk del make g++ ruby-rdoc ruby-irb && \
  rm -rf /var/cache/apk/*
EXPOSE 63790
ENTRYPOINT ["redis-stat"]