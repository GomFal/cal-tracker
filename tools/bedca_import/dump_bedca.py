#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import unicodedata
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import psycopg
import requests
from tqdm import tqdm


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATA_DIR = ROOT / "data" / "bedca"
BASE_URL = "https://www.bedca.net/bdpub"
QUERY_URL = f"{BASE_URL}/procquery.php"
TERMS_URL = f"{BASE_URL}/UsoBD.pdf"
SOURCE_URL = f"{BASE_URL}/index.php"
SOURCE = "bedca"
DATA_TYPE = "BEDCA"
ATTRIBUTION = "AESAN/BEDCA Base de Datos Española de Composición de Alimentos v1.0 (2010)"
LICENSE = "BEDCA usage terms; attribution required"
USER_AGENT = "better-calories-bedca-dump/0.1 (local inspection; https://bettercalories.app)"

LIST_SELECTION = [
    "f_id",
    "f_ori_name",
    "langual",
    "f_eng_name",
    "f_origen",
    "edible_portion",
]

DETAIL_SELECTION = [
    "f_id",
    "f_ori_name",
    "f_eng_name",
    "sci_name",
    "langual",
    "foodexcode",
    "mainlevelcode",
    "codlevel1",
    "namelevel1",
    "codsublevel",
    "codlevel2",
    "namelevel2",
    "f_des_esp",
    "f_des_ing",
    "photo",
    "edible_portion",
    "f_origen",
    "c_id",
    "c_ori_name",
    "c_eng_name",
    "eur_name",
    "componentgroup_id",
    "glos_esp",
    "glos_ing",
    "cg_descripcion",
    "cg_description",
    "best_location",
    "v_unit",
    "moex",
    "stdv",
    "min",
    "max",
    "v_n",
    "u_id",
    "u_descripcion",
    "u_description",
    "value_type",
    "vt_descripcion",
    "vt_description",
    "mu_id",
    "mu_descripcion",
    "mu_description",
    "ref_id",
    "citation",
    "at_descripcion",
    "at_description",
    "pt_descripcion",
    "pt_description",
    "method_id",
    "mt_descripcion",
    "mt_description",
    "m_descripcion",
    "m_description",
    "m_nom_esp",
    "m_nom_ing",
    "mhd_descripcion",
    "mhd_description",
]

FOOD_COLUMNS = [
    "bedca_id",
    "name_es",
    "name_en",
    "origin",
    "langual",
    "edible_portion",
    "source",
    "attribution",
    "terms_url",
]

NUTRIENT_COLUMNS = [
    "bedca_id",
    "name_es",
    "component_id",
    "component_es",
    "component_en",
    "eur_name",
    "component_group_id",
    "component_group_es",
    "value",
    "unit",
    "measure",
    "value_type",
    "reference_id",
    "citation",
    "method_id",
    "method_es",
]

CORE_EUR_NAMES = {
    "ENERC": "energy_kj",
    "FAT": "fat_g",
    "PROT": "protein_g",
    "CHO": "carbs_g",
    "FIBT": "fiber_g",
    "WATER": "water_g",
    "ALC": "alcohol_g",
}

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

MACRO_EUR_NAMES = {
    "calories": "ENERC",
    "protein_grams": "PROT",
    "carbs_grams": "CHO",
    "fat_grams": "FAT",
}

OPTIONAL_NUTRIENTS = {
    "fiber_grams": "FIBT",
    "sugars_grams": "SUGAR",
    "saturated_fat_grams": "FASAT",
    "sodium_mg": "NA",
}


