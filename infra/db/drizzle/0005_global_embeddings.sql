WITH ranked AS (
  SELECT
    food_item_embeddings.id,
    row_number() OVER (
      PARTITION BY food_item_embeddings.food_item_id
      ORDER BY
        CASE
          WHEN embedding_models.provider = 'local'
            AND embedding_models.model = 'bge-m3'
            AND embedding_models.dimensions = 1024
          THEN 0
          ELSE 1
        END,
        food_item_embeddings.updated_at DESC,
        food_item_embeddings.created_at DESC,
        food_item_embeddings.id
    ) AS row_number
  FROM food_item_embeddings
  LEFT JOIN embedding_models ON embedding_models.id = food_item_embeddings.embedding_model_id
)
DELETE FROM food_item_embeddings
USING ranked
WHERE food_item_embeddings.id = ranked.id
  AND ranked.row_number > 1;
--> statement-breakpoint
WITH ranked AS (
  SELECT
    food_memory_embeddings.id,
    row_number() OVER (
      PARTITION BY food_memory_embeddings.food_memory_id
      ORDER BY
        CASE
          WHEN embedding_models.provider = 'local'
            AND embedding_models.model = 'bge-m3'
            AND embedding_models.dimensions = 1024
          THEN 0
          ELSE 1
        END,
        food_memory_embeddings.created_at DESC,
        food_memory_embeddings.id
    ) AS row_number
  FROM food_memory_embeddings
  LEFT JOIN embedding_models ON embedding_models.id = food_memory_embeddings.embedding_model_id
)
DELETE FROM food_memory_embeddings
USING ranked
WHERE food_memory_embeddings.id = ranked.id
  AND ranked.row_number > 1;
--> statement-breakpoint
ALTER TABLE "food_item_embeddings" DROP CONSTRAINT IF EXISTS "food_item_embeddings_embedding_model_id_embedding_models_id_fk";
--> statement-breakpoint
ALTER TABLE "food_memory_embeddings" DROP CONSTRAINT IF EXISTS "food_memory_embeddings_embedding_model_id_embedding_models_id_fk";
--> statement-breakpoint
DROP INDEX IF EXISTS "embedding_models_lookup_idx";
--> statement-breakpoint
DROP INDEX IF EXISTS "food_item_embeddings_food_model_unique";
--> statement-breakpoint
DROP INDEX IF EXISTS "food_item_embeddings_model_idx";
--> statement-breakpoint
DROP INDEX IF EXISTS "food_item_embeddings_hash_idx";
--> statement-breakpoint
ALTER TABLE "food_item_embeddings" DROP COLUMN IF EXISTS "embedding_model_id";
--> statement-breakpoint
ALTER TABLE "food_memory_embeddings" DROP COLUMN IF EXISTS "embedding_model_id";
--> statement-breakpoint
DROP TABLE IF EXISTS "embedding_models";
--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "food_item_embeddings_food_unique" ON "food_item_embeddings" USING btree ("food_item_id");
--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "food_memory_embeddings_memory_unique" ON "food_memory_embeddings" USING btree ("food_memory_id");
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "food_item_embeddings_hash_idx" ON "food_item_embeddings" USING btree ("embedded_text_hash");
