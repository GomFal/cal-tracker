import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { zodToJsonSchema } from "zod-to-json-schema";
import {
  actionDefinitions,
  agentRunRequestSchema,
  agentRunResponseSchema,
  calorieEstimateRequestSchema,
  calorieEstimateResponseSchema,
  dailyHydrationResponseSchema,
  dailyHydrationUpdateSchema,
  errorResponseSchema,
  executeActionRequestSchema,
  executeActionResponseSchema,
  foodSearchRequestSchema,
  foodSearchResponseSchema,
  goalsResponseSchema,
  goalsUpdateSchema,
  googleLoginRequestSchema,
  loginRequestSchema,
  passwordResetConfirmSchema,
  passwordResetRequestSchema,
  refreshRequestSchema,
  registerRequestSchema,
  settingsUpdateSchema,
  tokenPairSchema,
  transcriptionResponseSchema
} from "./index.js";

const schema = (name: string, zodSchema: Parameters<typeof zodToJsonSchema>[0]) =>
  zodToJsonSchema(zodSchema, { name, $refStrategy: "none" }).definitions?.[name] ??
  zodToJsonSchema(zodSchema, { $refStrategy: "none" });

const actionSchemas = Object.fromEntries(
  actionDefinitions.flatMap((action) => [
    [`${action.id}_input`, schema(`${action.id}_input`, action.inputSchema)],
    [`${action.id}_output`, schema(`${action.id}_output`, action.outputSchema)]
  ])
);

const voiceMealRunResponseOpenApiSchema = {
  type: "object",
  properties: {
    transcript: { type: "string" },
    provider: { type: "string" },
    model: { type: "string" },
    traceId: { type: "string" },
    result: { $ref: "#/components/schemas/AgentRunResponse" }
  },
  required: ["transcript", "provider", "model", "traceId", "result"],
  additionalProperties: false
};

