# Open Food Facts Import Tool

Streaming tooling for building and loading a local Open Food Facts product corpus.

## Data Source and License

The tool downloads the official daily JSONL export:

- `https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz`

Open Food Facts data is available under the Open Database License (ODbL) v1.0. The app stores attribution on imported rows with:

- `external_source = openfoodfacts`
- `source_url = https://world.openfoodfacts.org/product/<barcode>`
- `license = ODbL-1.0; (c) Open Food Facts contributors`

Open Food Facts asks API/data reusers to preserve attribution and share alike for derivative databases. If this imported data is publicly reused or redistributed, the Open Food Facts-derived database portion must remain available under ODbL-compatible terms.

## Local Usage

```bash
cd /home/javier/dev/cal-tracker
python -m venv .venv-openfoodfacts
. .venv-openfoodfacts/bin/activate
pip install -r tools/openfoodfacts_import/requirements.txt

export OPENFOODFACTS_IMPORT_DATABASE_URL=postgres://cal_tracker:cal_tracker@localhost:5432/cal_tracker
export OPENFOODFACTS_IMPORT_DATABASE_SCHEMA=public
python tools/openfoodfacts_import/import_openfoodfacts.py run --target local
python tools/openfoodfacts_import/import_openfoodfacts.py validate-db --target local
```

Raw exports, normalized CSVs, reports, and manifests are written under `data/openfoodfacts/`, which is intentionally ignored by Git.

For a small local smoke test, use:

```bash
python tools/openfoodfacts_import/import_openfoodfacts.py run --target local --max-products 50000
```

## Dev/Production Schemas

The deployed Postgres database uses separate schemas:

- Dev: `cal_tracker_dev`
- Production: `cal_tracker_pro`

Run the same load for each schema by changing `OPENFOODFACTS_IMPORT_DATABASE_SCHEMA`.

## Production Guard

Production runs require explicit intent:

```bash
OPENFOODFACTS_IMPORT_MODE=docker-exec \
OPENFOODFACTS_IMPORT_POSTGRES_CONTAINER=cal-tracker-postgres \
OPENFOODFACTS_IMPORT_DATABASE_SCHEMA=cal_tracker_pro \
python tools/openfoodfacts_import/import_openfoodfacts.py load --target production --confirm-production
```

The script does not start, stop, restart, kill, or reconfigure production containers.
