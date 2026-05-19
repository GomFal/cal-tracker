# BetterCalories macro configuration feature specification

## 1. Product goal

Add an optional macro configuration flow after the user sets and saves their daily calories.

The feature should let users decide whether they want to track macronutrients without making onboarding feel heavier.

Core principle:

```txt
Calories define the daily budget.
Macros define the preferred distribution.
Protein is treated as the priority target.
Carbs/fats provide flexibility.
The app explains mismatches without creating anxiety.
```

The app should **not** force exact equality between calories and macro-derived calories. Small differences are normal because food labels, nutrition databases, fiber, rounding, and serving sizes are imperfect.

---

## 2. Final UX decision

Use this final flow:

```txt
User sets daily calories
↓
User presses Save
↓
Calories are saved successfully
↓
Mini bottom sheet appears:
“Want to track protein, carbs and fats too?”
↓
User chooses:
A. Set macro distribution
B. Not now / dismiss
```

This is the chosen flow because it solves the macro baseline problem cleanly:

```txt
Macros are always calculated from the saved calorie target.
```

Do **not** let the user configure macros before saving calories. Macro setup should never depend on an unsaved temporary calorie value.

---

## 3. Entry points

### 3.1 First onboarding entry point

Current calorie setup screen:

```txt
Set your daily calories
Choose the target you want to track each day.

[-] 2200 Kcal [+]

Don't know how many calories you need?

[Save]
```

The calorie setup screen should remain focused on only one task:

```txt
Confirm the user's daily calorie target.
```

Do **not** add a visible macro configuration button before Save.

Do **not** add a visible “Skip for now” button to the calorie screen.

The existing **Save** button is the exit/confirmation button from this screen.

### 3.2 Post-save macro prompt

After the user taps **Save**, the app must first persist the selected calorie value.

Only after the calorie target is saved successfully should the app show a mini bottom sheet.

Recommended copy:

```txt
Calories saved

Your daily target is 2200 kcal.

Want to track protein, carbs and fats too?

Macros help you distribute your daily calories.

[Set macro distribution]

Not now
```

The bottom sheet should be dismissible through:

```txt
Not now

```

The explicit **Not now** option is acceptable here because the calorie value has already been saved and the user is now being offered an optional advanced setup. It should not appear on the calorie setup screen itself.

### 3.3 Later menu entry point

Users who skip macros during onboarding should be able to configure them later from:

```txt
Menu → Macro distribution
```

---

## 4. Main flow

### Step 1 — User sets calories

User lands on:

```txt
Set your daily calories
```

Available actions:

```txt
A. Manually set calories using [-] and [+]
B. Tap “Don't know how many calories you need?” and complete the calorie wizard
C. Tap Save
```

No macro configuration is available before Save.

### Step 2 — User taps Save

When the user taps **Save**, the app must save the selected calorie target first.

Implementation rule:

```txt
Couldn't save your calories. Please try again.
```

### Step 3 — Post-save macro prompt appears

After successful save:

```txt
Calories saved

Your daily target is 2200 kcal.

Want to track protein, carbs and fats too?

[Set macro distribution]

Not now
```

If user taps **Set macro distribution**, open the macro configuration modal using the saved calorie value.

If user taps **Not now** or dismisses the sheet, close the prompt and return to Home.

### Step 4 — Macro configuration modal opens

The macro modal always receives a confirmed calorie baseline:

```txt
Daily target: 2200 kcal
```

This value comes from persisted user settings, not from temporary UI state.

---

## 5. Macro configuration modal

### 5.1 Modal header

```txt
Set your macros
Choose how you want to distribute your daily calories.
```

Show the saved calorie target clearly:

```txt
Daily target: 2200 kcal
```

Helper text:

```txt
You can change this later from Menu.
```

### 5.2 Toggle: percentages vs grams

At the top of the modal, show a segmented control:

```txt
[ Percentages ] [ Grams ]
```

Default:

```txt
Percentages
```

Rationale:

Percentage mode is easier for normal users. Gram mode is for advanced users who already know their targets.

---

## 6. Percentage mode

### 6.1 Behavior

In percentage mode, calories are fixed and macros are derived.

Example:

```txt
Daily target: 2200 kcal

Protein 30% → 165 g
Carbs   40% → 220 g
Fats    30% → 73 g
```

Calculation:

