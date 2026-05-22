import { z } from "zod";
import {
  dailySummarySchema,
  foodCandidateSchema,
  foodMentionSchema,
  mealLabelTypeSchema,
  mealItemSchema,
  mealProposalSchema,
  mealSchema,
  mealTemplateSchema,
  nutritionSnapshotSchema,
  uuidSchema,
} from "./common.js";
import { PermissionScope } from "./permissions.js";

export const actionSourceSchema = z.enum([
  "flutter",
  "internal_agent",
  "android_appfunctions",
  "ios_appintents",
  "rest",
]);

export type ActionSource = z.infer<typeof actionSourceSchema>;

export const actionContextSchema = z.object({
  actorUserId: uuidSchema,
  actorType: z.enum(["user", "internal_agent", "external_agent"]),
  source: actionSourceSchema,
  scopes: z.array(z.nativeEnum(PermissionScope)),
  timezone: z.string(),
  locale: z.string(),
  trustedModeEnabled: z.boolean(),
  traceId: z.string(),
});

export type ActionContext = z.infer<typeof actionContextSchema>;

const emptyInputSchema = z.object({}).default({});

export const queryFoodMemoryInputSchema = z.object({
  text: z.string().min(1),
});
export const queryFoodMemoryOutputSchema = z.object({
  matches: z.array(
    z.object({
      id: uuidSchema,
      label: z.string(),
      normalizedText: z.string(),
      confidence: z.number().min(0).max(1),
      template: mealTemplateSchema.nullable(),
    }),
  ),
  needsClarification: z.boolean(),
});

export const searchNutritionDatabaseInputSchema = z.object({
  query: z.string().min(1),
  barcode: z.string().optional(),
});
export const searchNutritionDatabaseOutputSchema = z.object({
  items: z.array(mealItemSchema),
  candidates: z.array(foodCandidateSchema).optional(),
  candidateGroups: z.array(foodCandidateSchema).optional(),
});

export const proposeMealLogInputSchema = z.object({
  text: z.string().min(1),
  mentions: z.array(foodMentionSchema).optional(),
  occurredAt: z.string().datetime().optional(),
});
export const proposeMealLogOutputSchema = z.object({
  proposal: mealProposalSchema.optional(),
  autoCommittedMeal: mealSchema.nullable().optional(),
  clarificationRequired: z.boolean().optional(),
  resolvedItems: z.array(mealItemSchema).optional(),
  unresolvedMentions: z.array(foodMentionSchema).optional(),
  options: z.array(foodCandidateSchema).optional(),
  candidateGroups: z.array(foodCandidateSchema).optional(),
  message: z.string().optional(),
});

export const createMealProposalFromItemsInputSchema = z.object({
  phrase: z.string().min(1),
  title: z.string().min(1).optional(),
  items: z.array(mealItemSchema).min(1),
  occurredAt: z.string().datetime().optional(),
});
export const createMealProposalFromItemsOutputSchema = z.object({
  proposal: mealProposalSchema,
});

export const commitMealInputSchema = z.object({
  proposalId: uuidSchema,
  occurredAt: z.string().datetime().optional(),
  items: z.array(mealItemSchema).optional(),
  mealLabel: z.object({
    type: mealLabelTypeSchema,
    label: z.string().trim().max(40).optional(),
  }).nullable().optional(),
});
export const commitMealOutputSchema = z.object({
  meal: mealSchema,
});

export const correctMealInputSchema = z
  .object({
    mealId: uuidSchema.optional(),
    proposalId: uuidSchema.optional(),
    items: z.array(mealItemSchema).min(1),
  })
  .refine(
    (value) => value.mealId || value.proposalId,
    "mealId or proposalId is required",
  );
export const correctMealOutputSchema = z.object({
  proposal: mealProposalSchema.optional(),
  meal: mealSchema.optional(),
});

export const reviseMealProposalOperationSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("add_item"),
    mention: foodMentionSchema,
  }),
  z.object({
    type: z.literal("remove_item"),
    itemIndex: z.number().int().nonnegative().optional(),
    matchText: z.string().min(1).optional(),
  }),
  z.object({
    type: z.literal("replace_item"),
    itemIndex: z.number().int().nonnegative().optional(),
    matchText: z.string().min(1).optional(),
    mention: foodMentionSchema,
  }),
  z.object({
    type: z.literal("update_item_quantity"),
    itemIndex: z.number().int().nonnegative().optional(),
    matchText: z.string().min(1).optional(),
    quantity: z.number().positive(),
    unit: z.string().min(1),
    rawUnitText: z.string().min(1).optional(),
  }),
]);
export const reviseMealProposalInputSchema = z.object({
  proposalId: uuidSchema,
  instruction: z.string().min(1),
  operations: z.array(reviseMealProposalOperationSchema).min(1),
});
export const reviseMealProposalOutputSchema = z.object({
  proposal: mealProposalSchema.optional(),
  clarificationRequired: z.boolean().optional(),
  resolvedItems: z.array(mealItemSchema).optional(),
  unresolvedMentions: z.array(foodMentionSchema).optional(),
  options: z.array(foodCandidateSchema).optional(),
  candidateGroups: z.array(foodCandidateSchema).optional(),
  message: z.string().optional(),
});

