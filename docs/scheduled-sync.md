# Scheduled sync

The sync runs daily from GitHub Actions: `.github/workflows/sync.yml`. It can
still be run by hand with `bin/sync-incremental --apply`.

It polls rather than listens because Tokko has no webhook for property changes.
Its webhooks cover lead activity and the property importer's callback, not edits
made in the panel, so the only way to learn about a change is to ask. A run
where nothing changed reads the property list from Tokko and the product list
from WooCommerce, then exits without writing.

Remaining setup, all of it on GitHub rather than in this repo: push to a
private repository and add the four secrets below.

## Cost

Free, and the frequency is what decides how free. GitHub gives unlimited
minutes to public repositories and 2,000 minutes/month to private ones. Minutes
are billed per job rounded up to the whole minute, so a run that finishes in 16
seconds still costs a full minute. The number of runs is the only thing that
moves the bill:

    daily             30 runs/month     1.5% of the quota
    business hours   420 runs/month      21% of the quota
    hourly           730 runs/month      36% of the quota

Hourly ran for a day and worked, but spending a third of the quota to catch
edits that happen a few times a week was not a trade worth making. Daily it is.

The sync job still installs no gems and runs no tests, which keeps a run near
20 seconds. That no longer saves minutes at this frequency, but it is what
makes going back to hourly cheap if the catalogue ever justifies it. The suite
lives in `.github/workflows/test.yml` and runs on push, which is when the code
can actually break.

Nothing else meters. The Tokko API is not billed per call, and 28 products is
not load worth worrying about on the WooCommerce side.

Keep the repository private. It contains no secrets (`.env` is gitignored),
but the sync logic reveals the catalogue structure and there is no reason to
publish it.

## Workflow

`EnvFile.load` is a no-op when `.env` is absent, so the script reads the
environment variables the workflow injects. No code change was needed.

The sync itself is stdlib only, so the sync job sets `bundler: none` and calls
`ruby` directly. The `Gemfile` exists for RSpec, which `test.yml` runs on push.
Both workflows pin `ruby-version` to the local 4.0, and `test.yml` needs it
because `Gemfile.lock` was resolved with Bundler 4.

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

Daily at 09:17 UTC, which is 06:17 in Argentina, before business hours. Tokko
is edited by hand a few times a week, judging by the `deleted_at` timestamps
(which, despite the name, are last-modified, see below), so most runs of any
schedule find nothing.

GitHub's scheduler is best-effort, not a guarantee. Measured over 14
consecutive hourly runs it did fire every slot, but never on time: 12 to 46
minutes late, averaging around half an hour. It also ignored the cron entirely
for the first 70 minutes after the repository was created. So the daily run
lands somewhere in the 06:17-07:00 window in Argentina, and anything that needs
to be live now wants `workflow_dispatch` from the Actions tab.

Going back to hourly is one line, if the catalogue grows or someone starts
editing Tokko all day. Restricting an hourly cron to business hours is the
middle option at roughly 420 runs/month, since nobody edits at 04:00. Making
the repository public removes the quota entirely, at the price of publishing
the sync logic and the shape of the catalogue.

Two cheaper designs exist and neither is worth building. The API accepts
Django-style filters (`inactiveproperty/?deleted_at__gte=...`), so a run could
ask "anything since last time?" before doing real work, and a Cloudflare Worker
on the free tier could take a webhook and fire `repository_dispatch`. Neither
avoids the billed minute, which is the only cost that matters here.

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
