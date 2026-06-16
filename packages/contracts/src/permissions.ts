export const PermissionScope = {
  Authenticated: "authenticated",
  NutritionReadSummary: "nutrition.read.summary",
  NutritionReadHistory: "nutrition.read.history",
  NutritionReadMemory: "nutrition.read.memory",
  NutritionWritePropose: "nutrition.write.propose",
  NutritionWriteCommit: "nutrition.write.commit",
  NutritionWriteCorrect: "nutrition.write.correct",
  NutritionWriteDelete: "nutrition.write.delete",
  NutritionTemplatesWrite: "nutrition.templates.write",
  NutritionTemplatesRead: "nutrition.templates.read",
  AdminTelemetryRead: "admin.telemetry.read",
  AdminTelemetryWrite: "admin.telemetry.write"
} as const;

export const adminTelemetryScopes: PermissionScope[] = [
  PermissionScope.AdminTelemetryRead,
  PermissionScope.AdminTelemetryWrite
];

export type PermissionScope = (typeof PermissionScope)[keyof typeof PermissionScope];

export const defaultUserScopes: PermissionScope[] = [
  PermissionScope.Authenticated,
  PermissionScope.NutritionReadSummary,
  PermissionScope.NutritionReadHistory,
  PermissionScope.NutritionReadMemory,
  PermissionScope.NutritionWritePropose,
  PermissionScope.NutritionWriteCommit,
  PermissionScope.NutritionWriteCorrect,
  PermissionScope.NutritionWriteDelete,
  PermissionScope.NutritionTemplatesRead,
  PermissionScope.NutritionTemplatesWrite
];
