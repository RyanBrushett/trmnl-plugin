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

Reads your primary calendar, read-only, and hides events you have declined. Without these settings `bin/push` shows no events (use `--sample-events` to see made-up ones).

1. In Google Cloud (signed in with the Google account whose calendar you want to read), create a project, enable the Google Calendar API, set up the OAuth consent screen with the scope `https://www.googleapis.com/auth/calendar.events.readonly` and yourself as a test user, then create an OAuth client of type "Desktop app".
2. Put its client ID and secret in `.env` as `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`.
3. Run `bin/google_auth`. It opens Google's consent page and prints a refresh token; put that in `.env` as `GOOGLE_REFRESH_TOKEN`. While the app is in "Testing" on Google's side, the token expires after 7 days and you re-run this.
4. `bin/push --dry-run` should now list your real events.

## Development

```
bundle exec rake test     # tests
bundle exec rubocop       # lint
```
