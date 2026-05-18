#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import json
import os
import re
import subprocess
import sys
import unicodedata
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import psycopg
import requests
from tqdm import tqdm


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATA_DIR = ROOT / "data" / "openfoodfacts"
SOURCE = "openfoodfacts"
LICENSE = "ODbL-1.0; (c) Open Food Facts contributors"
DATASET_URL = "https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz"
USER_AGENT = "better-calories/openfoodfacts-import (https://bettercalories.app)"

FOOD_LOAD_COLUMNS = [
    "external_id",
    "name",
    "normalized_name",
    "canonical_name",
    "data_type",
    "food_category",
    "publication_date",
    "food_key",
    "brand",
    "barcode",
    "ingredients",
    "market_country",
    "household_serving_fulltext",
    "source_url",
    "license",
    "serving_grams",
    "calories",
    "protein_grams",
    "carbs_grams",
    "fat_grams",
    "nutrients_json",
]

PORTION_LOAD_COLUMNS = [
    "external_food_id",
    "usda_portion_id",
    "amount",
    "unit",
    "modifier",
    "description",
    "gram_weight",
    "normalized_aliases_json",
    "kind",
    "source_description",
]


@dataclass(frozen=True)
class BuildStats:
    products_seen: int
    food_rows: int
    portion_rows: int
    skipped_missing_name: int
    skipped_missing_nutrition: int
    skipped_invalid_nutrition: int


def main() -> int:
    parser = argparse.ArgumentParser(description="Build and load a local Open Food Facts corpus.")
    parser.add_argument("command", choices=["download", "build", "validate", "load", "validate-db", "run"])
    parser.add_argument("--data-dir", default=str(DEFAULT_DATA_DIR))
    parser.add_argument("--target", choices=["local", "production"], default="local")
    parser.add_argument("--confirm-production", action="store_true")
    parser.add_argument("--languages", default="en,es", help="Comma-separated language codes to materialize.")
    parser.add_argument("--max-products", type=int, help="Stop after reading this many products; useful for smoke tests.")
    args = parser.parse_args()

    ctx = Context(
        data_dir=Path(args.data_dir),
        target=args.target,
        confirm_production=args.confirm_production,
        languages=tuple(code.strip().lower() for code in args.languages.split(",") if code.strip()),
        max_products=args.max_products,
    )
    ctx.ensure_dirs()
    if args.command in {"download", "run"}:
        download(ctx)
    if args.command in {"build", "run"}:
        build(ctx)
    if args.command in {"validate", "run"}:
        validate(ctx)
    if args.command in {"load", "run"}:
        load(ctx)
    if args.command == "validate-db":
        validate_db(ctx)
    return 0


class Context:
    def __init__(
        self,
        data_dir: Path,
        target: str,
        confirm_production: bool,
        languages: tuple[str, ...],
        max_products: int | None,
    ) -> None:
        self.data_dir = data_dir
        self.target = target
        self.confirm_production = confirm_production
        self.languages = languages
        self.max_products = max_products
        self.raw_dir = data_dir / "raw"
        self.normalized_dir = data_dir / "normalized"
        self.manifest_dir = data_dir / "manifests"
        self.report_dir = data_dir / "reports"

    def ensure_dirs(self) -> None:
        for directory in [self.raw_dir, self.normalized_dir, self.manifest_dir, self.report_dir]:
            directory.mkdir(parents=True, exist_ok=True)

    @property
    def raw_path(self) -> Path:
        return self.raw_dir / "openfoodfacts-products.jsonl.gz"

    @property
    def foods_path(self) -> Path:
        return self.normalized_dir / "foods.csv"

    @property
    def portions_path(self) -> Path:
        return self.normalized_dir / "food_portions.csv"


def download(ctx: Context) -> None:
    if ctx.raw_path.exists() and ctx.raw_path.stat().st_size > 0:
        print(f"Using cached {ctx.raw_path}")
        return
    temporary = ctx.raw_path.with_suffix(ctx.raw_path.suffix + ".part")
    print(f"Downloading {DATASET_URL}")
    with requests.get(DATASET_URL, stream=True, timeout=60, headers={"User-Agent": USER_AGENT}) as response:
        response.raise_for_status()
        total = int(response.headers.get("content-length") or 0)
        with temporary.open("wb") as fh, tqdm(total=total, unit="B", unit_scale=True) as progress:
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                if not chunk:
                    continue
                fh.write(chunk)
                progress.update(len(chunk))
    temporary.replace(ctx.raw_path)


