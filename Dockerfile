FROM ruby:2.5.1-slim

RUN echo deb http://http.debian.net/debian jessie-backports main >> /etc/apt/sources.list.d/backports.list && apt-get update -qq && apt-get install -y build-essential git curl && apt-get clean autoclean && apt-get autoremove -y && rm -rf /var/lib/apt /var/lib/dpkg /var/lib/cache /var/lib/log

WORKDIR /app

COPY Gemfile* ./

RUN bundle install   --deployment   --jobs 8   --retry 3

ADD . /app

ENV APP_ENV docker

VOLUME ["/var/www/backend"]

CMD ["/app/bin/start_service.sh"]