const spec = {
  openapi: "3.1.0",
  info: {
    title: "Cal Tracker API",
    version: "0.1.0"
  },
  servers: [{ url: "http://localhost:3000" }],
  components: {
    securitySchemes: {
      bearerAuth: {
        type: "http",
        scheme: "bearer",
        bearerFormat: "JWT"
      }
    },
    schemas: {
      ErrorResponse: schema("ErrorResponse", errorResponseSchema),
      RegisterRequest: schema("RegisterRequest", registerRequestSchema),
      LoginRequest: schema("LoginRequest", loginRequestSchema),
      GoogleLoginRequest: schema("GoogleLoginRequest", googleLoginRequestSchema),
      RefreshRequest: schema("RefreshRequest", refreshRequestSchema),
      PasswordResetRequest: schema("PasswordResetRequest", passwordResetRequestSchema),
      PasswordResetConfirm: schema("PasswordResetConfirm", passwordResetConfirmSchema),
      TokenPair: schema("TokenPair", tokenPairSchema),
      SettingsUpdate: schema("SettingsUpdate", settingsUpdateSchema),
      GoalsUpdate: schema("GoalsUpdate", goalsUpdateSchema),
      GoalsResponse: schema("GoalsResponse", goalsResponseSchema),
      DailyHydrationUpdate: schema("DailyHydrationUpdate", dailyHydrationUpdateSchema),
      DailyHydrationResponse: schema("DailyHydrationResponse", dailyHydrationResponseSchema),
      CalorieEstimateRequest: schema("CalorieEstimateRequest", calorieEstimateRequestSchema),
      CalorieEstimateResponse: schema("CalorieEstimateResponse", calorieEstimateResponseSchema),
      ExecuteActionRequest: schema("ExecuteActionRequest", executeActionRequestSchema),
      ExecuteActionResponse: schema("ExecuteActionResponse", executeActionResponseSchema),
      FoodSearchRequest: schema("FoodSearchRequest", foodSearchRequestSchema),
      FoodSearchResponse: schema("FoodSearchResponse", foodSearchResponseSchema),
      AgentRunRequest: schema("AgentRunRequest", agentRunRequestSchema),
      AgentRunResponse: schema("AgentRunResponse", agentRunResponseSchema),
      TranscriptionResponse: schema("TranscriptionResponse", transcriptionResponseSchema),
      VoiceMealRunResponse: voiceMealRunResponseOpenApiSchema,
      ...actionSchemas
    }
  },
  paths: {
    "/v1/health": {
      get: {
        operationId: "getHealth",
        responses: {
          "200": {
            description: "Health status"
          }
        }
      }
    },
    "/v1/auth/register": {
      post: {
        operationId: "register",
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/RegisterRequest" } } }
        },
        responses: {
          "200": { description: "Token pair", content: { "application/json": { schema: { $ref: "#/components/schemas/TokenPair" } } } }
        }
      }
    },
    "/v1/auth/login": {
      post: {
        operationId: "login",
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/LoginRequest" } } }
        },
        responses: {
          "200": { description: "Token pair", content: { "application/json": { schema: { $ref: "#/components/schemas/TokenPair" } } } }
        }
      }
    },
    "/v1/auth/google/login": {
      post: {
        operationId: "loginWithGoogle",
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/GoogleLoginRequest" } } }
        },
        responses: {
          "200": { description: "Token pair", content: { "application/json": { schema: { $ref: "#/components/schemas/TokenPair" } } } }
        }
      }
    },
    "/v1/auth/refresh": {
      post: {
        operationId: "refresh",
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/RefreshRequest" } } }
        },
        responses: {
          "200": { description: "Token pair", content: { "application/json": { schema: { $ref: "#/components/schemas/TokenPair" } } } }
        }
      }
    },
    "/v1/auth/me": {
      get: {
        operationId: "getMe",
        security: [{ bearerAuth: [] }],
        responses: {
          "200": { description: "Current user" }
        }
      }
    },
    "/v1/settings": {
      put: {
        operationId: "updateSettings",
        security: [{ bearerAuth: [] }],
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/SettingsUpdate" } } }
        },
        responses: {
          "200": { description: "Updated settings" }
        }
      }
    },
    "/v1/goals": {
      put: {
        operationId: "updateGoals",
        security: [{ bearerAuth: [] }],
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/GoalsUpdate" } } }
        },
        responses: {
          "200": { description: "Updated daily goals", content: { "application/json": { schema: { $ref: "#/components/schemas/GoalsResponse" } } } }
        }
      }
    },
    "/v1/goals/calorie-estimate": {
      post: {
        operationId: "estimateCalories",
        security: [{ bearerAuth: [] }],
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/CalorieEstimateRequest" } } }
        },
        responses: {
          "200": { description: "Estimated calorie target", content: { "application/json": { schema: { $ref: "#/components/schemas/CalorieEstimateResponse" } } } }
        }
      }
    },
    "/v1/actions": {
      get: {
        operationId: "listActions",
        security: [{ bearerAuth: [] }],
        responses: { "200": { description: "Action metadata" } }
      }
    },
    "/v1/actions/{actionId}/execute": {
      post: {
        operationId: "executeAction",
        security: [{ bearerAuth: [] }],
        parameters: [{ name: "actionId", in: "path", required: true, schema: { type: "string" } }],
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionRequest" } } }
        },
        responses: {
          "200": { description: "Action result", content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionResponse" } } } }
        }
      }
    },
    "/v1/foods/search": {
      post: {
        operationId: "searchFoods",
        security: [{ bearerAuth: [] }],
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/FoodSearchRequest" } } }
        },
        responses: {
          "200": { description: "Food search results", content: { "application/json": { schema: { $ref: "#/components/schemas/FoodSearchResponse" } } } }
        }
      }
    },
    "/v1/agent/runs": {
      post: {
        operationId: "runAgent",
        security: [{ bearerAuth: [] }],
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/AgentRunRequest" } } }
        },
        responses: {
          "200": { description: "Agent result", content: { "application/json": { schema: { $ref: "#/components/schemas/AgentRunResponse" } } } }
        }
      }
    },
    "/v1/stt/transcriptions": {
      post: {
        operationId: "transcribeAudio",
        security: [{ bearerAuth: [] }],
        requestBody: {
          required: true,
          content: {
            "multipart/form-data": {
              schema: {
                type: "object",
                properties: { audio: { type: "string", format: "binary" }, source: { type: "string" } },
                required: ["audio"]
              }
            }
          }
        },
        responses: {
          "200": { description: "Transcript", content: { "application/json": { schema: { $ref: "#/components/schemas/TranscriptionResponse" } } } }
        }
      }
    },
    "/v1/voice/meal-runs": {
      post: {
        operationId: "runVoiceMeal",
        security: [{ bearerAuth: [] }],
        requestBody: {
          required: true,
          content: {
            "multipart/form-data": {
              schema: {
                type: "object",
                properties: { audio: { type: "string", format: "binary" }, source: { type: "string" } },
                required: ["audio"]
              }
            }
          }
        },
        responses: {
          "200": { description: "Transcript and meal agent result", content: { "application/json": { schema: { $ref: "#/components/schemas/VoiceMealRunResponse" } } } }
        }
      }
    },
    "/v1/meals/proposals": {
      post: {
        operationId: "createMealProposal",
        security: [{ bearerAuth: [] }],
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/propose_meal_log_input" } } }
        },
        responses: {
          "200": { description: "Proposal action result", content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionResponse" } } } }
        }
      }
    },
    "/v1/meals/proposals/{proposalId}/commit": {
      post: {
        operationId: "commitMealProposal",
        security: [{ bearerAuth: [] }],
        parameters: [{ name: "proposalId", in: "path", required: true, schema: { type: "string", format: "uuid" } }],
        responses: {
          "200": { description: "Commit action result", content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionResponse" } } } }
        }
      }
    },
    "/v1/meals/{mealId}/correct": {
      post: {
        operationId: "correctMeal",
        security: [{ bearerAuth: [] }],
        parameters: [{ name: "mealId", in: "path", required: true, schema: { type: "string", format: "uuid" } }],
        requestBody: {
          required: true,
          content: {
            "application/json": {
              schema: { $ref: "#/components/schemas/correct_meal_input" }
            }
          }
        },
        responses: {
          "200": { description: "Correction action result", content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionResponse" } } } }
        }
      }
    },
    "/v1/meals/{mealId}": {
      delete: {
        operationId: "deleteMeal",
        security: [{ bearerAuth: [] }],
        parameters: [
          { name: "mealId", in: "path", required: true, schema: { type: "string", format: "uuid" } },
          { name: "confirmationToken", in: "query", required: false, schema: { type: "string" } }
        ],
        responses: {
          "200": { description: "Delete action result", content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionResponse" } } } }
        }
      }
    },
    "/v1/summary/daily": {
      get: {
        operationId: "getDailySummary",
        security: [{ bearerAuth: [] }],
        parameters: [{ name: "date", in: "query", required: false, schema: { type: "string" } }],
        responses: {
          "200": { description: "Daily summary action result", content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionResponse" } } } }
        }
      }
    },
    "/v1/hydration/daily": {
      put: {
        operationId: "updateDailyHydration",
        security: [{ bearerAuth: [] }],
        requestBody: {
          required: true,
          content: {
            "application/json": {
              schema: { $ref: "#/components/schemas/DailyHydrationUpdate" }
            }
          }
        },
        responses: {
          "200": { description: "Updated hydration summary", content: { "application/json": { schema: { $ref: "#/components/schemas/DailyHydrationResponse" } } } }
        }
      }
    },
    "/v1/meals": {
      get: {
        operationId: "getMealHistory",
        security: [{ bearerAuth: [] }],
        parameters: [{ name: "limit", in: "query", required: false, schema: { type: "integer", minimum: 1, maximum: 100 } }],
        responses: {
          "200": { description: "Meal history action result", content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionResponse" } } } }
        }
      }
    },
    "/v1/meal-templates": {
      get: {
        operationId: "getMealTemplates",
        security: [{ bearerAuth: [] }],
        responses: {
          "200": { description: "Template action result", content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionResponse" } } } }
        }
      },
      post: {
        operationId: "createMealTemplate",
        security: [{ bearerAuth: [] }],
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/create_meal_template_input" } } }
        },
        responses: {
          "200": { description: "Template action result", content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionResponse" } } } }
        }
      }
    },
    "/v1/meal-templates/{templateId}": {
      put: {
        operationId: "updateMealTemplate",
        security: [{ bearerAuth: [] }],
        parameters: [{ name: "templateId", in: "path", required: true, schema: { type: "string", format: "uuid" } }],
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/update_meal_template_input" } } }
        },
        responses: {
          "200": { description: "Template action result", content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionResponse" } } } }
        }
      },
      delete: {
        operationId: "deleteMealTemplate",
        security: [{ bearerAuth: [] }],
        parameters: [{ name: "templateId", in: "path", required: true, schema: { type: "string", format: "uuid" } }],
        responses: {
          "200": { description: "Template delete action result", content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionResponse" } } } }
        }
      }
    }
  }
};

const outPath = resolve(process.cwd(), "openapi.json");
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, `${JSON.stringify(spec, null, 2)}\n`);
console.log(`Wrote ${outPath}`);