def build(ctx: Context) -> None:
    with ctx.foods_path.open("w", newline="", encoding="utf-8") as foods_fh, ctx.portions_path.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as portions_fh:
        food_writer = csv.DictWriter(foods_fh, fieldnames=FOOD_LOAD_COLUMNS)
        portion_writer = csv.DictWriter(portions_fh, fieldnames=PORTION_LOAD_COLUMNS)
        food_writer.writeheader()
        portion_writer.writeheader()
        stats = stream_products(ctx, food_writer, portion_writer)
    write_manifest(ctx, stats)
    write_json(ctx.report_dir / "build.json", stats.__dict__)
    print(f"Wrote {stats.food_rows:,} foods and {stats.portion_rows:,} portions from {stats.products_seen:,} products")


def stream_products(ctx: Context, food_writer: csv.DictWriter, portion_writer: csv.DictWriter) -> BuildStats:
    seen = food_rows = portion_rows = 0
    missing_name = missing_nutrition = invalid_nutrition = 0
    with gzip.open(ctx.raw_path, "rt", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if ctx.max_products is not None and seen >= ctx.max_products:
                break
            seen += 1
            if not line.strip():
                continue
            try:
                product = json.loads(line)
            except json.JSONDecodeError:
                continue
            nutrition = nutrition_for_product(product)
            if nutrition is None:
                missing_nutrition += 1
                continue
            if not valid_nutrition(nutrition):
                invalid_nutrition += 1
                continue
            rows = food_rows_for_product(product, nutrition, ctx.languages)
            if not rows:
                missing_name += 1
                continue
            for row in rows:
                food_writer.writerow(row)
                food_rows += 1
                portion = portion_row_for_food(row)
                if portion:
                    portion_writer.writerow(portion)
                    portion_rows += 1
    return BuildStats(seen, food_rows, portion_rows, missing_name, missing_nutrition, invalid_nutrition)


def nutrition_for_product(product: dict[str, object]) -> dict[str, float] | None:
    nutriments = product.get("nutriments")
    if not isinstance(nutriments, dict):
        return None
    values = {
        "calories": number_value(nutriments.get("energy-kcal_100g")),
        "protein_grams": number_value(nutriments.get("proteins_100g")),
        "carbs_grams": number_value(nutriments.get("carbohydrates_100g")),
        "fat_grams": number_value(nutriments.get("fat_100g")),
        "fiber_grams": number_value(nutriments.get("fiber_100g")),
        "sugars_grams": number_value(nutriments.get("sugars_100g")),
        "saturated_fat_grams": number_value(nutriments.get("saturated-fat_100g")),
        "sodium_mg": sodium_mg(nutriments),
    }
    if any(values[key] is None for key in ["calories", "protein_grams", "carbs_grams", "fat_grams"]):
        return None
    return {key: value for key, value in values.items() if value is not None}


def sodium_mg(nutriments: dict[object, object]) -> float | None:
    sodium_100g = number_value(nutriments.get("sodium_100g"))
    if sodium_100g is not None:
        return sodium_100g * 1000
    salt_100g = number_value(nutriments.get("salt_100g"))
    if salt_100g is not None:
        return salt_100g * 393.4
    return None


def valid_nutrition(nutrition: dict[str, float]) -> bool:
    return (
        0 <= nutrition["calories"] <= 2000
        and 0 <= nutrition["protein_grams"] <= 100
        and 0 <= nutrition["carbs_grams"] <= 100
        and 0 <= nutrition["fat_grams"] <= 100
    )


def food_rows_for_product(
    product: dict[str, object],
    nutrition: dict[str, float],
    languages: tuple[str, ...],
) -> list[dict[str, object]]:
    if truthy(product.get("obsolete")) or truthy(product.get("no_nutrition_data")):
        return []
    code = clean_text(product.get("code"))
    if not code:
        return []
    rows: list[dict[str, object]] = []
    emitted_names: set[str] = set()
    for language in languages:
        name = localized_text(product, "product_name", language)
        generic_name = localized_text(product, "generic_name", language)
        if not name and product_language(product) == language:
            name = clean_text(product.get("product_name")) or clean_text(product.get("generic_name"))
            generic_name = generic_name or clean_text(product.get("generic_name"))
        name = name or generic_name
        if not name:
            continue
        normalized_name = normalize_text(name)
        if not normalized_name or normalized_name in emitted_names:
            continue
        emitted_names.add(normalized_name)
        source_url = clean_text(product.get("url")) or f"https://world.openfoodfacts.org/product/{code}"
        nutrients_json = extra_nutrients(product, nutrition, language)
        rows.append(
            {
                "external_id": f"{code}:{language}",
                "name": name,
                "normalized_name": normalized_name,
                "canonical_name": generic_name or name,
                "data_type": "Open Food Facts",
                "food_category": localized_text(product, "categories", language) or clean_text(product.get("categories")),
                "publication_date": timestamp_date(product.get("last_modified_t")),
                "food_key": language,
                "brand": clean_text(product.get("brands")),
                "barcode": code,
                "ingredients": localized_text(product, "ingredients_text", language),
                "market_country": tags_text(product.get("countries_tags")),
                "household_serving_fulltext": clean_text(product.get("serving_size")),
                "source_url": source_url,
                "license": LICENSE,
                "serving_grams": serving_grams(product),
                "calories": round(nutrition["calories"], 4),
                "protein_grams": round(nutrition["protein_grams"], 4),
                "carbs_grams": round(nutrition["carbs_grams"], 4),
                "fat_grams": round(nutrition["fat_grams"], 4),
                "nutrients_json": json.dumps(nutrients_json, sort_keys=True, separators=(",", ":")),
            }
        )
    return rows


def extra_nutrients(product: dict[str, object], nutrition: dict[str, float], language: str) -> dict[str, object]:
    payload: dict[str, object] = {
        "attribution": "(c) Open Food Facts contributors",
        "license": "ODbL-1.0",
        "language": language,
    }
    for key in ["fiber_grams", "sugars_grams", "saturated_fat_grams", "sodium_mg"]:
        value = nutrition.get(key)
        if value is not None:
            payload[key] = round(value, 4)
    for field in ["nutriscore_grade", "nova_group", "quantity"]:
        value = product.get(field)
        if value not in (None, ""):
            payload[field] = value
    return payload


def portion_row_for_food(food: dict[str, object]) -> dict[str, object] | None:
    grams = number_value(food.get("serving_grams"))
    serving = clean_text(food.get("household_serving_fulltext"))
    if grams is None or grams <= 0 or grams > 10000 or grams == 100 or not serving:
        return None
    return {
        "external_food_id": food["external_id"],
        "usda_portion_id": "openfoodfacts:serving",
        "amount": "1",
        "unit": "serving",
        "modifier": "",
        "description": serving,
        "gram_weight": round(grams, 4),
        "normalized_aliases_json": json.dumps(["serving"], separators=(",", ":")),
        "kind": "serving",
        "source_description": f"Open Food Facts serving size: {serving}",
    }


def localized_text(product: dict[str, object], field: str, language: str) -> str:
    return clean_text(product.get(f"{field}_{language}"))


def product_language(product: dict[str, object]) -> str:
    return (clean_text(product.get("lang")) or clean_text(product.get("lc"))).lower()


def serving_grams(product: dict[str, object]) -> float:
    value = number_value(product.get("serving_quantity"))
    if value is not None and 0 < value <= 10000:
        return round(value, 4)
    serving_size = clean_text(product.get("serving_size")).lower()
    match = re.search(r"([0-9]+(?:[.,][0-9]+)?)\s*(g|gram|grams|ml|milliliter|milliliters)\b", serving_size)
    if match:
        parsed = float(match.group(1).replace(",", "."))
        if 0 < parsed <= 10000:
            return round(parsed, 4)
    return 100.0


def number_value(value: object) -> float | None:
    if value is None or value == "":
        return None
    try:
        number = float(str(value).replace(",", "."))
    except ValueError:
        return None
    if not (number == number) or number in (float("inf"), float("-inf")):
        return None
    return number


def clean_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, list):
        value = ", ".join(str(item) for item in value if item not in (None, ""))
    text = str(value).strip()
    return re.sub(r"\s+", " ", text)


