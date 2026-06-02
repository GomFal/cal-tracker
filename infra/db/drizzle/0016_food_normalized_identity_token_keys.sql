ALTER TABLE "food_normalized_search_documents" ADD COLUMN "identity_token_keys" text[] DEFAULT '{}'::text[] NOT NULL;--> statement-breakpoint
CREATE INDEX "food_normalized_search_documents_identity_token_keys_gin_idx" ON "food_normalized_search_documents" USING gin ("identity_token_keys");
