# Dev and Production Open Food Facts Import

These notes assume application deployment and database migrations are handled by the existing CI/CD path. The Open Food Facts import does not require a new schema migration; it reuses `food_items`, `food_portions`, and `reference_data_imports`.

## Prepare Data

Use one of these approaches:

- Build on the server:

```bash
cd /home/javier/dev/cal-tracker
python -m venv .venv-openfoodfacts
. .venv-openfoodfacts/bin/activate
pip install -r tools/openfoodfacts_import/requirements.txt
python tools/openfoodfacts_import/import_openfoodfacts.py download
python tools/openfoodfacts_import/import_openfoodfacts.py build
python tools/openfoodfacts_import/import_openfoodfacts.py validate
```

- Or copy the already-built local artifacts to the server:

```bash
rsync -av data/openfoodfacts/normalized data/openfoodfacts/manifests data/openfoodfacts/reports \
  <server>:/home/javier/dev/cal-tracker/data/openfoodfacts/
```

## Load Dev

```bash
cd /home/javier/dev/cal-tracker
. .venv-openfoodfacts/bin/activate

OPENFOODFACTS_IMPORT_MODE=docker-exec \
OPENFOODFACTS_IMPORT_POSTGRES_CONTAINER=cal-tracker-postgres \
OPENFOODFACTS_IMPORT_DATABASE_SCHEMA=cal_tracker_dev \
python tools/openfoodfacts_import/import_openfoodfacts.py load --target local

OPENFOODFACTS_IMPORT_MODE=docker-exec \
OPENFOODFACTS_IMPORT_POSTGRES_CONTAINER=cal-tracker-postgres \
OPENFOODFACTS_IMPORT_DATABASE_SCHEMA=cal_tracker_dev \
python tools/openfoodfacts_import/import_openfoodfacts.py validate-db --target local
```

## Load Production

Production requires the explicit guard flag:

```bash
cd /home/javier/dev/cal-tracker
. .venv-openfoodfacts/bin/activate

OPENFOODFACTS_IMPORT_MODE=docker-exec \
OPENFOODFACTS_IMPORT_POSTGRES_CONTAINER=cal-tracker-postgres \
OPENFOODFACTS_IMPORT_DATABASE_SCHEMA=cal_tracker_pro \
python tools/openfoodfacts_import/import_openfoodfacts.py load --target production --confirm-production

OPENFOODFACTS_IMPORT_MODE=docker-exec \
OPENFOODFACTS_IMPORT_POSTGRES_CONTAINER=cal-tracker-postgres \
OPENFOODFACTS_IMPORT_DATABASE_SCHEMA=cal_tracker_pro \
python tools/openfoodfacts_import/import_openfoodfacts.py validate-db --target production --confirm-production
```

## Expected Validation Shape

The local build from 2026-05-11 produced:

- `openfoodfacts_food_items`: 845,979
- `openfoodfacts_portions`: 557,413
- `duplicate_external_ids`: 0
- `english_rows`: 835,005
- `spanish_rows`: 10,974

`reference_data_imports` should contain a recent `openfoodfacts` row for each loaded schema.