def tags_text(value: object) -> str:
    if isinstance(value, list):
        return ", ".join(str(item).replace("en:", "") for item in value if item)
    return clean_text(value)


def truthy(value: object) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes"}


def timestamp_date(value: object) -> str:
    number = number_value(value)
    if number is None or number <= 0:
        return ""
    return datetime.fromtimestamp(number, tz=timezone.utc).date().isoformat()


def validate(ctx: Context) -> None:
    errors: list[str] = []
    food_count = count_csv_rows(ctx.foods_path)
    portion_count = count_csv_rows(ctx.portions_path)
    if food_count == 0:
        errors.append("no food rows were built")
    duplicate_ids = duplicate_external_ids(ctx.foods_path)
    if duplicate_ids:
        errors.append(f"duplicate Open Food Facts external ids found: {duplicate_ids[:5]}")
    food_overflows = numeric_overflow_rows(ctx.foods_path, "serving_grams")
    if food_overflows:
        errors.append(f"food serving_grams values exceed database range: {food_overflows[:5]}")
    portion_overflows = numeric_overflow_rows(ctx.portions_path, "gram_weight")
    if portion_overflows:
        errors.append(f"portion gram_weight values exceed database range: {portion_overflows[:5]}")
    report = {"foods": food_count, "portions": portion_count, "errors": errors}
    write_json(ctx.report_dir / "validation.json", report)
    if errors:
        raise SystemExit("Validation failed: " + "; ".join(errors))
    print("Validation passed")


