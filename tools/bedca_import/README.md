# BEDCA Dump Tool

Small, rate-limited dumper for inspecting the public BEDCA web database.
It can also materialize load-shaped CSVs for inspection.

## Legal Status

BEDCA is not published under an open-data license suitable for app ingestion.
The usage PDF says the source must be clearly indicated as:

`AESAN/BEDCA Base de Datos Española de Composición de Alimentos v1.0 (2010)`

It also says reproduction, translation, or electronic use outside personal,
educational, or non-commercial contexts requires express authorization from
AESAN/BEDCA.

Project decision: do not load BEDCA into Better Calories application databases
or ship it in the app unless express permission is obtained and the attribution
text is approved. This includes dev, staging, production, and any local database
used as an application runtime source. Keep BEDCA artifacts as inspection-only
reference files.

Source terms: `https://www.bedca.net/bdpub/UsoBD.pdf`

## Usage

```bash
cd /home/antonio/code/cal-tracker
python -m venv .venv-bedca
. .venv-bedca/bin/activate
pip install -r tools/bedca_import/requirements.txt

python tools/bedca_import/dump_bedca.py dump
python tools/bedca_import/dump_bedca.py summarize
python tools/bedca_import/dump_bedca.py validate
python tools/bedca_import/dump_bedca.py sample
python tools/bedca_import/dump_bedca.py build-load
```

Output is written under `data/bedca/`, which is ignored by Git:

- `raw/foods.xml`
- `raw/details/<food_id>.xml`
- `normalized/foods.json`
- `normalized/foods.csv`
- `normalized/nutrients.csv`
- `normalized/load_foods.csv`
- `normalized/load_food_portions.csv`
- `manifests/manifest.json`
- `reports/summary.json`
- `reports/skipped_foods.json`
- `reports/load_skipped_foods.json`
- `reports/validation.json`

Some foods may appear in the public list but return an empty detail payload from
BEDCA. Those are excluded from the normalized files and recorded in
`reports/skipped_foods.json`.

## Inspection CSVs

BEDCA load rows use Spanish as the canonical language:

- `external_source = bedca`
- `data_type = BEDCA`
- `name = canonical_name = <BEDCA Spanish name>`
- `food_key = es`
- one `100 g` portion per food

Generate the load-shaped CSVs for inspection only:

```bash
cd /home/antonio/code/cal-tracker
. .venv-bedca/bin/activate
python tools/bedca_import/dump_bedca.py build-load
```
