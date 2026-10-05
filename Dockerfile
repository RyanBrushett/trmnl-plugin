# Runs bin/push once and exits, for Cloud Run Jobs. Keep the Ruby version in
# step with .ruby-version (the Gemfile checks they match).

# Build stage: gems such as json have C extensions, so this needs a compiler.
# The compiler stays here and never reaches the final image.
FROM ruby:4.0.7-slim AS build

RUN apt-get update \
  && apt-get install --no-install-recommends -y build-essential \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV BUNDLE_WITHOUT="development:test" \
    BUNDLE_DEPLOYMENT="true" \
    BUNDLE_PATH="/usr/local/bundle"

COPY .ruby-version Gemfile Gemfile.lock ./
RUN bundle install

# Final stage: only the runtime.
FROM ruby:4.0.7-slim

# tzdata: Config.zone? validates HOME_TIMEZONE against /usr/share/zoneinfo,
# which slim images may not ship.
RUN apt-get update \
  && apt-get install --no-install-recommends -y tzdata ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV BUNDLE_WITHOUT="development:test" \
    BUNDLE_DEPLOYMENT="true" \
    BUNDLE_PATH="/usr/local/bundle"

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY .ruby-version Gemfile Gemfile.lock ./
COPY bin/push ./bin/push
COPY lib ./lib

RUN useradd --create-home runner
USER runner

ENTRYPOINT ["bin/push"]