def count_csv_rows(path: Path) -> int:
    with path.open("r", encoding="utf-8", newline="") as fh:
        return max(0, sum(1 for _ in fh) - 1)


def duplicate_external_ids(path: Path) -> list[str]:
    seen: set[str] = set()
    duplicates: list[str] = []
    with path.open("r", encoding="utf-8", newline="") as fh:
        for row in csv.DictReader(fh):
            external_id = row["external_id"]
            if external_id in seen:
                duplicates.append(external_id)
                if len(duplicates) >= 25:
                    break
            seen.add(external_id)
    return duplicates


def numeric_overflow_rows(path: Path, column: str) -> list[str]:
    overflow: list[str] = []
    with path.open("r", encoding="utf-8", newline="") as fh:
        for row in csv.DictReader(fh):
            value = number_value(row.get(column))
            if value is not None and abs(value) >= 1_000_000:
                overflow.append(row.get("external_id") or row.get("external_food_id") or row.get("name") or "")
                if len(overflow) >= 25:
                    break
    return overflow


def load(ctx: Context) -> None:
    guard_production(ctx)
    food_count = count_csv_rows(ctx.foods_path)
    portion_count = count_csv_rows(ctx.portions_path)
    if import_mode() == "docker-exec":
        docker_load(ctx, food_count, portion_count)
    else:
        direct_load(ctx, food_count, portion_count)


def direct_load(ctx: Context, food_count: int, portion_count: int) -> None:
    database_url = os.environ.get("OPENFOODFACTS_IMPORT_DATABASE_URL") or os.environ.get("DATABASE_URL")
    if not database_url:
        raise SystemExit("OPENFOODFACTS_IMPORT_DATABASE_URL or DATABASE_URL is required")
    with psycopg.connect(database_url) as conn:
        with conn.transaction():
            with conn.cursor() as cur:
                cur.execute(search_path_sql())
                cur.execute(stage_food_sql())
                copy_csv(cur, ctx.foods_path, f"COPY off_food_stage ({','.join(FOOD_LOAD_COLUMNS)}) FROM STDIN WITH (FORMAT csv, HEADER true)")
                cur.execute(stage_portion_sql())
                copy_csv(cur, ctx.portions_path, f"COPY off_portion_stage ({','.join(PORTION_LOAD_COLUMNS)}) FROM STDIN WITH (FORMAT csv, HEADER true)")
                cur.execute(prepare_stage_sql())
                cur.execute(merge_stage_sql())
                cur.execute(record_import_sql(ctx, food_count, portion_count))
    print(f"Loaded {food_count:,} Open Food Facts foods and {portion_count:,} portions")