```txt
protein_g = calories * protein_pct / 4
carbs_g   = calories * carbs_pct / 4
fat_g     = calories * fat_pct / 9
```

Percentages must add to:

```txt
100%
```

### 6.2 Preset cards

Instead of showing only static percentage cards, use the selected toggle to decide how the cards are displayed.

When toggle is **Percentages**, cards show percentages first:

```txt
Balanced
30% protein / 40% carbs / 30% fat
165g / 220g / 73g

High protein
35% protein / 35% carbs / 30% fat
193g / 193g / 73g

Lower carb
35% protein / 25% carbs / 40% fat
193g / 138g / 98g

Custom
Choose your own distribution
```

Recommended presets:

| Preset | Protein | Carbs | Fat | Use case |
|---|---:|---:|---:|---|
| Balanced | 30% | 40% | 30% | Default general-purpose target |
| High protein | 35% | 35% | 30% | Fat loss, recomposition, muscle retention |
| Lower carb | 35% | 25% | 40% | Users who prefer fewer carbs |
| Custom | User-defined | User-defined | User-defined | Advanced/manual preference |

### 6.3 Custom percentage mode

If user taps **Custom** while the toggle is set to **Percentages**, open custom percentage editing.

UI:

```txt
Custom macros

Protein
[ - ] 30% [ + ]

Carbs
[ - ] 40% [ + ]

Fats
[ - ] 30% [ + ]

Total: 100%
```

Below each macro, show derived grams:

```txt
Protein 30% → 165g
Carbs 40% → 220g
Fats 30% → 73g
```

### 6.4 Percentage editing logic

The user should never need to manually solve the 100% total.

Recommended behavior:

```txt
When one macro increases, another macro decreases automatically.
When one macro decreases, another macro increases automatically.
```

Default absorbing macro:

```txt
Carbs
```

Reason:

Protein is usually the highest-priority macro. Fat often has a minimum practical floor. Carbs are the most flexible.

Optional later enhancement:

```txt
Lock protein
Lock carbs
Lock fats
```

For MVP, avoid locks unless the UI still feels simple.

### 6.5 Validation in percentage mode

Hard rule:

```txt
Final percentages must equal 100%.
```

But the app should auto-balance rather than block the user.

Example:

```txt
User changes protein from 30% to 35%.

Before:
Protein 30%
Carbs 40%
Fats 30%

After:
Protein 35%
Carbs 35%
Fats 30%
```

No warning is needed in percentage mode because the app always derives grams from the calorie target.

---

## 7. Gram mode

### 7.1 Behavior

In gram mode, users define exact gram targets.

Example:

```txt
Daily target: 2200 kcal

Protein 170g
Carbs 230g
Fats 75g
```

The app calculates macro-derived calories:

```txt
protein_kcal = protein_g * 4
carbs_kcal   = carbs_g * 4
fat_kcal     = fat_g * 9
macro_kcal   = protein_kcal + carbs_kcal + fat_kcal
delta        = macro_kcal - daily_calorie_target
```

Example:

```txt
170g protein = 680 kcal
230g carbs = 920 kcal
75g fat = 675 kcal

Macro calories = 2275 kcal
Daily target = 2200 kcal
Difference = +75 kcal
```

### 7.2 Preset cards in gram mode

When toggle is **Grams**, the same preset cards are shown, but grams are the primary display.

For 2200 kcal:

```txt
Balanced
165g protein / 220g carbs / 73g fat
30% / 40% / 30%

High protein
193g protein / 193g carbs / 73g fat
35% / 35% / 30%

Lower carb
193g protein / 138g carbs / 98g fat
35% / 25% / 40%

Custom
Choose exact gram targets
```

Important: presets still originate from percentages, but they are displayed as grams because the user selected gram mode.

### 7.3 Custom gram mode

If user taps **Custom** while toggle is set to **Grams**, open exact gram editing.

UI:

```txt
Custom macros

Daily target: 2200 kcal

Protein
[ - ] 170 g [ + ]

Carbs
[ - ] 230 g [ + ]

Fats
[ - ] 75 g [ + ]

Macro calories: 2275 kcal
Difference: +75 kcal
```

Show helper text:

```txt
Small differences are normal because nutrition labels and databases round values.
```

---

## 8. Warning system for gram mode

Warnings only apply in **custom gram mode**.

### 8.1 Difference thresholds

Use absolute difference:

