# Tokko to WooCommerce sync

Keeps the property listings on petrapropiedades.com in step with the agency's
Tokko Broker catalogue. Tokko is the source of truth.

Ruby standard library only. No gems at runtime, no `bundle install`.

## Setup

```sh
cp .env.example .env   # then fill in the four values
```

The WooCommerce key is generated in WP admin under WooCommerce, Settings,
Advanced, REST API, with Read/Write permission.

## Commands

```sh
bin/explore                       # read-only: dump both catalogues to tmp/
bin/backup                        # snapshot the site to backups/<timestamp>/
bin/sync-incremental              # dry run: show what would change
bin/sync-incremental --apply      # apply the changes
mise exec -- rspec                # tests
```

`bin/sync` is the one-time migration that rebuilt the catalogue from scratch.
It trashes every product and recreates them. It is kept for reference and
should not be run again: use `bin/sync-incremental`.

## How it works

`Tokko::Client` pages the Tokko API 20 at a time (their docs warn of a 30s
server timeout on larger pages).

`Woo::Payload` translates one Tokko property into the fields WooCommerce
needs. Pure, no network, so it is the part with real test coverage.

`Woo::Diff` compares mapped payloads against current products and returns a
plan of creates, updates and trashes. Also pure.

`Woo::Incremental` executes the plan, resolving category and attribute names
to WooCommerce term IDs.

## Mapping decisions

Property identity is the Tokko `reference_code`, stored in the product SKU.
The Tokko numeric id is also stored in `_tokko_id` meta. The SKU is hidden on
the front end with CSS in Appearance, Customize, Additional CSS.

Categories come from Tokko type plus operation. See `Woo::Payload::CATEGORIES`.
An unmapped combination raises rather than guessing, so a new Tokko property
type surfaces as a loud failure instead of a miscategorised listing.

All Tokko `Terreno` listings map to Terrenos, including ones whose titles say
"Lote". Tokko carries nothing that reliably distinguishes lote from terreno
from campo: `custom1` is "0.00" on every record and `extra_attributes` is
always empty.

Prices are written as a bare number, with the currency in the `Precio`
attribute ("USD 88000", "ARS 950000"). The store renders one currency symbol
for all products, so a peso rental would otherwise read as dollars. The
WooCommerce price element still shows the store symbol: fixing that properly
needs a `functions.php` filter, which is outside what the REST API can reach.

Surfaces come from `roofed_surface` (Superficie Cubierta) and `surface`,
falling back to `total_surface` (Superficie Terreno). Tokko uses 0.00 to mean
absent, so zeroes are omitted rather than written as "0m2".

Asador, Piscina and Cloacas are derived from Tokko tags, since Tokko has no
dedicated fields for them.

Blueprints (`is_blueprint`) are excluded from the gallery.

## Safety

- The sync aborts if Tokko returns fewer than 5 properties, so an API fault
  cannot empty the catalogue.
- Products are trashed, never permanently deleted, and are recoverable in WP
  admin.
- Only products whose SKU matches `Woo::Incremental::MANAGED_SKU` are touched.
  Anything added by hand is left alone.
- `backups/` holds full snapshots. Take one before anything destructive.

## Gotchas

`deleted_at` in the Tokko API is a last-modified timestamp despite the name.
Every live property has one. Filtering on it would treat the whole catalogue
as deleted. Removed properties simply stop appearing in the response.

WooCommerce enforces SKU uniqueness against trashed products, so the sync
clears a SKU before trashing that product.

WordPress never returns a description byte-identical to what was sent: it runs
it through `wpautop`, so `Text` comes back as `<p>Text</p>\n`. `Woo::Diff`
compares stripped text, not markup. Comparing raw strings made every run
report all 24 descriptions as changed.

WooCommerce reuses an existing global attribute term when one matches
case-insensitively, and returns that term's casing. The site already had a
lowercase "si" term on `pa_piscina`, so a sent "Si" came back as "si".
Attribute comparison is case-insensitive for that reason.

Both of the above cause the same failure: a sync that rewrites every product
on every run while never actually converging. After changing comparison logic,
verify with `bin/sync-incremental` that a run with no Tokko changes reports
everything unchanged.

Hostinger throttles under sustained API load. The rebuild triggered 502s and
refused connections for a couple of minutes afterwards. `HttpJson` retries
connection-level failures (`RETRIABLE_ERRORS`) with exponential backoff, not
just HTTP status codes.

## Scheduling

Not implemented. See `docs/scheduled-sync.md` for a ready-to-use GitHub
Actions workflow and the decisions around it.