def copy_csv(cur: psycopg.Cursor, path: Path, statement: str) -> None:
    with cur.copy(statement) as copy:
        with path.open("r", encoding="utf-8", newline="") as fh:
            for chunk in iter(lambda: fh.read(1024 * 1024), ""):
                if chunk:
                    copy.write(chunk)


def docker_load(ctx: Context, food_count: int, portion_count: int) -> None:
    container = os.environ.get("OPENFOODFACTS_IMPORT_POSTGRES_CONTAINER", "cal-tracker-postgres")
    subprocess.run(["docker", "cp", str(ctx.foods_path), f"{container}:/tmp/openfoodfacts_foods.csv"], check=True)
    subprocess.run(["docker", "cp", str(ctx.portions_path), f"{container}:/tmp/openfoodfacts_food_portions.csv"], check=True)
    sql = "\n".join(
        [
            search_path_sql(),
            "BEGIN;",
            stage_food_sql(),
            f"\\copy off_food_stage ({','.join(FOOD_LOAD_COLUMNS)}) FROM '/tmp/openfoodfacts_foods.csv' WITH (FORMAT csv, HEADER true)",
            stage_portion_sql(),
            f"\\copy off_portion_stage ({','.join(PORTION_LOAD_COLUMNS)}) FROM '/tmp/openfoodfacts_food_portions.csv' WITH (FORMAT csv, HEADER true)",
            prepare_stage_sql(),
            merge_stage_sql(),
            record_import_sql(ctx, food_count, portion_count),
            "COMMIT;",
        ]
    )
    docker_psql(sql, container)
    subprocess.run(["docker", "exec", container, "rm", "-f", "/tmp/openfoodfacts_foods.csv", "/tmp/openfoodfacts_food_portions.csv"], check=False)
    print(f"Loaded {food_count:,} Open Food Facts foods and {portion_count:,} portions")


def stage_food_sql() -> str:
    columns = ",\n  ".join(f"{column} text" for column in FOOD_LOAD_COLUMNS)
    return f"CREATE TEMP TABLE off_food_stage (\n  {columns}\n) ON COMMIT DROP;"


def stage_portion_sql() -> str:
    columns = ",\n  ".join(f"{column} text" for column in PORTION_LOAD_COLUMNS)
    return f"CREATE TEMP TABLE off_portion_stage (\n  {columns}\n) ON COMMIT DROP;"


def prepare_stage_sql() -> str:
    return """
CREATE INDEX off_food_stage_external_id_idx ON off_food_stage (external_id);
CREATE INDEX off_portion_stage_external_food_id_idx ON off_portion_stage (external_food_id);
ANALYZE off_food_stage;
ANALYZE off_portion_stage;
"""


