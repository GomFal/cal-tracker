# Voice Meal Tool Argument Validation Bug

## Summary

During local normalized-search testing, a voice meal proposal showed this mobile error:

```text
Something went wrong
Try a new recording and speak clearly after the recording starts.
```

The displayed message is misleading. The recording and STT step succeeded. The failure happened after transcription, when the agent generated invalid `propose_meal_log` tool arguments.

This issue is independent of normalized food search. In the failing run, the request never reached food search resolution.

## Observed Trace

Backend trace:

```text
traceId: 51fba2e2-9a16-4303-b2b9-7bb2a9b8ae01
transcript: "Añadez 100 gramos de arroz y 100 gramos de pollo."
selectedTool: "propose_meal_log"
```

The agent generated these mention fields:

```json
{
  "portionDescriptorRaw": "",
  "portionDescriptor": ""
}
```

The backend rejected them with a `ZodError` because both fields are optional, but if present they must be non-empty strings.

## Root Cause

The shared contract currently defines:

```ts
portionDescriptorRaw: z.string().min(1).optional(),
portionDescriptor: z.string().min(1).optional(),
```

Reference:

- `packages/contracts/src/common.ts`

That schema is correct in principle: empty strings should not be accepted as meaningful descriptors. The problem is that LLM tool output often includes optional fields as empty strings instead of omitting them.

The backend currently validates the model-generated tool arguments directly. Therefore, an otherwise valid food mention fails only because optional empty descriptor strings are present.

## Error Mapping Problem

The backend returns the `ZodError` as:

```json
{
  "error": {
    "code": "validation_error",
    "message": "Invalid request"
  }
}
```

Reference:

- `apps/backend/src/middleware/errors.ts`

The mobile app maps voice meal validation errors to:

```text
Try a new recording and speak clearly after the recording starts.
```

Reference:

- `apps/mobile/lib/ui/core/user_visible_error.dart`

That message is appropriate for invalid user input or failed transcription, but not for backend rejection of malformed agent tool arguments.

## Recommended Fix

Fix this backend-first so the app is robust against harmless LLM formatting noise.

Preferred fix:

1. Add a reusable string preprocessor in `packages/contracts/src/common.ts` that converts blank optional strings to `undefined`.
2. Apply it to optional user/model text fields where `""` has no semantic value, especially:

```ts
portionDescriptorRaw
portionDescriptor
brand
barcode
```

Example shape:

```ts
const optionalNonEmptyString = z.preprocess(
  (value) => typeof value === "string" && value.trim() === "" ? undefined : value,
  z.string().min(1).optional(),
);
```

Then use:

```ts
portionDescriptorRaw: optionalNonEmptyString,
portionDescriptor: optionalNonEmptyString,
```

Alternative fix:

- Sanitize model tool arguments in `apps/backend/src/agent/agentService.ts` before schema validation by recursively removing empty-string optional fields.

The contract-level fix is preferable because it protects all callers using the shared schema, not only the agent flow.

## Mobile Follow-up

After the backend is hardened, improve mobile error messaging so backend validation failures in voice meal flow do not blame the recording.

Suggested behavior:

- STT/audio validation error: keep the current recording-specific message.
- Agent/tool validation error: show a message like:

```text
We could not create the meal from that request. Try again or type it manually.
```

This should be handled near:

- `apps/mobile/lib/ui/core/user_visible_error.dart`

## Acceptance Test

Add backend tests covering this exact model output:

```json
{
  "text": "Añadez 100 gramos de arroz y 100 gramos de pollo",
  "mentions": [
    {
      "originalText": "100 gramos de arroz",
      "canonicalName": "arroz",
      "canonicalEnglishName": "rice",
      "language": "es",
      "quantity": 100,
      "unit": "g",
      "rawUnitText": "gramos",
      "unitKind": "metric",
      "portionDescriptorRaw": "",
      "portionDescriptor": "",
      "confidence": 0.95
    }
  ]
}
```

Expected result after fix:

- Empty descriptor strings are treated as absent.
- `propose_meal_log` validation succeeds.
- Food resolution executes.
- Voice meal response returns a proposal or a real clarification, not a generic recording error.

