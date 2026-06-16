---
title: Pastel Nutrient Text Styling for Food Editing
version: 1.0
date_created: 2026-05-30
owner: Cal Tracker
tags: [design, mobile, ui, nutrition]
---

# Introduction

This specification defines a small visual adjustment to the food editing experience: the text used for protein, carbohydrates, and fat should use a slightly more pastel tone. The intent is to soften the visual weight of these nutrient labels and values without reducing readability or changing any underlying data, layout, or interactions.

## 1. Purpose & Scope

This specification applies only to the user interface used when editing a food item.

In scope:

- the text for protein, carbohydrates, and fat in food edit forms or edit sheets
- the visual tone of those nutrient text elements
- accessibility and contrast requirements for those text elements

The target colors are fixed by macronutrient, but they must be slightly more pastel than fully saturated brand colors:

- Protein: `#D96A6A` or `#C95A5A`
- Carbohydrates: `#B88758` or `#C79C68`
- Fat: `#E8C65A` or `#E0B93B`

Out of scope:

- nutrition calculations
- data model changes
- label wording changes
- layout changes
- icon changes
- behavior changes in validation, saving, or navigation
- any broader theme or palette redesign

## 2. Definitions

- **Food editing UI**: Any screen, modal, sheet, or form where the user edits a food item and sees nutrition fields.
- **Pastel tone**: A visually softer color variant that remains clearly readable and does not materially reduce contrast against the background.
- **Nutrient text**: The label text or value text associated with protein, carbohydrates, and fat.

## 3. Requirements, Constraints & Guidelines

- **REQ-001**: The food editing UI must render protein, carbohydrates, and fat text in a slightly more pastel tone than the default body or label text used in the same screen.
- **REQ-002**: Protein text must use a softened red or garnet tone resolved from `#D96A6A` or `#C95A5A`.
- **REQ-003**: Carbohydrates text must use a softened brown or wheat tone resolved from `#B88758` or `#C79C68`.
- **REQ-004**: Fat text must use a softened yellow or gold tone resolved from `#E8C65A` or `#E0B93B`.
- **REQ-005**: The pastel styling must apply only to the nutrient text for protein, carbohydrates, and fat.
- **REQ-006**: The styling must not change the semantics, content, or ordering of the nutrient fields.
- **REQ-007**: The styling must preserve readability on light and dark themes.
- **REQ-008**: The styling must preserve accessibility contrast for normal-sized text.
- **REQ-009**: The styling must be visually subtle. It should soften emphasis without making the text look disabled, placeholder-like, or low contrast.
- **REQ-010**: The styling must be consistent across all edit states for a food item, including empty, populated, and validation-error states.

- **CON-001**: Do not change nutrient values, formatting, or labels as part of this design change.
- **CON-002**: Do not apply the pastel tone to unrelated fields, buttons, helper text, or navigation elements.
- **CON-003**: Do not use opacity alone if it causes the text to fall below acceptable contrast.
- **CON-004**: Do not introduce a new color family that conflicts with the existing design system.
- **CON-005**: Do not couple this change to food creation, meal templates, or other unrelated nutrition forms.
- **CON-006**: Do not replace the specified macronutrient colors with a generic single pastel token if that would erase the per-macronutrient color mapping.

- **GUD-001**: Prefer a restrained pastel shift derived from the existing design palette rather than an entirely new hue.
- **GUD-002**: Keep the visual hierarchy intact so the nutrient text remains readable as part of an editing form, not decorative text.

## 4. Interfaces & Data Contracts

This specification does not introduce new backend interfaces or API contracts.

Relevant UI contract:

| Element | Expected Behavior |
| --- | --- |
| Protein text | Uses a red/garnet pastel tone derived from `#D64545` or `#B83232` in the food edit UI |
| Carbohydrates text | Uses a brown/wheat pastel tone derived from `#A97443` or `#C89B5E` in the food edit UI |
| Fat text | Uses a yellow/gold pastel tone derived from `#F2C94C` or `#E6A700` in the food edit UI |
| Other nutrition fields | Remain unchanged unless explicitly added to scope later |

## 5. Acceptance Criteria

- **AC-001**: Given a user opens the food edit UI, when protein, carbohydrates, or fat text is displayed, then those text elements use the specified per-macronutrient color mapping.
- **AC-002**: Given the same screen, when the user reads or edits nutrient values, then the fields remain fully legible and the contrast remains acceptable.
- **AC-003**: Given a light theme or dark theme, when the edit UI is rendered, then the chosen color variant for each macronutrient remains visually coherent and does not break readability.
- **AC-004**: Given any other text in the screen, when the food edit UI is rendered, then the non-nutrient text is not recolored by this change.
- **AC-005**: Given validation errors or empty values in the food edit UI, when the nutrient section is shown, then the pastel styling does not obscure warnings or input affordances.

## 6. Test Automation Strategy

- Add or update a widget test for the food edit UI that verifies the nutrient text uses the intended color tokens or resolved text style.
- Add or update a golden test if the edit screen already has stable visual coverage and color regression risk is high.
- Verify light and dark theme rendering if the UI already supports both.
- Do not use backend tests for this change, because the behavior is purely presentational.

## 7. Rationale & Context

The food edit experience includes nutrient text that should remain informative but slightly less visually heavy than the rest of the form. A pastel tone can reduce visual tension without changing the meaning of the fields. The change is intentionally narrow so it does not alter the broader UI system or the nutrition editing workflow.

## 8. Dependencies & External Integrations

This specification has no external service dependencies.

### Infrastructure Dependencies

- **INF-001**: Existing mobile design system tokens must provide a safe color variant or a way to derive one without breaking accessibility.

### Data Dependencies

- **DAT-001**: The food edit UI must already expose protein, carbohydrates, and fat as distinct text elements or style targets.

## 9. Examples & Edge Cases

```text
Before:
- Protein: bold or high-emphasis body text
- Carbohydrates: default body text
- Fat: default body text

After:
- Protein: slightly pastel text
- Carbohydrates: slightly pastel text
- Fat: slightly pastel text
```

Edge cases:

- The pastel tone must still work if the nutrient row wraps onto multiple lines.
- The styling must not degrade readability when the screen is shown under reduced brightness or dark mode.
- If the design system cannot provide a safe pastel variant, the change should stop at the design/spec level rather than introducing an accessibility regression.

## 10. Validation Criteria

- Protein, carbohydrates, and fat text in the food edit UI use the specified color mapping.
- No other UI elements are recolored by this change.
- The food edit screen remains readable and accessible in supported themes.
- Widget or golden test coverage exists for the changed styling.

## 11. Related Specifications / Further Reading

- [Usual Foods and Usual Meals Flow Specification](../docs/spec-usual-foods-flow.md)
- [Application Specification and Architecture](../docs/app-description.md)