def merge_stage_sql() -> str:
    return """
UPDATE food_items target
SET name = stage.name,
    normalized_name = stage.normalized_name,
    canonical_name = stage.canonical_name,
    brand = NULLIF(stage.brand, ''),
    barcode = NULLIF(stage.barcode, ''),
    source = 'openfoodfacts',
    external_source = 'openfoodfacts',
    source_url = stage.source_url,
    license = stage.license,
    fetched_at = now(),
    data_type = stage.data_type,
    food_category = NULLIF(stage.food_category, ''),
    publication_date = NULLIF(stage.publication_date, '')::date,
    ndb_number = NULL,
    food_key = stage.food_key,
    ingredients = NULLIF(stage.ingredients, ''),
    market_country = NULLIF(stage.market_country, ''),
    household_serving_fulltext = NULLIF(stage.household_serving_fulltext, ''),
    nutrients_json = COALESCE(NULLIF(stage.nutrients_json, '')::jsonb, '{}'::jsonb),
    serving_grams = NULLIF(stage.serving_grams, '')::numeric,
    calories = round(NULLIF(stage.calories, '')::numeric)::integer,
    protein_grams = NULLIF(stage.protein_grams, '')::numeric,
    carbs_grams = NULLIF(stage.carbs_grams, '')::numeric,
    fat_grams = NULLIF(stage.fat_grams, '')::numeric
FROM off_food_stage stage
WHERE target.external_source = 'openfoodfacts'
  AND target.external_id = stage.external_id
  AND target.user_id IS NULL;

INSERT INTO food_items (
  user_id, name, normalized_name, canonical_name, brand, barcode, source,
  external_source, external_id, source_url, license, fetched_at, data_type,
  food_category, publication_date, ndb_number, food_key, ingredients,
  market_country, household_serving_fulltext, nutrients_json, serving_grams,
  calories, protein_grams, carbs_grams, fat_grams
)
SELECT
  NULL, stage.name, stage.normalized_name, stage.canonical_name,
  NULLIF(stage.brand, ''), NULLIF(stage.barcode, ''), 'openfoodfacts',
  'openfoodfacts', stage.external_id, stage.source_url, stage.license, now(),
  stage.data_type, NULLIF(stage.food_category, ''), NULLIF(stage.publication_date, '')::date,
  NULL, stage.food_key, NULLIF(stage.ingredients, ''),
  NULLIF(stage.market_country, ''), NULLIF(stage.household_serving_fulltext, ''),
  COALESCE(NULLIF(stage.nutrients_json, '')::jsonb, '{}'::jsonb),
  NULLIF(stage.serving_grams, '')::numeric, round(NULLIF(stage.calories, '')::numeric)::integer,
  NULLIF(stage.protein_grams, '')::numeric, NULLIF(stage.carbs_grams, '')::numeric,
  NULLIF(stage.fat_grams, '')::numeric
FROM off_food_stage stage
WHERE NOT EXISTS (
  SELECT 1 FROM food_items existing
  WHERE existing.external_source = 'openfoodfacts'
    AND existing.external_id = stage.external_id
    AND existing.user_id IS NULL
);

DELETE FROM food_portions portion
USING food_items food, off_food_stage stage
WHERE portion.food_item_id = food.id
  AND food.external_source = 'openfoodfacts'
  AND food.external_id = stage.external_id
  AND food.user_id IS NULL;

INSERT INTO food_portions (
  food_item_id, usda_portion_id, amount, unit, modifier, description,
  gram_weight, normalized_aliases, kind, source_description
)
SELECT
  food.id,
  NULLIF(stage.usda_portion_id, ''),
  NULLIF(stage.amount, '')::numeric,
  NULLIF(stage.unit, ''),
  NULLIF(stage.modifier, ''),
  NULLIF(stage.description, ''),
  NULLIF(stage.gram_weight, '')::numeric,
  ARRAY(SELECT jsonb_array_elements_text(COALESCE(NULLIF(stage.normalized_aliases_json, '')::jsonb, '[]'::jsonb))),
  COALESCE(NULLIF(stage.kind, ''), 'serving'),
  COALESCE(NULLIF(stage.source_description, ''), 'Open Food Facts serving')
FROM off_portion_stage stage
JOIN food_items food
  ON food.external_source = 'openfoodfacts'
 AND food.external_id = stage.external_food_id
 AND food.user_id IS NULL
WHERE NULLIF(stage.gram_weight, '')::numeric > 0;
"""


def record_import_sql(ctx: Context, food_count: int, portion_count: int) -> str:
    manifest = import_manifest(ctx)
    manifest_json = json.dumps(manifest, sort_keys=True, separators=(",", ":"))
    manifest_sha256 = hashlib.sha256(manifest_json.encode("utf-8")).hexdigest()
    return f"""
INSERT INTO reference_data_imports (
  source, target_schema, manifest_sha256, manifest_json, food_count, portion_count
)
VALUES (
  {sql_literal(SOURCE)},
  {sql_literal(database_schema())},
  {sql_literal(manifest_sha256)},
  {sql_literal(manifest_json)}::jsonb,
  {int(food_count)},
  {int(portion_count)}
)
ON CONFLICT (source, target_schema, manifest_sha256)
DO UPDATE SET
  manifest_json = EXCLUDED.manifest_json,
  food_count = EXCLUDED.food_count,
  portion_count = EXCLUDED.portion_count,
  imported_at = now();
"""