@dataclass(frozen=True)
class Context:
    data_dir: Path
    delay: float
    target: str

    @property
    def raw_dir(self) -> Path:
        return self.data_dir / "raw"

    @property
    def details_dir(self) -> Path:
        return self.raw_dir / "details"

    @property
    def normalized_dir(self) -> Path:
        return self.data_dir / "normalized"

    @property
    def reports_dir(self) -> Path:
        return self.data_dir / "reports"

    @property
    def manifest_dir(self) -> Path:
        return self.data_dir / "manifests"

    @property
    def foods_xml_path(self) -> Path:
        return self.raw_dir / "foods.xml"

    @property
    def foods_json_path(self) -> Path:
        return self.normalized_dir / "foods.json"

    @property
    def foods_csv_path(self) -> Path:
        return self.normalized_dir / "foods.csv"

    @property
    def nutrients_csv_path(self) -> Path:
        return self.normalized_dir / "nutrients.csv"

    @property
    def load_foods_path(self) -> Path:
        return self.normalized_dir / "load_foods.csv"

    @property
    def load_portions_path(self) -> Path:
        return self.normalized_dir / "load_food_portions.csv"

    @property
    def summary_path(self) -> Path:
        return self.reports_dir / "summary.json"

    @property
    def skipped_foods_path(self) -> Path:
        return self.reports_dir / "skipped_foods.json"

    @property
    def load_skipped_foods_path(self) -> Path:
        return self.reports_dir / "load_skipped_foods.json"

    @property
    def validation_path(self) -> Path:
        return self.reports_dir / "validation.json"

    @property
    def manifest_path(self) -> Path:
        return self.manifest_dir / "manifest.json"

    def ensure_dirs(self) -> None:
        for directory in [self.raw_dir, self.details_dir, self.normalized_dir, self.reports_dir, self.manifest_dir]:
            directory.mkdir(parents=True, exist_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Create and validate a BEDCA inspection corpus.")
    parser.add_argument(
        "command",
        choices=[
            "dump",
            "summarize",
            "validate",
            "sample",
            "build-load",
            "validate-db",
        ],
    )
    parser.add_argument("--data-dir", default=str(DEFAULT_DATA_DIR))
    parser.add_argument("--delay", type=float, default=0.2)
    parser.add_argument("--limit", type=int, help="Only fetch the first N foods; useful for smoke tests.")
    parser.add_argument("--target", choices=["local"], default="local")
    args = parser.parse_args()

    ctx = Context(Path(args.data_dir), args.delay, args.target)
    ctx.ensure_dirs()
    if args.command == "dump":
        dump(ctx, args.limit)
    elif args.command == "summarize":
        summarize(ctx)
    elif args.command == "validate":
        validate(ctx)
    elif args.command == "sample":
        sample(ctx)
    elif args.command == "build-load":
        build_load(ctx)
    elif args.command == "validate-db":
        validate_db(ctx)
    return 0


def dump(ctx: Context, limit: int | None) -> None:
    foods_xml = post_food_list()
    ctx.foods_xml_path.write_bytes(foods_xml)
    foods = parse_food_list(foods_xml)
    if limit is not None:
        foods = foods[:limit]

    normalized_foods: list[dict[str, object]] = []
    nutrients: list[dict[str, object]] = []
    skipped_foods: list[dict[str, object]] = []
    for index, food in enumerate(tqdm(foods, desc="BEDCA foods")):
        if index > 0:
            time.sleep(ctx.delay)
        detail_path = ctx.details_dir / f"{food['bedca_id']}.xml"
        if detail_path.exists() and detail_path.stat().st_size > 0:
            detail_xml = detail_path.read_bytes()
        else:
            detail_xml = post_food_detail(food["bedca_id"])
            detail_path.write_bytes(detail_xml)
        food_record, nutrient_records = parse_food_detail(detail_xml)
        if not food_record["bedca_id"]:
            skipped_foods.append(
                {
                    **food,
                    "source": SOURCE,
                    "attribution": ATTRIBUTION,
                    "terms_url": TERMS_URL,
                    "skip_reason": "BEDCA detail response contained an empty food node",
                }
            )
            continue
        normalized_foods.append(food_record)
        nutrients.extend(nutrient_records)

    write_json(ctx.foods_json_path, normalized_foods)
    write_csv(ctx.foods_csv_path, FOOD_COLUMNS, normalized_foods)
    write_csv(ctx.nutrients_csv_path, NUTRIENT_COLUMNS, nutrients)
    write_json(ctx.skipped_foods_path, skipped_foods)
    summarize(ctx)


def post_food_list() -> bytes:
    xml = build_query_xml(
        level="1",
        selection=LIST_SELECTION,
        conditions=[("f_origen", "EQUAL", "BEDCA")],
        order=("f_ori_name", "ASC"),
    )
    return post_query(xml)


def post_food_detail(food_id: str) -> bytes:
    xml = build_query_xml(
        level="2",
        selection=DETAIL_SELECTION,
        conditions=[("f_id", "EQUAL", food_id), ("publico", "EQUAL", "1")],
        order=("componentgroup_id", "ASC"),
    )
    return post_query(xml)


def build_query_xml(
    *,
    level: str,
    selection: list[str],
    conditions: list[tuple[str, str, str]],
    order: tuple[str, str] | None,
) -> bytes:
    root = ET.Element("foodquery")
    ET.SubElement(root, "type", {"level": level})
    selection_node = ET.SubElement(root, "selection")
    for name in selection:
        ET.SubElement(selection_node, "atribute", {"name": name})
    for left, relation, value in conditions:
        condition = ET.SubElement(root, "condition")
        cond1 = ET.SubElement(condition, "cond1")
        ET.SubElement(cond1, "atribute1", {"name": left})
        ET.SubElement(condition, "relation", {"type": relation})
        ET.SubElement(condition, "cond3").text = value
    if order is not None:
        order_node = ET.SubElement(root, "order", {"ordtype": order[1]})
        ET.SubElement(order_node, "atribute3", {"name": order[0]})
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def post_query(xml: bytes) -> bytes:
    last_error: Exception | None = None
    for attempt in range(1, 5):
        try:
            response = requests.post(
                QUERY_URL,
                data=xml,
                headers={"Content-Type": "text/xml", "User-Agent": USER_AGENT},
                timeout=60,
            )
            response.raise_for_status()
            if response.text.startswith("error:"):
                raise RuntimeError(response.text)
            return response.content
        except (requests.RequestException, RuntimeError) as error:
            last_error = error
            if attempt == 4:
                break
            time.sleep(2 * attempt)
    raise RuntimeError(f"BEDCA query failed after retries: {last_error}") from last_error


def parse_food_list(xml: bytes) -> list[dict[str, str]]:
    root = ET.fromstring(xml)
    foods: list[dict[str, str]] = []
    for node in root.findall("food"):
        foods.append(
            {
                "bedca_id": text(node, "f_id"),
                "name_es": text(node, "f_ori_name"),
                "name_en": text(node, "f_eng_name"),
                "origin": text(node, "f_origen"),
                "langual": text(node, "langual"),
                "edible_portion": text(node, "edible_portion"),
            }
        )
    return foods


def parse_food_detail(xml: bytes) -> tuple[dict[str, object], list[dict[str, object]]]:
    root = ET.fromstring(xml)
    food = root.find("food")
    if food is None:
        raise RuntimeError("BEDCA detail response did not contain a food node")
    food_record = {
        "bedca_id": text(food, "f_id"),
        "name_es": text(food, "f_ori_name"),
        "name_en": text(food, "f_eng_name"),
        "origin": text(food, "f_origen"),
        "langual": text(food, "langual"),
        "edible_portion": text(food, "edible_portion"),
        "source": SOURCE,
        "attribution": ATTRIBUTION,
        "terms_url": TERMS_URL,
    }
    nutrients = []
    for value in food.findall("foodvalue"):
        nutrients.append(
            {
                "bedca_id": food_record["bedca_id"],
                "name_es": food_record["name_es"],
                "component_id": text(value, "c_id"),
                "component_es": text(value, "c_ori_name"),
                "component_en": text(value, "c_eng_name"),
                "eur_name": text(value, "eur_name"),
                "component_group_id": text(value, "componentgroup_id"),
                "component_group_es": text(value, "cg_descripcion"),
                "value": text(value, "best_location"),
                "unit": text(value, "v_unit"),
                "measure": text(value, "mu_descripcion"),
                "value_type": text(value, "value_type"),
                "reference_id": text(value, "ref_id"),
                "citation": text(value, "citation"),
                "method_id": text(value, "method_id"),
                "method_es": text(value, "m_nom_esp"),
            }
        )
    return food_record, nutrients


def summarize(ctx: Context) -> None:
    foods = read_json(ctx.foods_json_path)
    nutrients = list(read_csv(ctx.nutrients_csv_path))
    skipped_foods = read_json(ctx.skipped_foods_path) if ctx.skipped_foods_path.exists() else []
    summary = {
        "source": SOURCE,
        "attribution": ATTRIBUTION,
        "terms_url": TERMS_URL,
        "food_count": len(foods),
        "skipped_food_count": len(skipped_foods),
        "nutrient_row_count": len(nutrients),
        "origin_counts": counts(food.get("origin", "") for food in foods),
        "core_component_counts": counts(row["eur_name"] for row in nutrients if row["eur_name"] in CORE_EUR_NAMES),
        "sample_foods": foods[:10],
        "skipped_foods": skipped_foods,
    }
    write_json(ctx.summary_path, summary)
    print(json.dumps(summary, indent=2, ensure_ascii=False))


def validate(ctx: Context) -> None:
    foods = read_json(ctx.foods_json_path)
    nutrients = list(read_csv(ctx.nutrients_csv_path))
    errors: list[str] = []
    if not foods:
        errors.append("no foods were dumped")
    if not nutrients:
        errors.append("no nutrient rows were dumped")
    seen = set()
    duplicate_ids = set()
    for food in foods:
        bedca_id = food.get("bedca_id")
        if not bedca_id:
            errors.append("food without bedca_id")
        elif bedca_id in seen:
            duplicate_ids.add(bedca_id)
        seen.add(bedca_id)
    if duplicate_ids:
        errors.append(f"duplicate food ids: {sorted(duplicate_ids)[:10]}")
    nutrient_food_ids = {row["bedca_id"] for row in nutrients}
    missing_nutrients = sorted(str(food["bedca_id"]) for food in foods if str(food["bedca_id"]) not in nutrient_food_ids)
    if missing_nutrients:
        errors.append(f"foods without nutrient rows: {missing_nutrients[:10]}")
    if errors:
        raise SystemExit("Validation failed: " + "; ".join(errors))
    print(f"Validation passed: {len(foods)} foods, {len(nutrients)} nutrient rows")


def sample(ctx: Context) -> None:
    foods = read_json(ctx.foods_json_path)
    nutrients_by_food: dict[str, list[dict[str, str]]] = {}
    for row in read_csv(ctx.nutrients_csv_path):
        nutrients_by_food.setdefault(row["bedca_id"], []).append(row)
    for food in foods[:5]:
        bedca_id = str(food["bedca_id"])
        core = [
            row
            for row in nutrients_by_food.get(bedca_id, [])
            if row["eur_name"] in CORE_EUR_NAMES
        ]
        print(json.dumps({"food": food, "core_nutrients": core}, ensure_ascii=False, indent=2))


def build_load(ctx: Context) -> None:
    validate(ctx)
    foods = read_json(ctx.foods_json_path)
    nutrients_by_food: dict[str, list[dict[str, str]]] = {}
    for row in read_csv(ctx.nutrients_csv_path):
        nutrients_by_food.setdefault(row["bedca_id"], []).append(row)

    load_foods: list[dict[str, object]] = []
    load_portions: list[dict[str, object]] = []
    skipped: list[dict[str, object]] = []
    for food in foods:
        food_id = str(food["bedca_id"])
        nutrients = nutrients_by_food.get(food_id, [])
        nutrition = nutrition_for_food(nutrients)
        if nutrition is None:
            skipped.append(
                {
                    **food,
                    "skip_reason": "missing required calories/protein/carbs/fat values",
                }
            )
            continue
        name_es = str(food["name_es"])
        load_foods.append(food_load_row(food, nutrition, nutrients))
        load_portions.append(portion_load_row(food_id, name_es))

    write_csv(ctx.load_foods_path, FOOD_LOAD_COLUMNS, load_foods)
    write_csv(ctx.load_portions_path, PORTION_LOAD_COLUMNS, load_portions)
    write_json(ctx.load_skipped_foods_path, skipped)
    validate_load(ctx)
    write_manifest(ctx, len(load_foods), len(load_portions), len(skipped))
    print(f"Wrote {len(load_foods):,} BEDCA load foods and {len(load_portions):,} portions")


def nutrition_for_food(nutrients: list[dict[str, str]]) -> dict[str, float] | None:
    by_eur = first_nutrient_by_eur(nutrients)
    calories = energy_kcal(by_eur.get(MACRO_EUR_NAMES["calories"]))
    protein = grams_value(by_eur.get(MACRO_EUR_NAMES["protein_grams"]))
    carbs = grams_value(by_eur.get(MACRO_EUR_NAMES["carbs_grams"]))
    fat = grams_value(by_eur.get(MACRO_EUR_NAMES["fat_grams"]))
    if any(value is None for value in [calories, protein, carbs, fat]):
        return None
    result = {
        "calories": calories,
        "protein_grams": protein,
        "carbs_grams": carbs,
        "fat_grams": fat,
    }
    fiber = grams_value(by_eur.get(OPTIONAL_NUTRIENTS["fiber_grams"]))
    sugars = grams_value(by_eur.get(OPTIONAL_NUTRIENTS["sugars_grams"]))
    saturated_fat = grams_value(by_eur.get(OPTIONAL_NUTRIENTS["saturated_fat_grams"]))
    sodium = mg_value(by_eur.get(OPTIONAL_NUTRIENTS["sodium_mg"]))
    if fiber is not None:
        result["fiber_grams"] = fiber
    if sugars is not None:
        result["sugars_grams"] = sugars
    if saturated_fat is not None:
        result["saturated_fat_grams"] = saturated_fat
    if sodium is not None:
        result["sodium_mg"] = sodium
    if not valid_nutrition(result):
        return None
    return result


def first_nutrient_by_eur(nutrients: list[dict[str, str]]) -> dict[str, dict[str, str]]:
    result: dict[str, dict[str, str]] = {}
    for nutrient in nutrients:
        eur_name = nutrient.get("eur_name", "")
        if eur_name and eur_name not in result:
            result[eur_name] = nutrient
    return result


def food_load_row(food: dict[str, object], nutrition: dict[str, float], nutrients: list[dict[str, str]]) -> dict[str, object]:
    food_id = str(food["bedca_id"])
    name_es = str(food["name_es"])
    nutrients_json = {
        "source": SOURCE,
        "attribution": ATTRIBUTION,
        "terms_url": TERMS_URL,
        "source_url": SOURCE_URL,
        "bedca_id": food_id,
        "name_es": name_es,
        "name_en": food.get("name_en", ""),
        "origin": food.get("origin", ""),
        "langual": food.get("langual", ""),
        "edible_portion": food.get("edible_portion", ""),
        "nutrients": nutrients,
    }
    return {
        "external_id": food_id,
        "name": name_es,
        "normalized_name": normalize_text(name_es),
        "canonical_name": name_es,
        "data_type": DATA_TYPE,
        "food_category": "",
        "publication_date": "",
        "food_key": "es",
        "brand": "",
        "barcode": "",
        "ingredients": "",
        "market_country": "",
        "household_serving_fulltext": "100 g",
        "source_url": SOURCE_URL,
        "license": LICENSE,
        "serving_grams": "100",
        "calories": round_number(nutrition["calories"], 3),
        "protein_grams": round_number(nutrition["protein_grams"], 3),
        "carbs_grams": round_number(nutrition["carbs_grams"], 3),
        "fat_grams": round_number(nutrition["fat_grams"], 3),
        "nutrients_json": json.dumps(nutrients_json, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
    }


def portion_load_row(food_id: str, name_es: str) -> dict[str, object]:
    aliases = ["100 g", "100 gramos", "g", "gramos", normalize_text(name_es)]
    return {
        "external_food_id": food_id,
        "usda_portion_id": "",
        "amount": "100",
        "unit": "g",
        "modifier": "",
        "description": "100 g",
        "gram_weight": "100",
        "normalized_aliases_json": json.dumps(sorted(set(alias for alias in aliases if alias)), ensure_ascii=False),
        "kind": "serving",
        "source_description": "por 100 g de porción comestible",
    }


def validate_load(ctx: Context) -> None:
    errors: list[str] = []
    food_count = count_csv_rows(ctx.load_foods_path)
    portion_count = count_csv_rows(ctx.load_portions_path)
    if food_count == 0:
        errors.append("no BEDCA load foods were built")
    if portion_count != food_count:
        errors.append(f"portion count {portion_count} does not match food count {food_count}")
    duplicate_ids = duplicate_external_ids(ctx.load_foods_path)
    if duplicate_ids:
        errors.append(f"duplicate BEDCA external ids found: {duplicate_ids[:5]}")
    invalid_rows = invalid_load_rows(ctx.load_foods_path)
    if invalid_rows:
        errors.append(f"invalid BEDCA nutrition rows: {invalid_rows[:5]}")
    report = {
        "foods": food_count,
        "portions": portion_count,
        "skipped_load_foods": len(read_json(ctx.load_skipped_foods_path)) if ctx.load_skipped_foods_path.exists() else 0,
        "errors": errors,
    }
    write_json(ctx.validation_path, report)
    if errors:
        raise SystemExit("Validation failed: " + "; ".join(errors))
    print("Load validation passed")


def load(ctx: Context) -> None:
    guard_application_load(ctx)
    validate_load(ctx)
    food_count = count_csv_rows(ctx.load_foods_path)
    portion_count = count_csv_rows(ctx.load_portions_path)
    if import_mode() == "docker-exec":
        docker_load(ctx, food_count, portion_count)
    else:
        direct_load(ctx, food_count, portion_count)


def direct_load(ctx: Context, food_count: int, portion_count: int) -> None:
    database_url = os.environ.get("BEDCA_IMPORT_DATABASE_URL") or os.environ.get("DATABASE_URL")
    if not database_url:
        raise SystemExit("BEDCA_IMPORT_DATABASE_URL or DATABASE_URL is required")
    with psycopg.connect(database_url) as conn:
        with conn.transaction():
            with conn.cursor() as cur:
                cur.execute(search_path_sql())
                cur.execute(stage_food_sql())
                copy_csv(cur, ctx.load_foods_path, f"COPY bedca_food_stage ({','.join(FOOD_LOAD_COLUMNS)}) FROM STDIN WITH (FORMAT csv, HEADER true)")
                cur.execute(stage_portion_sql())
                copy_csv(cur, ctx.load_portions_path, f"COPY bedca_portion_stage ({','.join(PORTION_LOAD_COLUMNS)}) FROM STDIN WITH (FORMAT csv, HEADER true)")
                cur.execute(prepare_stage_sql())
                cur.execute(merge_stage_sql())
                cur.execute(record_import_sql(ctx, food_count, portion_count))
    print(f"Loaded {food_count:,} BEDCA foods and {portion_count:,} portions")


def copy_csv(cur: psycopg.Cursor, path: Path, statement: str) -> None:
    with cur.copy(statement) as copy:
        with path.open("r", encoding="utf-8", newline="") as fh:
            for chunk in iter(lambda: fh.read(1024 * 1024), ""):
                if chunk:
                    copy.write(chunk)


def docker_load(ctx: Context, food_count: int, portion_count: int) -> None:
    container = os.environ.get("BEDCA_IMPORT_POSTGRES_CONTAINER", "cal-tracker-postgres")
    subprocess.run(["docker", "cp", str(ctx.load_foods_path), f"{container}:/tmp/bedca_foods.csv"], check=True)
    subprocess.run(["docker", "cp", str(ctx.load_portions_path), f"{container}:/tmp/bedca_food_portions.csv"], check=True)
    sql = "\n".join(
        [
            search_path_sql(),
            "BEGIN;",
            stage_food_sql(),
            f"\\copy bedca_food_stage ({','.join(FOOD_LOAD_COLUMNS)}) FROM '/tmp/bedca_foods.csv' WITH (FORMAT csv, HEADER true)",
            stage_portion_sql(),
            f"\\copy bedca_portion_stage ({','.join(PORTION_LOAD_COLUMNS)}) FROM '/tmp/bedca_food_portions.csv' WITH (FORMAT csv, HEADER true)",
            prepare_stage_sql(),
            merge_stage_sql(),
            record_import_sql(ctx, food_count, portion_count),
            "COMMIT;",
        ]
    )
    print(docker_psql(sql, container))
    subprocess.run(["docker", "exec", container, "rm", "-f", "/tmp/bedca_foods.csv", "/tmp/bedca_food_portions.csv"], check=False)
    print(f"Loaded {food_count:,} BEDCA foods and {portion_count:,} portions")


def stage_food_sql() -> str:
    columns = ",\n  ".join(f"{column} text" for column in FOOD_LOAD_COLUMNS)
    return f"CREATE TEMP TABLE bedca_food_stage (\n  {columns}\n) ON COMMIT DROP;"


def stage_portion_sql() -> str:
    columns = ",\n  ".join(f"{column} text" for column in PORTION_LOAD_COLUMNS)
    return f"CREATE TEMP TABLE bedca_portion_stage (\n  {columns}\n) ON COMMIT DROP;"


def prepare_stage_sql() -> str:
    return """
CREATE INDEX bedca_food_stage_external_id_idx ON bedca_food_stage (external_id);
CREATE INDEX bedca_portion_stage_external_food_id_idx ON bedca_portion_stage (external_food_id);
ANALYZE bedca_food_stage;
ANALYZE bedca_portion_stage;
"""


def merge_stage_sql() -> str:
    return """
UPDATE food_items target
SET name = stage.name,
    normalized_name = stage.normalized_name,
    canonical_name = stage.canonical_name,
    brand = NULLIF(stage.brand, ''),
    barcode = NULLIF(stage.barcode, ''),
    source = 'bedca',
    external_source = 'bedca',
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
FROM bedca_food_stage stage
WHERE target.external_source = 'bedca'
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
  NULLIF(stage.brand, ''), NULLIF(stage.barcode, ''), 'bedca',
  'bedca', stage.external_id, stage.source_url, stage.license, now(),
  stage.data_type, NULLIF(stage.food_category, ''), NULLIF(stage.publication_date, '')::date,
  NULL, stage.food_key, NULLIF(stage.ingredients, ''),
  NULLIF(stage.market_country, ''), NULLIF(stage.household_serving_fulltext, ''),
  COALESCE(NULLIF(stage.nutrients_json, '')::jsonb, '{}'::jsonb),
  NULLIF(stage.serving_grams, '')::numeric, round(NULLIF(stage.calories, '')::numeric)::integer,
  NULLIF(stage.protein_grams, '')::numeric, NULLIF(stage.carbs_grams, '')::numeric,
  NULLIF(stage.fat_grams, '')::numeric
FROM bedca_food_stage stage
WHERE NOT EXISTS (
  SELECT 1 FROM food_items existing
  WHERE existing.external_source = 'bedca'
    AND existing.external_id = stage.external_id
    AND existing.user_id IS NULL
);

DELETE FROM food_portions portion
USING food_items food, bedca_food_stage stage
WHERE portion.food_item_id = food.id
  AND food.external_source = 'bedca'
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
  COALESCE(NULLIF(stage.source_description, ''), 'BEDCA portion')
FROM bedca_portion_stage stage
JOIN food_items food
  ON food.external_source = 'bedca'
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
    guard_application_load(ctx)
    sql = search_path_sql() + """
SELECT 'bedca_food_items', count(*)::text FROM food_items WHERE external_source = 'bedca'
UNION ALL
SELECT 'bedca_portions', count(*)::text
FROM food_portions portion
JOIN food_items food ON food.id = portion.food_item_id
WHERE food.external_source = 'bedca'
UNION ALL
SELECT 'duplicate_external_ids', count(*)::text
FROM (
  SELECT external_id FROM food_items
  WHERE external_source = 'bedca' AND user_id IS NULL
  GROUP BY external_id HAVING count(*) > 1
) duplicates
UNION ALL
SELECT 'spanish_rows', count(*)::text FROM food_items WHERE external_source = 'bedca' AND food_key = 'es';

SELECT source, target_schema, manifest_sha256, food_count, portion_count, imported_at
FROM reference_data_imports
WHERE source = 'bedca'
ORDER BY imported_at DESC
LIMIT 5;

SELECT id, name, canonical_name, calories, protein_grams, carbs_grams, fat_grams
FROM food_items
WHERE external_source = 'bedca'
  AND normalized_name % 'aceite oliva'
ORDER BY similarity(normalized_name, 'aceite oliva') DESC
LIMIT 10;
"""
    if import_mode() == "docker-exec":
        print(docker_psql(sql, os.environ.get("BEDCA_IMPORT_POSTGRES_CONTAINER", "cal-tracker-postgres")))
        return
    database_url = os.environ.get("BEDCA_IMPORT_DATABASE_URL") or os.environ.get("DATABASE_URL")
    if not database_url:
        raise SystemExit("BEDCA_IMPORT_DATABASE_URL or DATABASE_URL is required")
    with psycopg.connect(database_url) as conn:
        with conn.cursor() as cur:
            for statement in [part.strip() for part in sql.split(";") if part.strip()]:
                cur.execute(statement)
                if cur.description:
                    for row in cur.fetchall():
                        print(row)


def write_manifest(ctx: Context, food_count: int, portion_count: int, skipped_count: int) -> None:
    manifest = {
        "source": SOURCE,
        "data_type": DATA_TYPE,
        "attribution": ATTRIBUTION,
        "license": LICENSE,
        "terms_url": TERMS_URL,
        "source_url": SOURCE_URL,
        "foods": food_count,
        "portions": portion_count,
        "skipped_load_foods": skipped_count,
        "raw_foods_sha256": sha256_file(ctx.foods_xml_path) if ctx.foods_xml_path.exists() else None,
        "normalized_foods_sha256": sha256_file(ctx.foods_csv_path) if ctx.foods_csv_path.exists() else None,
        "normalized_nutrients_sha256": sha256_file(ctx.nutrients_csv_path) if ctx.nutrients_csv_path.exists() else None,
    }
    write_json(ctx.manifest_path, manifest)


def import_manifest(ctx: Context) -> dict[str, object]:
    if not ctx.manifest_path.exists():
        raise SystemExit(f"Manifest not found: {ctx.manifest_path}. Run build-load before load.")
    return json.loads(ctx.manifest_path.read_text(encoding="utf-8"))


def energy_kcal(row: dict[str, str] | None) -> float | None:
    if row is None:
        return None
    value = nutrient_number_value(row)
    if value is None:
        return None
    unit = normalize_text(row.get("unit", ""))
    if unit == "kj":
        return value / 4.184
    if unit == "kcal":
        return value
    return None


def grams_value(row: dict[str, str] | None) -> float | None:
    if row is None:
        return None
    value = nutrient_number_value(row)
    if value is None:
        return None
    unit = normalize_text(row.get("unit", ""))
    if unit == "g":
        return value
    if unit == "mg":
        return value / 1000
    if unit == "ug":
        return value / 1_000_000
    return None


def mg_value(row: dict[str, str] | None) -> float | None:
    if row is None:
        return None
    value = nutrient_number_value(row)
    if value is None:
        return None
    unit = normalize_text(row.get("unit", ""))
    if unit == "mg":
        return value
    if unit == "g":
        return value * 1000
    if unit == "ug":
        return value / 1000
    return None


def valid_nutrition(nutrition: dict[str, float]) -> bool:
    return (
        0 <= nutrition["calories"] <= 2000
        and 0 <= nutrition["protein_grams"] <= 100
        and 0 <= nutrition["carbs_grams"] <= 100
        and 0 <= nutrition["fat_grams"] <= 100
    )


def invalid_load_rows(path: Path) -> list[str]:
    invalid: list[str] = []
    with path.open("r", encoding="utf-8", newline="") as fh:
        for row in csv.DictReader(fh):
            nutrition = {
                "calories": number_value(row.get("calories")),
                "protein_grams": number_value(row.get("protein_grams")),
                "carbs_grams": number_value(row.get("carbs_grams")),
                "fat_grams": number_value(row.get("fat_grams")),
            }
            if any(value is None for value in nutrition.values()) or not valid_nutrition(nutrition):  # type: ignore[arg-type]
                invalid.append(row.get("external_id", ""))
                if len(invalid) >= 25:
                    break
    return invalid


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


def count_csv_rows(path: Path) -> int:
    with path.open("r", encoding="utf-8", newline="") as fh:
        return max(0, sum(1 for _ in fh) - 1)


def number_value(value: object) -> float | None:
    if value is None:
        return None
    text_value = str(value).strip().replace(",", ".")
    if not text_value:
        return None
    try:
        return float(text_value)
    except ValueError:
        return None


def nutrient_number_value(row: dict[str, str]) -> float | None:
    value = number_value(row.get("value"))
    if value is not None:
        return value
    if normalize_text(row.get("value_type", "")) == "tr":
        return 0
    return None


def round_number(value: float, digits: int) -> str:
    rounded = round(value, digits)
    if rounded == int(rounded):
        return str(int(rounded))
    return str(rounded)


def search_path_sql() -> str:
    schema = database_schema()
    if schema == "public":
        return "SET search_path TO public;"
    return f"SET search_path TO {quote_ident(schema)}, public;"


def database_schema() -> str:
    schema = os.environ.get("BEDCA_IMPORT_DATABASE_SCHEMA") or os.environ.get("DATABASE_SCHEMA") or "public"
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", schema):
        raise SystemExit(f"Invalid database schema name: {schema}")
    return schema


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def quote_ident(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def docker_psql(sql: str, container: str) -> str:
    user = os.environ.get("BEDCA_IMPORT_POSTGRES_USER", "cal_tracker")
    database = os.environ.get("BEDCA_IMPORT_POSTGRES_DB", "cal_tracker")
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


def guard_application_load(ctx: Context) -> None:
    if ctx.target != "local":
        raise SystemExit("BEDCA may only be inspected locally; application database loading is not supported")


def import_mode() -> str:
    return os.environ.get("BEDCA_IMPORT_MODE", "direct")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_text(value: object) -> str:
    text = unicodedata.normalize("NFKD", str(value).lower())
    text = "".join(char for char in text if not unicodedata.combining(char))
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def text(node: ET.Element, tag: str) -> str:
    value = node.findtext(tag)
    return "" if value is None else value.strip()


def counts(values: Iterable[str]) -> dict[str, int]:
    result: dict[str, int] = {}
    for value in values:
        result[value] = result.get(value, 0) + 1
    return dict(sorted(result.items(), key=lambda item: (-item[1], item[0])))


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")


def read_json(path: Path) -> list[dict[str, object]]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_csv(path: Path, columns: list[str], rows: Iterable[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=columns)
        writer.writeheader()
        for row in rows:
            writer.writerow({column: row.get(column, "") for column in columns})


def read_csv(path: Path) -> Iterable[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8") as fh:
        yield from csv.DictReader(fh)


if __name__ == "__main__":
    raise SystemExit(main())