export const deleteMealInputSchema = z.object({
  mealId: uuidSchema,
  confirmationToken: z.string().optional(),
});
export const deleteMealOutputSchema = z.object({
  deleted: z.boolean(),
  confirmationRequired: z.boolean(),
});

export const getDailySummaryInputSchema = z.object({
  date: z.string().optional(),
});
export const getDailySummaryOutputSchema = z.object({
  summary: dailySummarySchema,
});

export const getRemainingTargetsInputSchema = getDailySummaryInputSchema;
export const getRemainingTargetsOutputSchema = z.object({
  remaining: nutritionSnapshotSchema,
});

export const getMealHistoryInputSchema = z.object({
  limit: z.number().int().min(1).max(100).default(25),
});
export const getMealHistoryOutputSchema = z.object({
  meals: z.array(mealSchema),
});

export const getUsualMealsOutputSchema = z.object({
  templates: z.array(mealTemplateSchema),
});

export const createMealTemplateInputSchema = z.object({
  title: z.string().min(1),
  trustedAutoCommitEnabled: z.boolean().default(false),
  items: z.array(mealItemSchema).min(1),
  aliases: z.array(z.string()).default([]),
});
export const createMealTemplateOutputSchema = z.object({
  template: mealTemplateSchema,
});

export const updateMealTemplateInputSchema = createMealTemplateInputSchema
  .partial()
  .extend({
    templateId: uuidSchema,
  });
export const updateMealTemplateOutputSchema = createMealTemplateOutputSchema;

export const deleteMealTemplateInputSchema = z.object({
  templateId: uuidSchema,
});
export const deleteMealTemplateOutputSchema = z.object({
  deleted: z.boolean(),
});

export type ConfirmationPolicy =
  | "never"
  | "required"
  | "trusted_auto_commit_allowed";
export type SideEffect = "none" | "proposal" | "write" | "destructive";
export type ExecutionMode = "deterministic" | "agent_assisted";

export type ActionDefinition = {
  id: string;
  version: string;
  title: string;
  description: string;
  inputSchema: z.ZodTypeAny;
  outputSchema: z.ZodTypeAny;
  permissionScope: PermissionScope;
  sideEffect: SideEffect;
  confirmationPolicy: ConfirmationPolicy;
  executionMode: ExecutionMode;
};

