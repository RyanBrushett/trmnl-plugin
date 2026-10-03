# TRMNL

Pushes a glanceable daily screen (schedule and the next few hours of weather) to a TRMNL e-ink display through a private plugin webhook.

## Getting started

1. Use the Ruby version in `.ruby-version` (rbenv, chruby, asdf and similar tools read it), then install the gems:

   ```
   bundle install
   ```

2. Create your settings file and fill it in (it is git-ignored):

   ```
   cp .env.example .env
   ```

   | Variable | What it is |
   |---|---|
   | `HOME_LAT`, `HOME_LON` | Coordinates for the weather |
   | `HOME_TIMEZONE` | IANA zone name, e.g. `Region/City` |
   | `TRMNL_WEBHOOK_UUID` | The UUID at the end of your private plugin's webhook URL |

3. Try it without sending anything:

   ```
   bin/push --dry-run --sample-events
   ```

   Drop `--dry-run` to POST to TRMNL for real.

4. See what the screen will look like (writes `tmp/preview.html`; open it in a browser):

   ```
   bin/push --dry-run --sample-events | bin/preview
   ```

## Setting up the plugin on TRMNL

Create a private plugin, then paste two files into it:

- `templates/full.liquid` into the full-screen markup
- `templates/shared.liquid` into the shared markup (the reusable pieces that `full.liquid` calls)

Copy the UUID from its webhook URL into `.env`.

## Google Calendar

Reads one calendar, read-only, and hides events you have declined. Without these settings the screen shows an error saying so, rather than an empty day (use `--sample-events` to see made-up events instead).

It signs in as a service account: a robot identity with its own key, so there is no consent screen and nothing to renew.

1. In Google Cloud, create a project, enable the Google Calendar API, and create a service account (it needs no project roles).
2. Create a JSON key for it and keep the file somewhere private, outside the repo.
3. In Google Calendar, share your calendar with the service account's email address, with the permission "See all event details".
4. In `.env`, set `GOOGLE_SERVICE_ACCOUNT_KEY_FILE` to the key file's absolute path, and `GOOGLE_CALENDAR_ID` to the calendar's email address. A service account's own "primary" calendar is empty, so `primary` is rejected.
5. `bin/push --dry-run` should now list your real events.

## Development

```
bundle exec rake test     # tests
bundle exec rubocop       # lint
```
