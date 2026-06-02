CREATE TABLE "food_normalization_review" (
	"food_item_id" uuid PRIMARY KEY NOT NULL,
	"normalization_version" text NOT NULL,
	"review_status" text NOT NULL,
	"severity" text NOT NULL,
	"issue_codes" text[] DEFAULT '{}'::text[] NOT NULL,
	"raw_name" text NOT NULL,
	"raw_brand" text,
	"raw_source" text,
	"raw_external_source" text,
	"raw_data_type" text,
	"display_name" text,
	"base_name" text,
	"variant_name" text,
	"brand_display" text,
	"primary_entity_name" text,
	"locale" text,
	"result_type" text,
	"normalization_confidence" numeric(6, 4),
	"metrics" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"metadata" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "food_normalization_review_status_check" CHECK ("review_status" IN ('valid', 'needs_review', 'failed')),
	CONSTRAINT "food_normalization_review_severity_check" CHECK ("severity" IN ('info', 'warning', 'error'))
);
--> statement-breakpoint
ALTER TABLE "food_normalization_review" ADD CONSTRAINT "food_normalization_review_food_item_id_food_items_id_fk" FOREIGN KEY ("food_item_id") REFERENCES "food_items"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
CREATE INDEX "food_normalization_review_status_severity_idx" ON "food_normalization_review" USING btree ("review_status","severity");
--> statement-breakpoint
CREATE INDEX "food_normalization_review_issue_codes_gin_idx" ON "food_normalization_review" USING gin ("issue_codes");
--> statement-breakpoint
CREATE INDEX "food_normalization_review_version_idx" ON "food_normalization_review" USING btree ("normalization_version");
--> statement-breakpoint
CREATE INDEX "food_normalization_review_display_idx" ON "food_normalization_review" USING btree ("locale", "result_type", lower("display_name"));
