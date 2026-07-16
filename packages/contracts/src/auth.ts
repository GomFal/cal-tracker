import { z } from "zod";
import { isoDateTimeSchema, uuidSchema } from "./common.js";

export const registerRequestSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  displayName: z.string().min(1).max(120)
});

export const registrationPendingResponseSchema = z.object({
  ok: z.literal(true),
  email: z.string().email()
});

export const loginRequestSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1)
});

export const adminLoginRequestSchema = z.object({
  username: z.string().min(1).max(120),
  password: z.string().min(1).max(512)
});

export const googleLoginRequestSchema = z.object({
  idToken: z.string().min(1)
});

export const emailConfirmationRequestSchema = z.object({
  token: z.string().min(32)
});

export const refreshRequestSchema = z.object({
  refreshToken: z.string().min(32)
});

export const logoutRequestSchema = z.object({
  refreshToken: z.string().min(32).optional()
});

export const passwordResetRequestSchema = z.object({
  email: z.string().email()
});

export const passwordResetConfirmSchema = z.object({
  token: z.string().min(32),
  newPassword: z.string().min(8)
});

export const authUserSchema = z.object({
  id: uuidSchema,
  email: z.string().email(),
  displayName: z.string(),
  trustedModeEnabled: z.boolean(),
  emailVerifiedAt: isoDateTimeSchema.nullable().optional(),
  createdAt: isoDateTimeSchema
});

export const tokenPairSchema = z.object({
  accessToken: z.string(),
  refreshToken: z.string(),
  expiresAt: isoDateTimeSchema,
  user: authUserSchema
});

export const adminTokenResponseSchema = z.object({
  accessToken: z.string(),
  expiresAt: isoDateTimeSchema,
  tokenType: z.literal("Bearer"),
  scope: z.string(),
  username: z.string()
});

export type RegisterRequest = z.infer<typeof registerRequestSchema>;
export type RegistrationPendingResponse = z.infer<typeof registrationPendingResponseSchema>;
export type LoginRequest = z.infer<typeof loginRequestSchema>;
export type AdminLoginRequest = z.infer<typeof adminLoginRequestSchema>;
export type AdminTokenResponse = z.infer<typeof adminTokenResponseSchema>;
export type GoogleLoginRequest = z.infer<typeof googleLoginRequestSchema>;
export type EmailConfirmationRequest = z.infer<typeof emailConfirmationRequestSchema>;
export type TokenPair = z.infer<typeof tokenPairSchema>;
export type AuthUser = z.infer<typeof authUserSchema>;