```txt
abs(macroCalories - dailyCalories)
```

#### Case A — 0 to 25 kcal difference

No warning.

Show neutral info only if desired:

```txt
Macro calories: 2190 kcal
Difference: -10 kcal
```

No red, no alert, no blocking.

#### Case B — 25 to 75 kcal difference

Show soft warning.

Example:

```txt
Your macro targets are 60 kcal below your daily calorie target.
Small differences are normal.
```

UI style:

```txt
Soft yellow/neutral info card
No aggressive icon
No blocking
```

Buttons:

```txt
Keep grams
Adjust carbs
```

#### Case C — More than 75 kcal difference

Show clear warning and offer auto-fix.

Required warning copy:

```txt
Your macro targets add up to 1,890 kcal, which is 110 kcal below your daily calorie target of 2,000 kcal.
```

Buttons:

```txt
Keep grams
Adjust carbs to match calories
Adjust fats to match calories
Recalculate percentages
```

### 8.2 Warning behavior

Do not prevent saving.

The user can always choose:

```txt
Keep grams
```

But for large mismatches, the app should clearly explain the mismatch and offer fast correction.

### 8.3 Auto-fix options

#### Option 1 — Keep grams

Saves the exact grams the user entered.

Use when:

```txt
User intentionally wants those exact macro targets.
```

Save:

```txt
mode = "grams"
proteinGrams = user value
carbsGrams = user value
fatGrams = user value
calorieDeltaKcal = calculated delta
```

#### Option 2 — Adjust carbs to match calories

Default recommended auto-fix.

Formula:

```txt
remaining_kcal = calories - protein_g*4 - fat_g*9
carbs_g = remaining_kcal / 4
```

If result is valid, update carbs.

Example:

```txt
Calories: 2000
Protein: 160g = 640 kcal
Fat: 70g = 630 kcal

Remaining: 730 kcal
Carbs: 183g
```

#### Option 3 — Adjust fats to match calories

Formula:

```txt
remaining_kcal = calories - protein_g*4 - carbs_g*4
fat_g = remaining_kcal / 9
```

Use when users prefer fixed carbs/protein.

#### Option 4 — Recalculate percentages

Convert entered grams into percentages based on macro calories.

Formula:

```txt
protein_pct = protein_kcal / macro_kcal
carbs_pct = carbs_kcal / macro_kcal
fat_pct = fat_kcal / macro_kcal
```

Then normalize to 100%.

This option is useful when the user likes the ratio they entered but wants the app to manage future changes based on percentages.

---

## 9. Saving behavior

### 9.1 If user selects a preset

Save both percentages and grams.

Example:

```ts
{
  caloriesKcal: 2200,
  mode: "percentage",
  selectedPreset: "balanced",
  proteinPct: 30,
  carbsPct: 40,
  fatPct: 30,
  proteinGrams: 165,
  carbsGrams: 220,
  fatGrams: 73
}
```

Even in gram toggle mode, if the card is a preset derived from percentages, you can save:

```ts
mode: "grams"
```

but keep the source:

```ts
source: "preset"
```

Recommended:

```ts
mode: "percentage"
```

for presets unless the user custom-edits grams.

Why: presets are ratio-based by nature. If calories change later, macro grams should update automatically.

### 9.2 If user uses custom percentages

Save:

```ts
mode = "percentage"
proteinPct
carbsPct
fatPct
```

Recalculate grams whenever calories change.

### 9.3 If user uses custom grams

Save:

```ts
mode = "grams"
proteinGrams
carbsGrams
fatGrams
```

If calories change later, show:

```txt
Your calorie target changed. Do you want to update your macro grams too?
```

Options:

```txt
Keep my gram targets
Recalculate grams from the same percentages
Adjust carbs to match new calories
```

---

## 10. Interaction with calorie changes

### 10.1 If mode is percentage

When calories change, macro grams update automatically.

Example:

```txt
Before:
Calories 2200
Protein 30% = 165g

After:
Calories 2000
Protein 30% = 150g
```

No warning needed.

### 10.2 If mode is grams

When calories change, grams should not silently change.

Show a small confirmation sheet:

```txt
Your calorie target changed
Your current macro grams add up to 2,180 kcal, but your new target is 2,000 kcal.

What do you want to do?
```

Actions:

```txt
Keep my macro grams
Adjust carbs to match calories
Adjust fats to match calories
Convert to percentages
```

