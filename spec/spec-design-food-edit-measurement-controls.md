---
title: Flat Measurement Controls for Food Editing
version: 1.0
date_created: 2026-05-30
owner: Cal Tracker
tags: [design, mobile, ui, food-editing, nutrition]
---

# Introduction

This specification defines a visual and interaction refinement for the food editing view. The measurement controls should feel flatter, more centered, and more visually balanced. The current design uses too many card-like containers around quantity controls and suggested weights, which makes the area feel heavy and slightly misaligned.

The change is intentionally limited to the food editing measurement area. It does not change nutrition calculations, saved values, API contracts, or data models.

## 1. Purpose & Scope

This specification applies to the food editing UI section where the user can:

- select or change the measurement unit;
- increase the quantity by 10;
- decrease the quantity by 10;
- choose suggested gram or portion weights;
- review the current selected quantity.

In scope:

- visual treatment of measurement controls;
- horizontal and vertical alignment;
- spacing between controls;
- centering of suggested weight buttons;
- removing card-like containers from increment and decrement controls;
- keeping suggested weights as buttons or chips with a lighter, more balanced presentation.

Out of scope:

- changing the meaning of measurement units;
- changing quantity arithmetic;
- changing backend or repository behavior;
- changing nutrition recalculation logic;
- changing food search, usual foods, or meal template behavior;
- broad redesign of the whole food editing screen.

## 2. Definitions

- **Food editing view**: Any screen, bottom sheet, dialog, or form where a user edits an existing food item or a food item draft.
- **Measurement controls**: UI controls that change quantity, serving size, unit, or suggested weight.
- **Increment control**: A control that increases the selected quantity, especially the `+10` action.
- **Decrement control**: A control that decreases the selected quantity, especially the `-10` action.
- **Suggested weight**: A selectable preset value such as suggested grams, serving amounts, or common portion sizes.
- **Card-like container**: A visually framed block with border, elevation, background panel, or rounded container styling that makes a control look like an independent card.
- **Flat layout**: A layout that relies on alignment, spacing, typography, icons, and lightweight controls instead of stacked cards.

## 3. Requirements, Constraints & Guidelines

- **REQ-001**: The measurement controls in the food editing view must use a flatter visual treatment than the current card-heavy layout.
- **REQ-002**: The `+10` and `-10` controls must not be wrapped in card-like containers.
- **REQ-003**: The `+10` and `-10` controls must look like direct quantity actions, not separate cards.
- **REQ-004**: The measurement unit selector must remain easy to discover and use.
- **REQ-005**: Suggested gram or portion weights must remain selectable controls, such as buttons or chips.
- **REQ-006**: Suggested weight controls must be visually centered within their available horizontal space.
- **REQ-007**: Suggested weight controls must not appear stuck to the left edge of the section.
- **REQ-008**: Suggested weight controls must not be excessively flattened or compressed. They should still read as tappable controls.
- **REQ-009**: The measurement section must feel visually homogeneous with the rest of the food editing view.
- **REQ-010**: The measurement controls must preserve clear tap targets on mobile.
- **REQ-011**: The layout must remain stable when labels wrap, localized strings are longer, or several suggested weights are available.
- **REQ-012**: The visual hierarchy must make the current selected quantity and unit clear.

- **CON-001**: Do not use a card-like container around the `+10` and `-10` controls.
- **CON-002**: Do not add extra nested cards to solve alignment problems.
- **CON-003**: Do not left-align the suggested weight row if there is available horizontal space to center it.
- **CON-004**: Do not reduce suggested weight controls to plain text if that makes them look non-interactive.
- **CON-005**: Do not change quantity step behavior as part of this design-only task.
- **CON-006**: Do not change the default selected quantity or measurement unit as part of this task.
- **CON-007**: Do not introduce horizontal overflow on narrow mobile screens.

- **GUD-001**: Prefer a single flat measurement section using rows, wraps, segmented controls, chips, or icon buttons.
- **GUD-002**: Use spacing and alignment to create structure instead of borders, elevation, and card backgrounds.
- **GUD-003**: Suggested weights should use a balanced chip or button shape with enough padding to feel intentional.
- **GUD-004**: The selected suggested weight may use a stronger state treatment, but it should still match the flatter style.
- **GUD-005**: The design should look centered and intentional at both compact and wider mobile widths.

