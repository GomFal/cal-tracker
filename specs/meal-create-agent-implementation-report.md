# Meal create / voice / agent chat UI cleanup implementation report

## Scope

Implemented the AMOLED cleanup requested by `specs/card-audit-meal-create-voice-agent.md` in this worktree only. Edits were limited to:

- `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart`
- `apps/mobile/lib/ui/features/agent_chat/views/agent_chat_screen.dart`
- `apps/mobile/test/voice_log_screen_test.dart`

No backend, Settings, History, saved editors, LLM/STT parsing, or food inference logic was changed.

## What changed

- Removed the remaining `FreshCard` wrappers from meal create / voice-log content and replaced them with open AMOLED sections, typography-first metric summaries, inline transcript/status treatment, and rule-separated rows.
- Flattened manual food search, selected draft ingredients, proposal review, clarification candidates, summary/remaining/results, and proposal editor ingredient rows.
- Converted proposal calories and agent-result metrics from filled blocks/pills to colored text metrics.
- Reduced agent chat panel weight by flattening the welcome state, user/assistant messages, tool-call timeline items, draft headers, and input bar actions.
- Preserved existing widget keys and user-flow behavior where practical; updated one widget test expectation for the proposal item split into name and quantity columns.

## Validation

- `cd apps/mobile && flutter pub get` completed successfully to restore package resolution for this worktree.
- `cd apps/mobile && flutter analyze --no-pub` ran and reported one pre-existing unrelated info in `lib/app/theme.dart:244:23` (`prefer_const_constructors`). No new issues were reported in edited files.
- `cd apps/mobile && flutter test --no-pub test/voice_log_screen_test.dart test/agent_chat_test.dart` passed: `+19 ~5`, all tests passed.
- `git diff --check` passed.
- `graphify update .` was run after source changes; it completed without leaving graph changes.

## Residual risks

- Visual validation on a running emulator/Marionette was not performed in this pass.
- Full `flutter analyze --no-pub` still exits non-zero because of the unrelated existing `lib/app/theme.dart` info.