Default recommended action:

```txt
Adjust carbs to match calories
```

---

## 11. Logged food vs target macros

Do not confuse **target mismatch** with **logged food mismatch**.

There are two different concepts.

### 11.1 Macro target setup

This is what the user defines:

```txt
I want 2200 kcal with 165g protein, 220g carbs, 73g fat.
```

Here, the app can warn if the target macros do not roughly match calories.

### 11.2 Daily food logging

This is what the user actually eats:

```txt
Logged today:
2050 kcal
160g protein
230g carbs
68g fat
```

Do **not** warn aggressively if logged food calories and logged food macros do not perfectly match.

Reason:

Food databases often have inconsistencies.

Show progress independently:

```txt
Calories: 2050 / 2200 kcal
Protein: 160 / 165g
Carbs: 230 / 220g
Fat: 68 / 73g
```

Macro-derived calories should not override logged calories.

---

## 12. UI copy

### 12.1 Calorie setup screen

```txt
Set your daily calories
Choose the target you want to track each day.
```

Main CTA:

```txt
Save
```

Do not add:

```txt
Skip for now
Set macro distribution
```

on this screen.

### 12.2 Post-save macro prompt

```txt
Calories saved

Your daily target is 2200 kcal.

Want to track protein, carbs and fats too?

Macros help you distribute your daily calories.

[Set macro distribution]

Not now
```

### 12.3 Macro modal title

```txt
Set your macros
```

Subtitle:

```txt
Choose how your daily calories are distributed.
```

### 12.4 Toggle labels

```txt
Percentages
Grams
```

### 12.5 Preset names

```txt
Balanced
High protein
Lower carb
Custom
```

### 12.6 Helper text

```txt
Calories stay as your main daily target. Macros help you distribute those calories.
```

For gram mode:

```txt
Small differences are normal because nutrition labels and databases round values.
```

### 12.7 Soft warning

```txt
Your macro targets are 60 kcal below your daily calorie target. Small differences are normal.
```

### 12.8 Clear warning

```txt
Your macro targets add up to 1,890 kcal, which is 110 kcal below your daily calorie target of 2,000 kcal.
```

Buttons:

```txt
Keep grams
Adjust carbs to match calories
Adjust fats to match calories
Recalculate percentages
```

---

## 13. Visual design direction

Use the visual language from the attached UI:

```txt
White background
Large rounded cards
Soft shadow
Green primary CTA
Minimal icons
Large readable numbers
Light gray helper text
Pill toggles
Bottom sheet/modal style
```

Avoid dense nutrition-dashboard feeling during onboarding.

The screen should feel like:

```txt
Simple setup → optional precision
```

not:

```txt
Spreadsheet nutrition calculator
```

### 13.1 Calorie setup screen structure

```txt
┌─────────────────────────────┐
│ Set your daily calories      │
│ Choose the target you want   │
│ to track each day.           │
│                              │
│    [-] 2200 Kcal [+]         │
│                              │
│ Don't know how many calories │
│ you need?                    │
│                              │
│ [Save]                       │
└─────────────────────────────┘
```

### 13.2 Post-save mini menu structure

```txt
┌─────────────────────────────┐
│ Calories saved               │
│                              │
│ 2200 kcal                    │
│                              │
│ Want to track protein,       │
│ carbs and fats too?          │
│                              │
│ Macros help you distribute   │
│ your daily calories.         │
│                              │
│ [Set macro distribution]     │
│                              │
│ Not now                      │
└─────────────────────────────┘
```

### 13.3 Macro modal structure

```txt
┌─────────────────────────────┐
│ Set your macros              │
│ Daily target: 2200 kcal      │
│                              │
│ [ Percentages | Grams ]      │
│                              │
│ Balanced                     │
│ 30% P / 40% C / 30% F        │
│ 165g / 220g / 73g            │
│                              │
│ High protein                 │
│ 35% P / 35% C / 30% F        │
│ 193g / 193g / 73g            │
│                              │
│ Lower carb                   │
│ 35% P / 25% C / 40% F        │
│ 193g / 138g / 98g            │
│                              │
│ Custom                       │
│ Choose your own targets      │
│                              │
│ [Save macros]                │
└─────────────────────────────┘
```

Do not include a visible **Skip for now** button inside the macro modal. Skipping occurs in the post-save mini prompt or by dismissing before entering macro configuration.

