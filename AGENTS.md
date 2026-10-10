# TRMNL

Ruby script that pushes a daily screen (Google Calendar events plus weather) to a TRMNL e-ink display via a private plugin webhook. Runs once and exits (`bin/push`), as a Cloud Run Job on a Cloud Scheduler cron.

## Commands

- `bundle exec rake test`
- `bundle exec rubocop`
- `bin/push --dry-run --sample-events`: try without sending or needing Google credentials
- `bin/push --dry-run --sample-events | bin/preview`: writes `tmp/preview.html`

## Gotchas

- `templates/*.liquid` are pasted by hand into the TRMNL plugin editor. Changes there don't take effect until re-pasted.
- TRMNL allows 12 pushes an hour, so don't schedule more often than every 12 minutes.
- Deploys happen from GitHub Actions after CI passes on `main`; setup and `gcloud` steps are in `README.md`.
- `.env` holds real settings and is git-ignored. Never read or print it; use `.env.example`.
