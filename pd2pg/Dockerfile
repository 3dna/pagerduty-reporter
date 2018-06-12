FROM ruby:2.4.0-alpine

ENV BUILD_PACKAGES bash curl-dev ruby-dev build-base libxml2-dev libxslt-dev postgresql postgresql-dev git
ENV RUBY_PACKAGES ruby ruby-io-console ruby-bundler ruby-dev

# Update and install all of the required packages.
# At the end, remove the apk cache
RUN apk update && \
    apk upgrade && \
    apk add $BUILD_PACKAGES && \
    apk add $RUBY_PACKAGES && \
    rm -rf /var/cache/apk/*

ENV app /app
RUN mkdir $app
WORKDIR $app
COPY Gemfile $app
COPY Gemfile.lock $app
ADD . $app

RUN bundle install
