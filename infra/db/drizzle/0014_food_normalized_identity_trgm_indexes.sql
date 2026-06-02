CREATE INDEX "food_normalized_search_documents_base_name_trgm_idx" ON "food_normalized_search_documents" USING gin (lower("base_name") gin_trgm_ops);--> statement-breakpoint
CREATE INDEX "food_normalized_search_documents_display_name_trgm_idx" ON "food_normalized_search_documents" USING gin (lower("display_name") gin_trgm_ops);--> statement-breakpoint
CREATE INDEX "food_normalized_search_documents_brand_display_trgm_idx" ON "food_normalized_search_documents" USING gin (lower("brand_display") gin_trgm_ops);