---

## 14. Recommended implementation rules

### 14.1 Constants

```ts
const KCAL_PER_GRAM = {
  protein: 4,
  carbs: 4,
  fat: 9,
};

const WARNING_SOFT_THRESHOLD_KCAL = 25;
const WARNING_CLEAR_THRESHOLD_KCAL = 75;
```

During onboarding, the user should not see macro setup until after the calorie target has been saved.

---

## 15. MVP scope

Build now:

```txt
Calorie setup screen remains focused on calorie selection.
User taps Save to confirm calories.
Calories are persisted before any macro setup appears.
Post-save mini bottom sheet asks whether the user wants to track protein, carbs and fats.
User can open macro setup or choose Not now.
Macro setup opens as bottom sheet/modal using the saved calorie target.
Segmented toggle: Percentages / Grams.
Preset cards: Balanced, High protein, Lower carb, Custom.
Percentage mode derives grams automatically.
Gram mode calculates macro calories and delta.
Warnings only appear from >25 kcal difference.
Clear warning appears from >75 kcal difference.
User can keep mismatched grams.
Auto-fix options: adjust carbs, adjust fats, recalculate percentages.
Skipped macros can be configured later from Menu.
```

Defer:

```txt
Macro locks
Net carbs vs total carbs
Keto-specific calculator
Exercise-calorie macro redistribution
Per-day macro cycling
Different macro targets for training/rest days
```

---

## 16. Intended user experience

The user first chooses:

```txt
How many calories do I want to target?
```

Then the user presses:

```txt
Save
```

The app saves the target and then asks, optionally:

```txt
Do you want to track protein, carbs and fats too?
```

If yes, the user can choose:

```txt
Simple: percentages
Advanced: grams
```

If no, the user continues into the app with calorie tracking only and can configure macros later from Menu.

The app helps users avoid mistakes, but does not punish normal imprecision.

That gives BetterCalories a clean onboarding experience while still supporting advanced nutrition users.

## 17. Add this last feature to extend the existing calorie wizard.

Add a simple macronutrient selection step at the end of the existing calorie wizard.

Context:
The calorie wizard is used by users who do not know how many calories they need. After the wizard calculates/recommends a daily calorie target, the user should also be offered a simple way to choose their macro distribution.

Requirement:
At the final step of the calorie wizard, after the daily calorie target has been calculated, add an optional macro distribution section.

This section should only offer the same three percentage-based macro presets that already exist in the macro configuration wizard:

1. Balanced
   - Protein: 30%
   - Carbs: 40%
   - Fat: 30%

2. High protein
   - Protein: 35%
   - Carbs: 35%
   - Fat: 30%

3. Lower carb
   - Protein: 35%
   - Carbs: 25%
   - Fat: 40%

Do not add grams mode here.
Do not add custom macro editing here.
Do not add calorie/macro mismatch warnings here.
This step should stay simple because the user using the calorie wizard is likely less advanced nutritionally.

Behavior:
- The wizard calculates the recommended daily calories as it already does.
- The macro preset cards use that calculated calorie target as their baseline.
- When the user selects a preset, derive the macro gram targets from the percentages:
  - proteinGrams = calories * proteinPct / 100 / 4
  - carbsGrams = calories * carbsPct / 100 / 4
  - fatGrams = calories * fatPct / 100 / 9
- Round grams to whole numbers for display and storage.
- Save the selected macro target as percentage-based, not gram-based.
- If the user does not select a macro preset, the wizard should still allow finishing with only the calorie target saved.

Suggested UI:
At the final wizard result screen, show:

Recommended daily calories
[calculatedCalories] kcal

Choose your macro distribution
Optional: you can change this later.

[Balanced]
30% protein / 40% carbs / 30% fat
[derived grams]

[High protein]
35% protein / 35% carbs / 30% fat
[derived grams]

[Lower carb]
35% protein / 25% carbs / 40% fat
[derived grams]

[Save]

Important UX rules:
- Calories remain the primary target.
- Macros are optional.
- This wizard only exposes simple percentage presets.
- Advanced macro configuration remains available in the dedicated macro configuration wizard/menu.
- Reuse the existing macro preset definitions/components if possible to avoid duplicated logic.
- Keep the visual style consistent with the current BetterCalories soft UI: rounded cards, clean white background, green primary CTA, simple text hierarchy.