## 4. Interfaces & Data Contracts

This specification does not introduce new API contracts or backend behavior.

Relevant UI contract:

| Element | Expected Behavior |
| --- | --- |
| `-10` action | Flat direct action, no surrounding card-like container |
| `+10` action | Flat direct action, no surrounding card-like container |
| Measurement unit selector | Remains visible and editable |
| Suggested weight options | Remain tappable controls and are centered within the section |
| Current quantity display | Remains clear and visually dominant enough for editing |

## 5. Acceptance Criteria

- **AC-001**: Given the user opens the food editing view, when the measurement controls are displayed, then the `+10` and `-10` controls are not visually wrapped as cards.
- **AC-002**: Given the user opens the food editing view, when suggested weights are displayed, then the suggested weight controls are centered in their available space.
- **AC-003**: Given suggested weights are displayed, when the row wraps because of limited width, then the wrapped controls remain visually centered and evenly spaced.
- **AC-004**: Given the user taps `+10` or `-10`, when the quantity changes, then the behavior remains the same as before this visual change.
- **AC-005**: Given the user changes the measurement unit, when the selector is used, then existing measurement behavior remains unchanged.
- **AC-006**: Given a narrow mobile viewport, when the food editing view is rendered, then there is no horizontal overflow and no incoherent overlap.
- **AC-007**: Given light or dark theme rendering, when the measurement controls are shown, then the controls remain readable, tappable, and visually balanced.
- **AC-008**: Given localized Spanish or English labels, when labels are longer than expected, then the layout remains stable and the suggested weights do not drift awkwardly to the left.

## 6. Test Automation Strategy

- Add or update widget tests for the food editing view covering:
  - `+10` quantity action;
  - `-10` quantity action;
  - measurement unit selection;
  - suggested weight selection.
- Add a widget test or golden test that exercises a narrow mobile width and verifies no overflow exceptions occur.
- Prefer widget tests for behavior and layout stability.
- Use golden tests only if the food editing view already has stable visual baselines or if the visual risk is high.
- Do not add backend tests for this change because it is a UI presentation refinement.

## 7. Rationale & Context

The measurement area is an editing surface, not a content gallery. Heavy card styling around every small control makes the interaction feel fragmented and visually noisy. A flatter design should make the controls feel like one coherent editing tool while still keeping suggested weights discoverable and tappable.

The suggested weight controls specifically need alignment attention. If they sit too far to the left, the section looks accidental and less polished. Centering them improves visual balance without changing the workflow.

## 8. Dependencies & External Integrations

This specification has no external service dependencies.

### Platform Dependencies

- **PLT-001**: Flutter layout must support responsive wrapping, centering, and stable tap targets for the measurement controls.

### Design System Dependencies

- **DES-001**: The existing mobile design system should provide enough primitives for flat icon buttons, chips, segmented controls, or lightweight buttons without adding card containers.

## 9. Examples & Edge Cases

Preferred structure:

```text
Quantity row:
[-10]    [current quantity + unit selector]    [+10]

Suggested weights:
        [50 g]  [100 g]  [150 g]  [200 g]
```

The suggested weights may wrap, but the wrapped rows should still feel centered:

```text
Suggested weights:
          [50 g]  [100 g]  [150 g]
                [200 g]  [250 g]
```

Edge cases:

- Only one suggested weight is available.
- Many suggested weights are available and must wrap.
- Spanish labels are longer than English labels.
- The user changes from grams to another unit.
- The current quantity has three or four digits.
- The screen is rendered on a narrow mobile viewport.

## 10. Validation Criteria

- The food editing measurement section no longer looks card-heavy.
- The `+10` and `-10` controls are not inside card-like wrappers.
- Suggested weights remain visibly tappable but are centered and balanced.
- Measurement selection remains functional.
- Existing quantity behavior remains unchanged.
- No mobile overflow or overlapping text is introduced.

## 11. Related Specifications / Further Reading

- [Pastel Nutrient Text Styling for Food Editing](./spec-design-pastel-nutrition-macros-editing.md)
- [Usual Foods and Usual Meals Flow Specification](../docs/spec-usual-foods-flow.md)
