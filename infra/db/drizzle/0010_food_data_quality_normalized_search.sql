CREATE TABLE "food_item_quality" (
	"food_item_id" uuid PRIMARY KEY NOT NULL,
	"quality_status" text NOT NULL,
	"is_search_eligible" boolean NOT NULL,
	"canonical_food_item_id" uuid,
	"quality_score" numeric(6, 4) NOT NULL,
	"quality_flags" text[] DEFAULT '{}'::text[] NOT NULL,
	"quality_version" text NOT NULL,
	"metadata" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "food_item_quality_status_check" CHECK ("food_item_quality"."quality_status" IN ('valid', 'duplicate', 'suspicious', 'quarantined'))
);
--> statement-breakpoint
CREATE TABLE "food_normalization_sample_items" (
	"sample_set_id" uuid NOT NULL,
	"food_item_id" uuid NOT NULL,
	"sample_reason" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "food_normalization_sample_items_sample_set_id_food_item_id_pk" PRIMARY KEY("sample_set_id","food_item_id")
);
--> statement-breakpoint
CREATE TABLE "food_normalization_sample_sets" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"description" text NOT NULL,
	"seed" text NOT NULL,
	"quality_version" text NOT NULL,
	"normalization_version" text NOT NULL,
	"criteria_json" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "food_normalized_search_documents" (
	"food_item_id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid,
	"locale" text NOT NULL,
	"result_type" text NOT NULL,
	"display_name" text NOT NULL,
	"base_name" text NOT NULL,
	"variant_name" text,
	"brand_display" text,
	"search_text" text NOT NULL,
	"search_aliases" text[] DEFAULT '{}'::text[] NOT NULL,
	"search_vector" "tsvector" NOT NULL,
	"rank_bucket" integer NOT NULL,
	"normalization_version" text NOT NULL,
	"normalization_source" text NOT NULL,
	"normalization_confidence" numeric(6, 4) NOT NULL,
	"quality_flags" text[] DEFAULT '{}'::text[] NOT NULL,
	"metadata" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "food_normalized_search_documents_result_type_check" CHECK ("food_normalized_search_documents"."result_type" IN ('generic_food', 'product', 'custom_food'))
);
--> statement-breakpoint
ALTER TABLE "food_item_quality" ADD CONSTRAINT "food_item_quality_food_item_id_food_items_id_fk" FOREIGN KEY ("food_item_id") REFERENCES "food_items"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "food_item_quality" ADD CONSTRAINT "food_item_quality_canonical_food_item_id_food_items_id_fk" FOREIGN KEY ("canonical_food_item_id") REFERENCES "food_items"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "food_normalization_sample_items" ADD CONSTRAINT "food_normalization_sample_items_sample_set_id_food_normalization_sample_sets_id_fk" FOREIGN KEY ("sample_set_id") REFERENCES "food_normalization_sample_sets"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "food_normalization_sample_items" ADD CONSTRAINT "food_normalization_sample_items_food_item_id_food_items_id_fk" FOREIGN KEY ("food_item_id") REFERENCES "food_items"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "food_normalized_search_documents" ADD CONSTRAINT "food_normalized_search_documents_food_item_id_food_items_id_fk" FOREIGN KEY ("food_item_id") REFERENCES "food_items"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "food_normalized_search_documents" ADD CONSTRAINT "food_normalized_search_documents_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "food_item_quality_eligible_status_idx" ON "food_item_quality" USING btree ("is_search_eligible","quality_status");--> statement-breakpoint
CREATE INDEX "food_item_quality_flags_gin_idx" ON "food_item_quality" USING gin ("quality_flags");--> statement-breakpoint
CREATE INDEX "food_item_quality_canonical_idx" ON "food_item_quality" USING btree ("canonical_food_item_id") WHERE "food_item_quality"."canonical_food_item_id" IS NOT NULL;--> statement-breakpoint
CREATE INDEX "food_normalization_sample_items_sample_food_idx" ON "food_normalization_sample_items" USING btree ("sample_set_id","food_item_id");--> statement-breakpoint
CREATE INDEX "food_normalization_sample_items_reason_idx" ON "food_normalization_sample_items" USING btree ("sample_set_id","sample_reason");--> statement-breakpoint
CREATE UNIQUE INDEX "food_normalization_sample_sets_name_unique" ON "food_normalization_sample_sets" USING btree ("name");--> statement-breakpoint
CREATE INDEX "food_normalized_search_documents_search_text_trgm_idx" ON "food_normalized_search_documents" USING gin ("search_text" gin_trgm_ops);--> statement-breakpoint
CREATE INDEX "food_normalized_search_documents_search_vector_idx" ON "food_normalized_search_documents" USING gin ("search_vector");--> statement-breakpoint
CREATE INDEX "food_normalized_search_documents_locale_type_rank_idx" ON "food_normalized_search_documents" USING btree ("locale","result_type","rank_bucket");--> statement-breakpoint
CREATE INDEX "food_normalized_search_documents_user_idx" ON "food_normalized_search_documents" USING btree ("user_id") WHERE "food_normalized_search_documents"."user_id" IS NOT NULL;
