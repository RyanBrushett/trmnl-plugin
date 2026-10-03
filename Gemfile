source "https://rubygems.org"

ruby file: ".ruby-version"

gem "dotenv"
gem "google-apis-calendar_v3"
gem "googleauth"

# Only for rendering the template in previews and tests; bin/push does not need them.
group :development, :test do
  gem "cgi" # For liquid
  gem "trmnl-liquid"
end

group :development do
  gem "rubocop"
  gem "rubocop-minitest"
  gem "rubocop-performance"
  gem "rubocop-rake"
  gem "standard"
end

group :test do
  gem "base64" # Required directly by calendar_source_service_account_test
  gem "minitest"
  gem "rake"
  gem "webmock"
end
