# TRMNL

[![Ruby](https://github.com/RyanBrushett/trmnl-plugin/actions/workflows/ruby.yml/badge.svg?branch=main)](https://github.com/RyanBrushett/trmnl-plugin/actions/workflows/ruby.yml)

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

## Running on Google Cloud

`bin/push` runs once and exits, so it fits a Cloud Run Job started by Cloud Scheduler. Replace `PROJECT`, `PROJECT_NUMBER` (shown by `gcloud projects describe PROJECT`) and `REGION`. You need a project with billing enabled, and `gcloud auth login` and `gcloud config set project PROJECT` done.

Try the image locally first:

```
docker build -t trmnl-push .
docker run --rm -e HOME_LAT=... -e HOME_LON=... -e HOME_TIMEZONE=Region/City \
  trmnl-push --dry-run --sample-events
```

Set up once. The calendar must already be shared with the key's service account (see above); `trmnl-runner` is only the identity the job runs as.

```
gcloud services enable run.googleapis.com cloudscheduler.googleapis.com secretmanager.googleapis.com \
  artifactregistry.googleapis.com cloudbuild.googleapis.com calendar-json.googleapis.com
gcloud iam service-accounts create trmnl-runner

printf '%s' "$WEBHOOK_UUID"   | gcloud secrets create trmnl-webhook-uuid --replication-policy=automatic --data-file=-
printf '%s' "$CALENDAR_EMAIL" | gcloud secrets create trmnl-calendar-id --replication-policy=automatic --data-file=-
printf '%s' "$HOME_LAT"       | gcloud secrets create trmnl-home-lat --replication-policy=automatic --data-file=-
printf '%s' "$HOME_LON"       | gcloud secrets create trmnl-home-lon --replication-policy=automatic --data-file=-
gcloud secrets create trmnl-calendar-key --replication-policy=automatic --data-file=/path/to/service-account-key.json

for secret in trmnl-webhook-uuid trmnl-calendar-id trmnl-home-lat trmnl-home-lon trmnl-calendar-key; do
  gcloud secrets add-iam-policy-binding "$secret" \
    --member serviceAccount:trmnl-runner@PROJECT.iam.gserviceaccount.com \
    --role roles/secretmanager.secretAccessor
done
```

Cloud Build runs as the project's default compute service account, which may lack the build role. If the deploy below fails with `PERMISSION_DENIED` on the build, grant it and retry:

```
gcloud projects add-iam-policy-binding PROJECT --condition=None \
  --member serviceAccount:PROJECT_NUMBER-compute@developer.gserviceaccount.com \
  --role roles/cloudbuild.builds.builder
```

Deploy (this builds the `Dockerfile` in the cloud) and run it once by hand:

```
gcloud run jobs deploy trmnl-push --source . --region REGION \
  --service-account trmnl-runner@PROJECT.iam.gserviceaccount.com \
  --set-env-vars HOME_TIMEZONE=Region/City,GOOGLE_SERVICE_ACCOUNT_KEY_FILE=/secrets/key.json \
  --set-secrets TRMNL_WEBHOOK_UUID=trmnl-webhook-uuid:latest,GOOGLE_CALENDAR_ID=trmnl-calendar-id:latest,HOME_LAT=trmnl-home-lat:latest,HOME_LON=trmnl-home-lon:latest,/secrets/key.json=trmnl-calendar-key:latest \
  --max-retries 1
gcloud run jobs execute trmnl-push --region REGION --wait
```

Schedule it, e.g. every 12 minutes (TRMNL allows 12 pushes an hour). Scheduler calls the job as `trmnl-runner`, which needs permission to run it, or every call is refused and the screen quietly stops updating:

```
gcloud run jobs add-iam-policy-binding trmnl-push --region REGION \
  --member serviceAccount:trmnl-runner@PROJECT.iam.gserviceaccount.com --role roles/run.invoker

URI="https://run.googleapis.com/v2/projects/PROJECT/locations/REGION/jobs/trmnl-push:run"
SA=trmnl-runner@PROJECT.iam.gserviceaccount.com

gcloud scheduler jobs create http trmnl-push-schedule --location REGION \
  --schedule "*/12 * * * *" --time-zone "Region/City" \
  --uri "$URI" --http-method POST --oauth-service-account-email "$SA"
```

To stop the updates, pause the schedule: `gcloud scheduler jobs pause trmnl-push-schedule --location REGION` (and `resume` to restart).

## Development

```
bundle exec rake test     # tests
bundle exec rubocop       # lint
```
