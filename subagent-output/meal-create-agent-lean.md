# Meal create / agent chat lean UI cleanup

Implemented scoped AMOLED cleanup in meal create, voice/LLM states, and agent chat.

## Changed files

- `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart`
- `apps/mobile/lib/ui/features/agent_chat/views/agent_chat_screen.dart`
- `apps/mobile/test/voice_log_screen_test.dart`
- `specs/meal-create-agent-implementation-report.md`

## Validation

- `cd apps/mobile && flutter pub get` — passed.
- `cd apps/mobile && flutter analyze --no-pub` — ran; failed only on pre-existing unrelated `lib/app/theme.dart:244:23 prefer_const_constructors` info.
- `cd apps/mobile && flutter test --no-pub test/voice_log_screen_test.dart test/agent_chat_test.dart` — passed (`+19 ~5`).
- `git diff --check` — passed.
- `graphify update .` — ran after edits.

## Notes

No backend, Settings, History, saved editors, food parsing, ingredient inference, LLM/STT behavior, or API/cache logic was changed.
