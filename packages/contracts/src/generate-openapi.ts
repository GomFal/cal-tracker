import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { zodToJsonSchema } from "zod-to-json-schema";
import {
  actionDefinitions,
  adminActionCallsResponseSchema,
  adminAgentConversationDetailResponseSchema,
  adminAgentConversationsResponseSchema,
  adminAgentToolCallsResponseSchema,
  adminAgentTurnsResponseSchema,
  adminLoginRequestSchema,
  adminLlmCostResponseSchema,
  adminLlmProviderCallsResponseSchema,
  adminTranscriptionsResponseSchema,
  adminTokenResponseSchema,
  agentChatRequestSchema,
  commitAgentChatProposalRequestSchema,
  commitAgentChatProposalResponseSchema,
  agentConversationDetailResponseSchema,
  agentConversationsResponseSchema,
  deleteAgentConversationResponseSchema,
  agentRunRequestSchema,
  agentRunResponseSchema,
  calorieEstimateRequestSchema,
  calorieEstimateResponseSchema,
  clientTelemetryIngestRequestSchema,
  clientTelemetryIngestResponseSchema,
  createUsualFoodRequestSchema,
  dailyHydrationResponseSchema,
  dailyHydrationUpdateSchema,
  errorResponseSchema,
  emailConfirmationRequestSchema,
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
  authRequestAcceptedResponseSchema,
  refreshRequestSchema,
  rateLimitErrorResponseSchema,
  registerRequestSchema,
  registrationPendingResponseSchema,
  settingsUpdateSchema,
  telemetryEventsResponseSchema,
  telemetryFoodSearchResponseSchema,
  telemetryLlmRunsResponseSchema,
  telemetryOverviewResponseSchema,
  telemetryTraceResponseSchema,
  tokenPairSchema,
  transcriptionResponseSchema,
  updateUsualFoodRequestSchema,
  usualFoodDraftRequestSchema,
  usualFoodDraftResponseSchema,
  usualFoodResponseSchema,
  usualMealDraftRequestSchema,
  usualMealDraftResponseSchema,
  usualFoodsResponseSchema
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

const jsonContent = (schemaRef: string) => ({
  "application/json": { schema: { $ref: schemaRef } }
});

const jsonResponse = (description: string, schemaRef: string) => ({
  description,
  content: jsonContent(schemaRef)
});

const rateLimitResponse = {
  description: "Request rate or concurrency limit exceeded",
  headers: {
    "Retry-After": {
      description: "Seconds until the client should retry",
      schema: { type: "integer", minimum: 1 },
    },
  },
  content: jsonContent("#/components/schemas/RateLimitErrorResponse"),
};

const queryParameter = (
  name: string,
  schema: Record<string, unknown>,
  required = false
) => ({
  name,
  in: "query",
  required,
  schema
});

const telemetryCommonQueryParameters = [
  queryParameter("limit", { type: "integer", minimum: 1, maximum: 200 }),
  queryParameter("traceId", { type: "string", maxLength: 120 }),
  queryParameter("userId", { type: "string", format: "uuid" }),
  queryParameter("from", { type: "string", format: "date-time" }),
  queryParameter("to", { type: "string", format: "date-time" })
];

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
      RateLimitErrorResponse: schema("RateLimitErrorResponse", rateLimitErrorResponseSchema),
      RegisterRequest: schema("RegisterRequest", registerRequestSchema),
      AuthRequestAcceptedResponse: schema("AuthRequestAcceptedResponse", authRequestAcceptedResponseSchema),
      RegistrationPendingResponse: schema("RegistrationPendingResponse", registrationPendingResponseSchema),
      LoginRequest: schema("LoginRequest", loginRequestSchema),
      AdminLoginRequest: schema("AdminLoginRequest", adminLoginRequestSchema),
      AdminTokenResponse: schema("AdminTokenResponse", adminTokenResponseSchema),
      GoogleLoginRequest: schema("GoogleLoginRequest", googleLoginRequestSchema),
      EmailConfirmationRequest: schema("EmailConfirmationRequest", emailConfirmationRequestSchema),
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
      CreateUsualFoodRequest: schema("CreateUsualFoodRequest", createUsualFoodRequestSchema),
      UpdateUsualFoodRequest: schema("UpdateUsualFoodRequest", updateUsualFoodRequestSchema),
      UsualFoodResponse: schema("UsualFoodResponse", usualFoodResponseSchema),
      UsualFoodsResponse: schema("UsualFoodsResponse", usualFoodsResponseSchema),
      UsualFoodDraftRequest: schema("UsualFoodDraftRequest", usualFoodDraftRequestSchema),
      UsualFoodDraftResponse: schema("UsualFoodDraftResponse", usualFoodDraftResponseSchema),
      UsualMealDraftRequest: schema("UsualMealDraftRequest", usualMealDraftRequestSchema),
      UsualMealDraftResponse: schema("UsualMealDraftResponse", usualMealDraftResponseSchema),
      AgentRunRequest: schema("AgentRunRequest", agentRunRequestSchema),
      AgentChatRequest: schema("AgentChatRequest", agentChatRequestSchema),
      CommitAgentChatProposalRequest: schema("CommitAgentChatProposalRequest", commitAgentChatProposalRequestSchema),
      CommitAgentChatProposalResponse: schema("CommitAgentChatProposalResponse", commitAgentChatProposalResponseSchema),
      AgentRunResponse: schema("AgentRunResponse", agentRunResponseSchema),
      AgentConversationsResponse: schema("AgentConversationsResponse", agentConversationsResponseSchema),
      AgentConversationDetailResponse: schema("AgentConversationDetailResponse", agentConversationDetailResponseSchema),
      DeleteAgentConversationResponse: schema("DeleteAgentConversationResponse", deleteAgentConversationResponseSchema),
      TranscriptionResponse: schema("TranscriptionResponse", transcriptionResponseSchema),
      VoiceMealRunResponse: voiceMealRunResponseOpenApiSchema,
      ClientTelemetryIngestRequest: schema("ClientTelemetryIngestRequest", clientTelemetryIngestRequestSchema),
      ClientTelemetryIngestResponse: schema("ClientTelemetryIngestResponse", clientTelemetryIngestResponseSchema),
      TelemetryEventsResponse: schema("TelemetryEventsResponse", telemetryEventsResponseSchema),
      TelemetryTraceResponse: schema("TelemetryTraceResponse", telemetryTraceResponseSchema),
      TelemetryOverviewResponse: schema("TelemetryOverviewResponse", telemetryOverviewResponseSchema),
      TelemetryLlmRunsResponse: schema("TelemetryLlmRunsResponse", telemetryLlmRunsResponseSchema),
      TelemetryFoodSearchResponse: schema("TelemetryFoodSearchResponse", telemetryFoodSearchResponseSchema),
      AdminAgentConversationsResponse: schema("AdminAgentConversationsResponse", adminAgentConversationsResponseSchema),
      AdminAgentConversationDetailResponse: schema("AdminAgentConversationDetailResponse", adminAgentConversationDetailResponseSchema),
      AdminActionCallsResponse: schema("AdminActionCallsResponse", adminActionCallsResponseSchema),
      AdminAgentTurnsResponse: schema("AdminAgentTurnsResponse", adminAgentTurnsResponseSchema),
      AdminAgentToolCallsResponse: schema("AdminAgentToolCallsResponse", adminAgentToolCallsResponseSchema),
      AdminLlmProviderCallsResponse: schema("AdminLlmProviderCallsResponse", adminLlmProviderCallsResponseSchema),
      AdminLlmCostResponse: schema("AdminLlmCostResponse", adminLlmCostResponseSchema),
      AdminTranscriptionsResponse: schema("AdminTranscriptionsResponse", adminTranscriptionsResponseSchema),
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
          "200": { description: "Request accepted", content: { "application/json": { schema: { $ref: "#/components/schemas/AuthRequestAcceptedResponse" } } } },
          "429": rateLimitResponse
        }
      }
    },
    "/v1/auth/email/confirm": {
      post: {
        operationId: "confirmEmail",
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/EmailConfirmationRequest" } } }
        },
        responses: {
          "200": { description: "Token pair", content: { "application/json": { schema: { $ref: "#/components/schemas/TokenPair" } } } },
          "429": rateLimitResponse
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
          "200": { description: "Token pair", content: { "application/json": { schema: { $ref: "#/components/schemas/TokenPair" } } } },
          "429": rateLimitResponse
        }
      }
    },
    "/v1/auth/password-reset/request": {
      post: {
        operationId: "requestPasswordReset",
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/PasswordResetRequest" } } }
        },
        responses: {
          "200": { description: "Request accepted", content: { "application/json": { schema: { $ref: "#/components/schemas/AuthRequestAcceptedResponse" } } } },
          "429": rateLimitResponse
        }
      }
    },
    "/v1/auth/password-reset/confirm": {
      post: {
        operationId: "confirmPasswordReset",
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/PasswordResetConfirm" } } }
        },
        responses: {
          "200": { description: "Password reset result" },
          "429": rateLimitResponse
        }
      }
    },
    "/v1/admin/auth/login": {
      post: {
        operationId: "adminLogin",
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/AdminLoginRequest" } } }
        },
        responses: {
          "200": { description: "Admin token", content: { "application/json": { schema: { $ref: "#/components/schemas/AdminTokenResponse" } } } },
          "429": rateLimitResponse
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
          "200": { description: "Token pair", content: { "application/json": { schema: { $ref: "#/components/schemas/TokenPair" } } } },
          "429": rateLimitResponse
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
          "200": { description: "Action result", content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionResponse" } } } },
          "429": rateLimitResponse
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
    "/v1/usual-foods": {
      get: {
        operationId: "getUsualFoods",
        security: [{ bearerAuth: [] }],
        responses: {
          "200": { description: "Usual foods action result", content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionResponse" } } } }
        }
      },
      post: {
        operationId: "createUsualFood",
        security: [{ bearerAuth: [] }],
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/CreateUsualFoodRequest" } } }
        },
        responses: {
          "200": { description: "Usual food action result", content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionResponse" } } } }
        }
      }
    },
    "/v1/usual-foods/draft": {
      post: {
        operationId: "draftUsualFood",
        security: [{ bearerAuth: [] }],
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/UsualFoodDraftRequest" } } }
        },
        responses: {
          "200": { description: "Review-only usual food draft", content: { "application/json": { schema: { $ref: "#/components/schemas/UsualFoodDraftResponse" } } } },
          "429": rateLimitResponse
        }
      }
    },
    "/v1/usual-foods/{usualFoodId}": {
      put: {
        operationId: "updateUsualFood",
        security: [{ bearerAuth: [] }],
        parameters: [{ name: "usualFoodId", in: "path", required: true, schema: { type: "string", format: "uuid" } }],
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/UpdateUsualFoodRequest" } } }
        },
        responses: {
          "200": { description: "Usual food action result", content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionResponse" } } } }
        }
      },
      delete: {
        operationId: "deleteUsualFood",
        security: [{ bearerAuth: [] }],
        parameters: [{ name: "usualFoodId", in: "path", required: true, schema: { type: "string", format: "uuid" } }],
        responses: {
          "200": { description: "Usual food delete action result", content: { "application/json": { schema: { $ref: "#/components/schemas/ExecuteActionResponse" } } } }
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
          "200": { description: "Agent result", content: { "application/json": { schema: { $ref: "#/components/schemas/AgentRunResponse" } } } },
          "429": rateLimitResponse
        }
      }
    },
    "/v1/agent/chat": {
      post: {
        operationId: "chatWithAgent",
        security: [{ bearerAuth: [] }],
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/AgentChatRequest" } } }
        },
        responses: {
          "200": {
            description: "Agent chat event stream",
            content: { "text/event-stream": { schema: { type: "string" } } }
          },
          "429": rateLimitResponse
        }
      }
    },
    "/v1/agent/chat/audio": {
      post: {
        operationId: "chatWithAgentAudio",
        security: [{ bearerAuth: [] }],
        requestBody: {
          required: true,
          content: {
            "multipart/form-data": {
              schema: {
                type: "object",
                properties: {
                  audio: { type: "string", format: "binary" },
                  source: { type: "string" },
                  conversationId: { type: "string", format: "uuid" },
                  activeProposalId: { type: "string", format: "uuid" }
                },
                required: ["audio"]
              }
            }
          }
        },
        responses: {
          "200": {
            description: "Transcription and agent chat event stream",
            content: { "text/event-stream": { schema: { type: "string" } } }
          },
          "429": rateLimitResponse
        }
      }
    },
    "/v1/agent/conversations/{conversationId}/meal-proposals/{proposalId}/commit": {
      post: {
        operationId: "commitAgentChatProposal",
        security: [{ bearerAuth: [] }],
        parameters: [
          { name: "conversationId", in: "path", required: true, schema: { type: "string", format: "uuid" } },
          { name: "proposalId", in: "path", required: true, schema: { type: "string", format: "uuid" } }
        ],
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/CommitAgentChatProposalRequest" } } }
        },
        responses: {
          "200": jsonResponse("Direct meal proposal commit", "#/components/schemas/CommitAgentChatProposalResponse")
        }
      }
    },
    "/v1/agent/conversations": {
      get: {
        operationId: "listAgentConversations",
        security: [{ bearerAuth: [] }],
        responses: {
          "200": jsonResponse("Agent conversations", "#/components/schemas/AgentConversationsResponse")
        }
      }
    },
    "/v1/agent/conversations/{id}": {
      get: {
        operationId: "getAgentConversation",
        security: [{ bearerAuth: [] }],
        parameters: [{ name: "id", in: "path", required: true, schema: { type: "string", format: "uuid" } }],
        responses: {
          "200": jsonResponse("Agent conversation detail", "#/components/schemas/AgentConversationDetailResponse")
        }
      },
      delete: {
        operationId: "deleteAgentConversation",
        security: [{ bearerAuth: [] }],
        parameters: [{ name: "id", in: "path", required: true, schema: { type: "string", format: "uuid" } }],
        responses: {
          "202": jsonResponse("Agent conversation deletion accepted", "#/components/schemas/DeleteAgentConversationResponse")
        }
      }
    },
    "/v1/agent/conversations/{id}/deletion": {
      get: {
        operationId: "getAgentConversationDeletion",
        security: [{ bearerAuth: [] }],
        parameters: [{ name: "id", in: "path", required: true, schema: { type: "string", format: "uuid" } }],
        responses: {
          "200": jsonResponse("Agent conversation deletion status", "#/components/schemas/DeleteAgentConversationResponse")
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
          "200": { description: "Transcript", content: { "application/json": { schema: { $ref: "#/components/schemas/TranscriptionResponse" } } } },
          "429": rateLimitResponse
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
          "200": { description: "Transcript and meal agent result", content: { "application/json": { schema: { $ref: "#/components/schemas/VoiceMealRunResponse" } } } },
          "429": rateLimitResponse
        }
      }
    },
    "/v1/telemetry/client-events": {
      post: {
        operationId: "ingestClientTelemetryEvents",
        security: [{ bearerAuth: [] }],
        requestBody: {
          required: true,
          content: jsonContent("#/components/schemas/ClientTelemetryIngestRequest")
        },
        responses: {
          "200": jsonResponse("Accepted client telemetry events", "#/components/schemas/ClientTelemetryIngestResponse")
        }
      }
    },
    "/v1/admin/telemetry/overview": {
      get: {
        operationId: "getAdminTelemetryOverview",
        security: [{ bearerAuth: [] }],
        parameters: [
          queryParameter("from", { type: "string", format: "date-time" }),
          queryParameter("to", { type: "string", format: "date-time" })
        ],
        responses: {
          "200": jsonResponse("Telemetry overview", "#/components/schemas/TelemetryOverviewResponse")
        }
      }
    },
    "/v1/admin/telemetry/events": {
      get: {
        operationId: "listAdminTelemetryEvents",
        security: [{ bearerAuth: [] }],
        parameters: [
          ...telemetryCommonQueryParameters,
          queryParameter("severity", { type: "string", enum: ["info", "warning", "error"] }),
          queryParameter("eventType", { type: "string", maxLength: 120 }),
          queryParameter("surface", { type: "string", enum: ["backend", "mobile", "agent", "stt", "db", "admin"] })
        ],
        responses: {
          "200": jsonResponse("Telemetry events", "#/components/schemas/TelemetryEventsResponse")
        }
      }
    },
    "/v1/admin/telemetry/llm-runs": {
      get: {
        operationId: "listAdminTelemetryLlmRuns",
        security: [{ bearerAuth: [] }],
        parameters: [
          ...telemetryCommonQueryParameters,
          queryParameter("conversationId", { type: "string", format: "uuid" }),
          queryParameter("turnId", { type: "string", format: "uuid" }),
          queryParameter("resultKind", { type: "string", maxLength: 80 }),
          queryParameter("selectedTool", { type: "string", maxLength: 80 }),
          queryParameter("executedTool", { type: "string", maxLength: 80 })
        ],
        responses: {
          "200": jsonResponse("LLM telemetry runs", "#/components/schemas/TelemetryLlmRunsResponse")
        }
      }
    },
    "/v1/admin/telemetry/conversations": {
      get: {
        operationId: "listAdminTelemetryConversations",
        security: [{ bearerAuth: [] }],
        parameters: [
          ...telemetryCommonQueryParameters,
          queryParameter("conversationId", { type: "string", format: "uuid" }),
          queryParameter("turnId", { type: "string", format: "uuid" }),
          queryParameter("includeHidden", { type: "string", enum: ["true", "false"] })
        ],
        responses: {
          "200": jsonResponse("Admin agent conversations", "#/components/schemas/AdminAgentConversationsResponse")
        }
      }
    },
    "/v1/admin/telemetry/conversations/{conversationId}": {
      get: {
        operationId: "getAdminTelemetryConversation",
        security: [{ bearerAuth: [] }],
        parameters: [
          { name: "conversationId", in: "path", required: true, schema: { type: "string", format: "uuid" } },
          queryParameter("includeHidden", { type: "string", enum: ["true", "false"] })
        ],
        responses: {
          "200": jsonResponse("Admin agent conversation detail", "#/components/schemas/AdminAgentConversationDetailResponse")
        }
      }
    },
    "/v1/admin/telemetry/action-calls": {
      get: {
        operationId: "listAdminTelemetryActionCalls",
        security: [{ bearerAuth: [] }],
        parameters: [
          ...telemetryCommonQueryParameters,
          queryParameter("actionId", { type: "string", maxLength: 120 })
        ],
        responses: {
          "200": jsonResponse("Admin action calls", "#/components/schemas/AdminActionCallsResponse")
        }
      }
    },
    "/v1/admin/telemetry/agent-turns": {
      get: {
        operationId: "listAdminTelemetryAgentTurns",
        security: [{ bearerAuth: [] }],
        parameters: [
          ...telemetryCommonQueryParameters,
          queryParameter("conversationId", { type: "string", format: "uuid" }),
          queryParameter("turnId", { type: "string", format: "uuid" }),
          queryParameter("inputMode", { type: "string", maxLength: 40 }),
          queryParameter("status", { type: "string", maxLength: 40 })
        ],
        responses: {
          "200": jsonResponse("Admin agent turns", "#/components/schemas/AdminAgentTurnsResponse")
        }
      }
    },
    "/v1/admin/telemetry/agent-tool-calls": {
      get: {
        operationId: "listAdminTelemetryAgentToolCalls",
        security: [{ bearerAuth: [] }],
        parameters: [
          ...telemetryCommonQueryParameters,
          queryParameter("conversationId", { type: "string", format: "uuid" }),
          queryParameter("turnId", { type: "string", format: "uuid" }),
          queryParameter("actionId", { type: "string", maxLength: 120 }),
          queryParameter("status", { type: "string", maxLength: 40 })
        ],
        responses: {
          "200": jsonResponse("Admin agent tool calls", "#/components/schemas/AdminAgentToolCallsResponse")
        }
      }
    },
    "/v1/admin/telemetry/llm-provider-calls": {
      get: {
        operationId: "listAdminTelemetryLlmProviderCalls",
        security: [{ bearerAuth: [] }],
        parameters: [
          ...telemetryCommonQueryParameters,
          queryParameter("conversationId", { type: "string", format: "uuid" }),
          queryParameter("turnId", { type: "string", format: "uuid" }),
          queryParameter("provider", { type: "string", maxLength: 120 }),
          queryParameter("model", { type: "string", maxLength: 160 }),
          queryParameter("status", { type: "string", maxLength: 40 }),
          queryParameter("costSource", { type: "string", maxLength: 40 })
        ],
        responses: {
          "200": jsonResponse("Admin LLM provider calls", "#/components/schemas/AdminLlmProviderCallsResponse")
        }
      }
    },
    "/v1/admin/telemetry/llm-cost": {
      get: {
        operationId: "getAdminTelemetryLlmCost",
        security: [{ bearerAuth: [] }],
        parameters: [
          queryParameter("from", { type: "string", format: "date-time" }),
          queryParameter("to", { type: "string", format: "date-time" }),
          queryParameter("userId", { type: "string", format: "uuid" }),
          queryParameter("conversationId", { type: "string", format: "uuid" }),
          queryParameter("traceId", { type: "string", maxLength: 120 })
        ],
        responses: {
          "200": jsonResponse("Admin LLM cost overview", "#/components/schemas/AdminLlmCostResponse")
        }
      }
    },
    "/v1/admin/telemetry/transcriptions": {
      get: {
        operationId: "listAdminTelemetryTranscriptions",
        security: [{ bearerAuth: [] }],
        parameters: [
          ...telemetryCommonQueryParameters,
          queryParameter("conversationId", { type: "string", format: "uuid" }),
          queryParameter("turnId", { type: "string", format: "uuid" }),
          queryParameter("surface", { type: "string", maxLength: 80 }),
          queryParameter("status", { type: "string", maxLength: 40 })
        ],
        responses: {
          "200": jsonResponse("Admin transcriptions", "#/components/schemas/AdminTranscriptionsResponse")
        }
      }
    },
    "/v1/admin/telemetry/food-search": {
      get: {
        operationId: "listAdminTelemetryFoodSearchEvents",
        security: [{ bearerAuth: [] }],
        parameters: [
          ...telemetryCommonQueryParameters,
          queryParameter("zeroResults", { type: "string", enum: ["true", "false"] }),
          queryParameter("lowConfidence", { type: "string", enum: ["true", "false"] }),
          queryParameter("path", { type: "string", maxLength: 80 })
        ],
        responses: {
          "200": jsonResponse("Food search telemetry events", "#/components/schemas/TelemetryFoodSearchResponse")
        }
      }
    },
    "/v1/admin/telemetry/traces/{traceId}": {
      get: {
        operationId: "getAdminTelemetryTrace",
        security: [{ bearerAuth: [] }],
        parameters: [
          { name: "traceId", in: "path", required: true, schema: { type: "string", maxLength: 120 } }
        ],
        responses: {
          "200": jsonResponse("Telemetry trace detail", "#/components/schemas/TelemetryTraceResponse")
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
    "/v1/meal-templates/draft": {
      post: {
        operationId: "draftUsualMeal",
        security: [{ bearerAuth: [] }],
        requestBody: {
          required: true,
          content: { "application/json": { schema: { $ref: "#/components/schemas/UsualMealDraftRequest" } } }
        },
        responses: {
          "200": { description: "Review-only usual meal draft", content: { "application/json": { schema: { $ref: "#/components/schemas/UsualMealDraftResponse" } } } },
          "429": rateLimitResponse
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