def validate_db(ctx: Context) -> None:
    guard_production(ctx)
    sql = search_path_sql() + """
SELECT 'openfoodfacts_food_items', count(*)::text FROM food_items WHERE external_source = 'openfoodfacts'
UNION ALL
SELECT 'openfoodfacts_portions', count(*)::text
FROM food_portions portion
JOIN food_items food ON food.id = portion.food_item_id
WHERE food.external_source = 'openfoodfacts'
UNION ALL
SELECT 'duplicate_external_ids', count(*)::text
FROM (
  SELECT external_id FROM food_items
  WHERE external_source = 'openfoodfacts' AND user_id IS NULL
  GROUP BY external_id HAVING count(*) > 1
) duplicates
UNION ALL
SELECT 'english_rows', count(*)::text FROM food_items WHERE external_source = 'openfoodfacts' AND food_key = 'en'
UNION ALL
SELECT 'spanish_rows', count(*)::text FROM food_items WHERE external_source = 'openfoodfacts' AND food_key = 'es';

SELECT source, target_schema, manifest_sha256, food_count, portion_count, imported_at
FROM reference_data_imports
WHERE source = 'openfoodfacts'
ORDER BY imported_at DESC
LIMIT 5;

EXPLAIN ANALYZE
SELECT id, name
FROM food_items
WHERE external_source = 'openfoodfacts'
  AND normalized_name % 'yogurt'
ORDER BY similarity(normalized_name, 'yogurt') DESC
LIMIT 10;
"""
    if import_mode() == "docker-exec":
        print(docker_psql(sql, os.environ.get("OPENFOODFACTS_IMPORT_POSTGRES_CONTAINER", "cal-tracker-postgres")))
        return
    database_url = os.environ.get("OPENFOODFACTS_IMPORT_DATABASE_URL") or os.environ.get("DATABASE_URL")
    if not database_url:
        raise SystemExit("OPENFOODFACTS_IMPORT_DATABASE_URL or DATABASE_URL is required")
    with psycopg.connect(database_url) as conn:
        with conn.cursor() as cur:
            for statement in [part.strip() for part in sql.split(";") if part.strip()]:
                cur.execute(statement)
                if cur.description:
                    for row in cur.fetchall():
                        print(row)


def search_path_sql() -> str:
    schema = database_schema()
    if schema == "public":
        return "SET search_path TO public;"
    return f"SET search_path TO {quote_ident(schema)}, public;"


def database_schema() -> str:
    schema = os.environ.get("OPENFOODFACTS_IMPORT_DATABASE_SCHEMA") or os.environ.get("DATABASE_SCHEMA") or "public"
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", schema):
        raise SystemExit(f"Invalid database schema name: {schema}")
    return schema


def import_manifest(ctx: Context) -> dict[str, object]:
    manifest_path = ctx.manifest_dir / "manifest.json"
    if not manifest_path.exists():
        raise SystemExit(f"Manifest not found: {manifest_path}. Run build/validate before load.")
    return json.loads(manifest_path.read_text(encoding="utf-8"))


def write_manifest(ctx: Context, stats: BuildStats) -> None:
    manifest = {
        "dataset": {
            "label": "Open Food Facts JSONL daily export",
            "url": DATASET_URL,
            "sha256": sha256_file(ctx.raw_path) if ctx.raw_path.exists() else None,
        },
        "source": SOURCE,
        "license": LICENSE,
        "languages": list(ctx.languages),
        "max_products": ctx.max_products,
        "foods": stats.food_rows,
        "portions": stats.portion_rows,
        "products_seen": stats.products_seen,
    }
    write_json(ctx.manifest_dir / "manifest.json", manifest)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def quote_ident(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def docker_psql(sql: str, container: str) -> str:
    user = os.environ.get("OPENFOODFACTS_IMPORT_POSTGRES_USER", "cal_tracker")
    database = os.environ.get("OPENFOODFACTS_IMPORT_POSTGRES_DB", "cal_tracker")
    try:
        completed = subprocess.run(
            ["docker", "exec", "-i", container, "psql", "-v", "ON_ERROR_STOP=1", "-U", user, "-d", database],
            input=sql,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=True,
        )
    except subprocess.CalledProcessError as error:
        if error.stdout:
            print(error.stdout, file=sys.stderr)
        raise
    return completed.stdout


def guard_production(ctx: Context) -> None:
    if ctx.target == "production" and not ctx.confirm_production:
        raise SystemExit("--confirm-production is required for production targets")


def import_mode() -> str:
    return os.environ.get("OPENFOODFACTS_IMPORT_MODE", "direct")


def normalize_text(value: object) -> str:
    text = unicodedata.normalize("NFKD", str(value).lower())
    text = "".join(char for char in text if not unicodedata.combining(char))
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


if __name__ == "__main__":
    raise SystemExit(main())
