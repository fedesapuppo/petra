# Scheduled sync

The sync runs daily from GitHub Actions: `.github/workflows/sync.yml`. It can
still be run by hand with `bin/sync-incremental --apply`.

Remaining setup, all of it on GitHub rather than in this repo: push to a
private repository and add the four secrets below.

## Cost

Free. GitHub Actions gives unlimited minutes to public repositories and 2,000
minutes/month to private ones. A daily run of this sync uses roughly 1-2
minutes when little has changed, so about 60 minutes/month against that quota.

Keep the repository private. It contains no secrets (`.env` is gitignored),
but the sync logic reveals the catalogue structure and there is no reason to
publish it.

## Workflow

`EnvFile.load` is a no-op when `.env` is absent, so the script reads the
environment variables the workflow injects. No code change was needed.

The sync itself is stdlib only. The `Gemfile` exists solely so CI can run
RSpec before the sync touches the live store; a failing suite stops the run
before the WooCommerce step. `ruby-version` tracks the local 4.0 because
`Gemfile.lock` was resolved with Bundler 4.

## Secrets

Repository Settings, Secrets and variables, Actions. Add four repository
secrets, values from `.env`:

    TOKKO_API_KEY
    WOO_SITE_URL
    WOO_CONSUMER_KEY
    WOO_CONSUMER_SECRET

Those are the only variables the incremental path reads. `WP_USER` and
`PETRA_APLICATION_PASSWORD` belong to `Wp::Client`, which
`bin/sync-incremental` never loads, so they are not needed as secrets.

Rotate the keys currently in `.env` before this goes live: they were pasted
into a chat transcript. Regenerate the WooCommerce pair under WooCommerce,
Settings, Advanced, REST API, and the Tokko key from the Tokko panel, then
update the secrets.

## Choosing the schedule

Daily is the sensible default. Tokko is edited by hand a few times a week
based on the `deleted_at` timestamps (which, despite the name, are
last-modified, see below), so hourly would mostly do nothing.

GitHub's scheduled runs are queued, not guaranteed on time, and can be delayed
by 5-20 minutes at peak. Irrelevant here.

Scheduled workflows are disabled automatically after 60 days without repository
activity. If the repo goes quiet, GitHub emails before disabling; re-enable in
the Actions tab.

## Failure notification

By default GitHub emails the repository owner when a scheduled workflow fails.
That is usually enough. If the sync silently doing nothing is the bigger risk,
add a step that fails loudly when nothing was created, updated or trashed for
an unusually long stretch.

## Things that will bite

`deleted_at` in the Tokko API is a last-modified timestamp, not a deletion
marker. Every live property carries one. Do not filter on it. Removed
properties simply stop appearing in the API response, which is what
`Woo::Diff` relies on.

`Woo::Incremental::MINIMUM_PROPERTIES` aborts the run if Tokko returns fewer
than 5 properties. Without it, an API fault returning an empty list would
trash the whole catalogue. Raise it if the real catalogue grows well beyond 24.

Image import is the slow part, roughly 2.7 seconds per photo, because
WooCommerce downloads each from Tokko's CDN before responding. It only happens
for new listings, so a typical run is fast. A run that adds many properties at
once can approach the 30-minute job timeout: raise `timeout-minutes` if the
catalogue grows.

WooCommerce enforces SKU uniqueness against trashed products too. The sync
clears a product's SKU before trashing it, so a property relisted in Tokko can
be recreated with the same reference code. Do not remove that step.

Products whose SKU does not match `MANAGED_SKU` (three capitals plus digits)
are never touched. That is how manually added listings survive the sync.

## Alternative if GitHub Actions is unwanted

Hostinger's hPanel has a cron job section, but shared hosting runs PHP, not
Ruby. Using it would mean porting the sync to PHP as a WordPress plugin, which
also removes the need for REST API keys since it would run inside WordPress.
That is a rewrite, not a port. Only worth it if GitHub is off the table.
