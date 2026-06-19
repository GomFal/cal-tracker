---
title: Flutter Accessibility, Responsive, I18n, and Design-System Cleanup Plan
version: 1.0
date_created: 2026-06-18
last_updated: 2026-06-18
owner: Mobile engineering
tags: [design, flutter, accessibility, responsive, i18n]
---

# Introduction

This specification defines UI robustness work for accessibility, responsive layout, localization, empty/error states, and design-system consistency.

## 1. Purpose & Scope

The scope includes custom Flutter controls and dense screens identified by the audit: dashboard cards, app shell navigation/mic, usual food scan overlays, calorie calculator ruler, meal label sheet, and localized macro labels.

## 2. Definitions

- **Semantics**: Flutter accessibility metadata exposed to screen readers and tests.
- **Text scale**: User accessibility setting that increases text size.
- **ARB**: Flutter localization resource files for English and Spanish.

## 3. Requirements, Constraints & Guidelines

- **REQ-001**: Custom interactive controls must expose meaningful semantics labels, roles/states, and actions.
- **REQ-002**: Canvas-painted text must have equivalent semantics or non-canvas accessible alternatives.
- **REQ-003**: Dense sheets/cards must tolerate small viewport, keyboard, Spanish strings, and high text scale.
- **REQ-004**: User-visible strings must be in ARB files.
- **REQ-005**: Raw colors used repeatedly must move to semantic design tokens.
- **CON-001**: Do not replace automated widget tests with visual/manual validation only.

## 4. Interfaces & Data Contracts

### Files to touch

Accessibility/responsive:

- `apps/mobile/lib/ui/features/meal_templates/views/usual_food_scan_screen.dart`
- `apps/mobile/lib/ui/features/meal_templates/views/scan_viewfinder_overlay.dart`
- `apps/mobile/lib/ui/features/dashboard/views/calorie_target_sheet.dart`
- `apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart`
- `apps/mobile/lib/ui/features/voice_log/views/voice_log_screen.dart`
- `apps/mobile/lib/ui/core/app_shell.dart`

I18n:

- `apps/mobile/lib/l10n/app_en.arb`
- `apps/mobile/lib/l10n/app_es.arb`
- generated localization output after running Flutter l10n generation.
- `apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart`
- `apps/mobile/lib/ui/core/user_visible_error.dart` if strings are moved.

Design system:

- `apps/mobile/lib/ui/core/design_system.dart`
- `apps/mobile/test/dark_mode_static_audit_test.dart`
- `apps/mobile/lib/ui/features/dashboard/views/dashboard_screen.dart`

Tests:

- `apps/mobile/test/bottom_mic_bubble_widget_test.dart`
- `apps/mobile/test/dashboard_cleanup_widget_test.dart`
- `apps/mobile/test/macro_distribution_test.dart`
- `apps/mobile/test/calorie_calculator_wizard_test.dart`
- `apps/mobile/test/features/meal_templates/usual_food_scan_screen_test.dart`
- New or updated semantics/responsive tests.

### Specific fixes

1. Add semantics to OCR selector in `usual_food_scan_screen.dart`.
2. Add semantics or accessible alternative labels for `scan_viewfinder_overlay.dart` canvas text.
3. Add semantics actions/value to sliding ruler in `calorie_target_sheet.dart`.
4. Add selected-state semantics to nav buttons in `app_shell.dart`.
5. Fix dashboard no-data error state so default values are not presented as real loaded data.
6. Wrap `_MealLabelSheet` content for keyboard/small viewport safety.
7. Replace hardcoded macro labels in `dashboard_screen.dart` with ARB strings.
8. Move water-card colors/tokens into `FreshPalette` or semantic design-system properties.
9. Expand dark-mode static audit to catch raw `Color(0x...)` usage with allowlist.

## 5. Acceptance Criteria

- **AC-001**: Important custom controls are discoverable with semantics tests.
- **AC-002**: Dashboard shows a dedicated error/empty state when no summary/cache exists after load failure.
- **AC-003**: Voice meal label sheet does not overflow with keyboard and custom label field.
- **AC-004**: Macro labels use localization resources, not locale-name branching.
- **AC-005**: Dark/light repeated colors move into semantic tokens or are explicitly allowlisted.

## 6. Test Automation Strategy

Run:

```bash
cd apps/mobile
flutter analyze
flutter test test/bottom_mic_bubble_widget_test.dart
flutter test test/dashboard_cleanup_widget_test.dart
flutter test test/calorie_calculator_wizard_test.dart test/macro_distribution_test.dart
flutter test test/features/meal_templates/usual_food_scan_screen_test.dart
```

If ARB files change, regenerate localization before validation.

## 7. Rationale & Context

These fixes reduce user-facing robustness issues and prevent visual/accessibility regressions while large files are being split.

## 8. Dependencies & External Integrations

- Flutter localization generation.
- Existing design system and theme extension.
- No backend dependency.

## 9. Examples & Edge Cases

- Spanish macro labels on Dashboard.
- Large text scale on daily progress card.
- Keyboard visible while adding custom meal label.
- Screen reader increments/decrements calorie ruler.

## 10. Validation Criteria

This spec is complete when focused tests pass and no new accessibility/layout warnings are introduced.

## 11. Related Specifications / Further Reading

- `review/flutter-ui-i18n-a11y.md`
- `review2/flutter-ui-i18n-a11y.md`
- `spec-architecture-voice-log-decomposition.md`

