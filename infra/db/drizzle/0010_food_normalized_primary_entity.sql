ALTER TABLE "food_normalized_search_documents" ADD COLUMN "primary_entity_name" text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE "food_normalized_search_documents" ADD COLUMN "primary_entity_aliases" text[] DEFAULT '{}'::text[] NOT NULL;--> statement-breakpoint
ALTER TABLE "food_normalized_search_documents" ADD COLUMN "secondary_entity_aliases" text[] DEFAULT '{}'::text[] NOT NULL;--> statement-breakpoint
ALTER TABLE "food_normalized_search_documents" ADD COLUMN "primary_entity_category" text;--> statement-breakpoint
ALTER TABLE "food_normalized_search_documents" ADD COLUMN "primary_entity_category_coherence" numeric(6, 4) DEFAULT '0' NOT NULL;--> statement-breakpoint
CREATE INDEX "food_normalized_search_documents_primary_aliases_gin_idx" ON "food_normalized_search_documents" USING gin ("primary_entity_aliases");--> statement-breakpoint
CREATE INDEX "food_normalized_search_documents_secondary_aliases_gin_idx" ON "food_normalized_search_documents" USING gin ("secondary_entity_aliases");