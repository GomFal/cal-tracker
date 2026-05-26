CREATE OR REPLACE FUNCTION sync_food_search_document_from_food_item()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  next_search_text text;
  next_locale text;
  next_scope text;
  next_rank_bucket integer;
BEGIN
  next_search_text := lower(concat_ws(
    ' ',
    NEW.normalized_name,
    NEW.canonical_name,
    NEW.name,
    NEW.brand,
    NEW.food_category
  ));
  next_search_text := regexp_replace(next_search_text, '[^[:alnum:][:space:]]+', ' ', 'g');
  next_search_text := trim(regexp_replace(next_search_text, '[[:space:]]+', ' ', 'g'));

  IF next_search_text = '' THEN
    DELETE FROM food_search_documents WHERE food_item_id = NEW.id;
    RETURN NEW;
  END IF;

  next_locale := CASE
    WHEN NEW.food_key IN ('es', 'en') THEN NEW.food_key
    WHEN NEW.external_source = 'usda_fdc' THEN 'en'
    ELSE 'any'
  END;

  next_scope := CASE
    WHEN NEW.user_id IS NOT NULL THEN 'generic'
    WHEN NEW.data_type IS DISTINCT FROM 'Branded'
      AND NEW.source IS DISTINCT FROM 'usda_branded'
      AND (
        NEW.source IS DISTINCT FROM 'openfoodfacts'
        OR (NEW.barcode IS NULL AND NEW.brand IS NULL)
      ) THEN 'generic'
    ELSE 'market'
  END;

  next_rank_bucket := CASE
    WHEN NEW.user_id IS NOT NULL THEN 0
    WHEN NEW.source = 'openfoodfacts'
      AND NEW.food_key = 'es'
      AND NEW.barcode IS NULL
      AND NEW.brand IS NULL THEN 1
    WHEN NEW.data_type = 'SR Legacy' THEN 2
    WHEN NEW.data_type = 'Foundation' THEN 3
    WHEN NEW.data_type = 'Survey (FNDDS)' THEN 4
    WHEN NEW.source = 'openfoodfacts' THEN 7
    WHEN NEW.data_type = 'Branded' THEN 8
    ELSE 6
  END;

  INSERT INTO food_search_documents (
    food_item_id,
    user_id,
    locale,
    scope,
    search_text,
    rank_bucket,
    source,
    external_source,
    data_type,
    food_key,
    updated_at
  )
  VALUES (
    NEW.id,
    NEW.user_id,
    next_locale,
    next_scope,
    next_search_text,
    next_rank_bucket,
    NEW.source,
    NEW.external_source,
    NEW.data_type,
    NEW.food_key,
    now()
  )
  ON CONFLICT (food_item_id) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    locale = EXCLUDED.locale,
    scope = EXCLUDED.scope,
    search_text = EXCLUDED.search_text,
    rank_bucket = EXCLUDED.rank_bucket,
    source = EXCLUDED.source,
    external_source = EXCLUDED.external_source,
    data_type = EXCLUDED.data_type,
    food_key = EXCLUDED.food_key,
    updated_at = now();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS food_items_search_documents_sync ON food_items;

CREATE TRIGGER food_items_search_documents_sync
AFTER INSERT OR UPDATE OF
  user_id,
  name,
  normalized_name,
  canonical_name,
  brand,
  barcode,
  source,
  external_source,
  data_type,
  food_category,
  food_key
ON food_items
FOR EACH ROW
EXECUTE FUNCTION sync_food_search_document_from_food_item();

UPDATE food_search_documents
SET
  scope = CASE
    WHEN food_items.user_id IS NOT NULL THEN 'generic'
    WHEN food_items.data_type IS DISTINCT FROM 'Branded'
      AND food_items.source IS DISTINCT FROM 'usda_branded'
      AND (
        food_items.source IS DISTINCT FROM 'openfoodfacts'
        OR (food_items.barcode IS NULL AND food_items.brand IS NULL)
      ) THEN 'generic'
    ELSE 'market'
  END,
  rank_bucket = CASE
    WHEN food_items.user_id IS NOT NULL THEN 0
    WHEN food_items.source = 'openfoodfacts'
      AND food_items.food_key = 'es'
      AND food_items.barcode IS NULL
      AND food_items.brand IS NULL THEN 1
    WHEN food_items.data_type = 'SR Legacy' THEN 2
    WHEN food_items.data_type = 'Foundation' THEN 3
    WHEN food_items.data_type = 'Survey (FNDDS)' THEN 4
    WHEN food_items.source = 'openfoodfacts' THEN 7
    WHEN food_items.data_type = 'Branded' THEN 8
    ELSE 6
  END,
  updated_at = now()
FROM food_items
WHERE food_items.id = food_search_documents.food_item_id
  AND (
    food_items.source = 'openfoodfacts'
    OR food_items.data_type = 'Branded'
    OR food_items.source = 'usda_branded'
    OR food_items.user_id IS NOT NULL
  );