export const actionDefinitions = [
  {
    id: "query_food_memory",
    version: "1.0.0",
    title: "Query Food Memory",
    description: "Retrieve user-scoped food memories and usual meal aliases.",
    inputSchema: queryFoodMemoryInputSchema,
    outputSchema: queryFoodMemoryOutputSchema,
    permissionScope: PermissionScope.NutritionReadMemory,
    sideEffect: "none",
    confirmationPolicy: "never",
    executionMode: "deterministic",
  },
  {
    id: "search_nutrition_database",
    version: "1.0.0",
    title: "Search Nutrition Database",
    description: "Search user custom foods and generic nutrition entries.",
    inputSchema: searchNutritionDatabaseInputSchema,
    outputSchema: searchNutritionDatabaseOutputSchema,
    permissionScope: PermissionScope.NutritionReadMemory,
    sideEffect: "none",
    confirmationPolicy: "never",
    executionMode: "deterministic",
  },
  {
    id: "propose_meal_log",
    version: "1.0.0",
    title: "Propose Meal Log",
    description:
      "Create a meal proposal from typed or transcribed natural language. Include structured food mentions when the caller can identify foods and quantities.",
    inputSchema: proposeMealLogInputSchema,
    outputSchema: proposeMealLogOutputSchema,
    permissionScope: PermissionScope.NutritionWritePropose,
    sideEffect: "proposal",
    confirmationPolicy: "required",
    executionMode: "agent_assisted",
  },
  {
    id: "commit_meal",
    version: "1.0.0",
    title: "Commit Meal",
    description: "Commit a confirmed meal proposal as a meal snapshot.",
    inputSchema: commitMealInputSchema,
    outputSchema: commitMealOutputSchema,
    permissionScope: PermissionScope.NutritionWriteCommit,
    sideEffect: "write",
    confirmationPolicy: "required",
    executionMode: "deterministic",
  },
  {
    id: "create_meal_proposal_from_items",
    version: "1.0.0",
    title: "Create Meal Proposal From Items",
    description:
      "Create a meal proposal from explicit user-selected nutrition items.",
    inputSchema: createMealProposalFromItemsInputSchema,
    outputSchema: createMealProposalFromItemsOutputSchema,
    permissionScope: PermissionScope.NutritionWritePropose,
    sideEffect: "proposal",
    confirmationPolicy: "required",
    executionMode: "deterministic",
  },
  {
    id: "correct_meal",
    version: "1.0.0",
    title: "Correct Meal",
    description: "Apply a user correction to a proposal or committed meal.",
    inputSchema: correctMealInputSchema,
    outputSchema: correctMealOutputSchema,
    permissionScope: PermissionScope.NutritionWriteCorrect,
    sideEffect: "write",
    confirmationPolicy: "required",
    executionMode: "deterministic",
  },
  {
    id: "revise_meal_proposal",
    version: "1.0.0",
    title: "Revise Meal Proposal",
    description:
      "Apply a natural-language correction to a pending meal proposal using structured add, remove, replace, or quantity update operations.",
    inputSchema: reviseMealProposalInputSchema,
    outputSchema: reviseMealProposalOutputSchema,
    permissionScope: PermissionScope.NutritionWriteCorrect,
    sideEffect: "proposal",
    confirmationPolicy: "required",
    executionMode: "deterministic",
  },
  {
    id: "delete_meal",
    version: "1.0.0",
    title: "Delete Meal",
    description: "Soft-delete a committed meal after explicit confirmation.",
    inputSchema: deleteMealInputSchema,
    outputSchema: deleteMealOutputSchema,
    permissionScope: PermissionScope.NutritionWriteDelete,
    sideEffect: "destructive",
    confirmationPolicy: "required",
    executionMode: "deterministic",
  },
  {
    id: "get_daily_summary",
    version: "1.0.0",
    title: "Get Daily Summary",
    description: "Get calories and macro totals for a day.",
    inputSchema: getDailySummaryInputSchema,
    outputSchema: getDailySummaryOutputSchema,
    permissionScope: PermissionScope.NutritionReadSummary,
    sideEffect: "none",
    confirmationPolicy: "never",
    executionMode: "deterministic",
  },
  {
    id: "get_remaining_targets",
    version: "1.0.0",
    title: "Get Remaining Targets",
    description: "Get remaining calories and macros for a day.",
    inputSchema: getRemainingTargetsInputSchema,
    outputSchema: getRemainingTargetsOutputSchema,
    permissionScope: PermissionScope.NutritionReadSummary,
    sideEffect: "none",
    confirmationPolicy: "never",
    executionMode: "deterministic",
  },
  {
    id: "get_meal_history",
    version: "1.0.0",
    title: "Get Meal History",
    description: "List recent committed meals.",
    inputSchema: getMealHistoryInputSchema,
    outputSchema: getMealHistoryOutputSchema,
    permissionScope: PermissionScope.NutritionReadHistory,
    sideEffect: "none",
    confirmationPolicy: "never",
    executionMode: "deterministic",
  },
  {
    id: "get_usual_meals",
    version: "1.0.0",
    title: "Get Usual Meals",
    description: "List user-owned recurring meal templates.",
    inputSchema: emptyInputSchema,
    outputSchema: getUsualMealsOutputSchema,
    permissionScope: PermissionScope.NutritionTemplatesRead,
    sideEffect: "none",
    confirmationPolicy: "never",
    executionMode: "deterministic",
  },
  {
    id: "create_meal_template",
    version: "1.0.0",
    title: "Create Meal Template",
    description: "Create a reusable usual meal template.",
    inputSchema: createMealTemplateInputSchema,
    outputSchema: createMealTemplateOutputSchema,
    permissionScope: PermissionScope.NutritionTemplatesWrite,
    sideEffect: "write",
    confirmationPolicy: "required",
    executionMode: "deterministic",
  },
  {
    id: "update_meal_template",
    version: "1.0.0",
    title: "Update Meal Template",
    description: "Update a user-owned usual meal template.",
    inputSchema: updateMealTemplateInputSchema,
    outputSchema: updateMealTemplateOutputSchema,
    permissionScope: PermissionScope.NutritionTemplatesWrite,
    sideEffect: "write",
    confirmationPolicy: "required",
    executionMode: "deterministic",
  },
  {
    id: "delete_meal_template",
    version: "1.0.0",
    title: "Delete Meal Template",
    description: "Delete a user-owned usual meal template.",
    inputSchema: deleteMealTemplateInputSchema,
    outputSchema: deleteMealTemplateOutputSchema,
    permissionScope: PermissionScope.NutritionTemplatesWrite,
    sideEffect: "destructive",
    confirmationPolicy: "required",
    executionMode: "deterministic",
  },
] satisfies ActionDefinition[];

export type ActionId = (typeof actionDefinitions)[number]["id"];

export const actionById = new Map(
  actionDefinitions.map((definition) => [definition.id, definition]),
);
