CREATE INDEX "food_normalized_search_documents_base_name_lower_idx" ON "food_normalized_search_documents" USING btree (lower("base_name"));--> statement-breakpoint
CREATE INDEX "food_normalized_search_documents_display_name_lower_idx" ON "food_normalized_search_documents" USING btree (lower("display_name"));--> statement-breakpoint
CREATE INDEX "food_normalized_search_documents_brand_display_lower_idx" ON "food_normalized_search_documents" USING btree (lower("brand_display"));
