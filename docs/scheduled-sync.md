# Scheduled sync (not implemented)

Everything needed to run the sync automatically. Deliberately left unbuilt:
the sync currently runs by hand with `bin/sync-incremental --apply`.

Estimated effort to finish: 1-2 hours, most of it verifying the first
unattended runs rather than writing the workflow.

## Cost

Free. GitHub Actions gives unlimited minutes to public repositories and 2,000
minutes/month to private ones. A daily run of this sync uses roughly 1-2
minutes when little has changed, so about 60 minutes/month against that quota.

Keep the repository private. It contains no secrets (`.env` is gitignored),
but the sync logic reveals the catalogue structure and there is no reason to
publish it.

## Workflow

Create `.github/workflows/sync.yml`:

```yaml
name: Sync Tokko to WooCommerce

on:
  schedule:
    - cron: "0 9 * * *"   # 06:00 in Argentina (UTC-3), before business hours
  workflow_dispatch:       # allows a manual run from the Actions tab

concurrency:
  group: tokko-sync        # never let two runs overlap
  cancel-in-progress: false

jobs:
  sync:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"   # no gems needed, stdlib only

      - name: Run tests
        run: rspec

      - name: Sync
        env:
          TOKKO_API_KEY: ${{ secrets.TOKKO_API_KEY }}
          WOO_SITE_URL: ${{ secrets.WOO_SITE_URL }}
          WOO_CONSUMER_KEY: ${{ secrets.WOO_CONSUMER_KEY }}
          WOO_CONSUMER_SECRET: ${{ secrets.WOO_CONSUMER_SECRET }}
        run: ruby bin/sync-incremental --apply
```

`EnvFile.load` is a no-op when `.env` is absent, so the script reads the
environment variables the workflow injects. No code change needed.

`rspec` needs the gem in CI. Either add a minimal `Gemfile` with
`gem "rspec"` plus `bundler-cache: true` on the setup-ruby step, or drop the
test step and rely on running tests locally before pushing.

## Secrets

Repository Settings, Secrets and variables, Actions. Add four repository
secrets with the names above, values from `.env`.

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
