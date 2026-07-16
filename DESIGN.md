---
name: Better Calories
description: Mobile-first AMOLED nutrition tracker for fast, inspectable food logging
colors:
  dark-app-bg: "#000000"
  dark-screen: "#000000"
  dark-surface: "#0a0a0a"
  dark-surface-soft: "#111111"
  dark-surface-muted: "#1a1a1a"
  dark-ink: "#ffffff"
  dark-ink-soft: "#b8b8b8"
  dark-ink-muted: "#6e6e6e"
  dark-rule: "#1f1f1f"
  dark-rule-soft: "#161616"
  light-app-bg: "#f7f8f2"
  light-screen: "#ffffff"
  light-surface: "#ffffff"
  light-surface-soft: "#f4f5ef"
  light-surface-muted: "#e9ebe2"
  light-ink: "#10120d"
  light-ink-soft: "#393d33"
  light-ink-muted: "#74796d"
  light-rule: "#dde1d4"
  light-rule-soft: "#ecefe5"
  lime: "#c8e14c"
  lime-deep: "#b8d142"
  lime-soft: "#1f2410"
  lime-wash: "#13160a"
  light-lime: "#8fbd20"
  light-lime-deep: "#5f850f"
  light-lime-soft: "#e7f5c4"
  light-lime-wash: "#f3fae4"
  coral: "#ff6f80"
  light-coral: "#d5485a"
  warning-yellow: "#c8e14c"
typography:
  display:
    fontFamily: "SF Pro Display, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "48px"
    fontWeight: 700
    lineHeight: 1.16
    letterSpacing: "0"
  headline:
    fontFamily: "SF Pro Display, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "30px"
    fontWeight: 700
    lineHeight: 1.16
    letterSpacing: "0"
  title:
    fontFamily: "SF Pro Text, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "22px"
    fontWeight: 600
    lineHeight: 1.18
    letterSpacing: "0"
  body:
    fontFamily: "SF Pro Text, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.35
    letterSpacing: "0"
  label:
    fontFamily: "SF Pro Text, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1
    letterSpacing: "0"
rounded:
  none: "0px"
  sm: "10px"
  md: "18px"
  lg: "24px"
  xl: "32px"
  sheet: "28px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  xxl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.lime}"
    textColor: "{colors.dark-app-bg}"
    rounded: "{rounded.pill}"
    padding: "14px 22px"
    height: "52px"
  button-secondary:
    backgroundColor: "{colors.dark-screen}"
    textColor: "{colors.dark-ink}"
    rounded: "{rounded.pill}"
    padding: "14px 20px"
    height: "52px"
  input-underline:
    backgroundColor: "{colors.dark-screen}"
    textColor: "{colors.dark-ink}"
    rounded: "{rounded.none}"
    padding: "0 0 9px 0"
  icon-button:
    backgroundColor: "{colors.dark-screen}"
    textColor: "{colors.dark-ink}"
    rounded: "{rounded.pill}"
    size: "44px"
  bottom-nav:
    backgroundColor: "{colors.dark-screen}"
    textColor: "{colors.dark-ink-muted}"
    rounded: "{rounded.none}"
    padding: "8px 18px"
---

# Design System: Better Calories

## 1. Overview

**Creative North Star: "AMOLED Food Ledger"**

Better Calories is a mobile-first product for logging meals quickly without losing trust. The current visual direction is the recent AMOLED redesign: pure black dark surfaces, quiet rows, inspectable numbers, and controls that keep the user in the logging task. It should feel like a focused daily food ledger, not a diet dashboard, a database browser, or a chatbot that hides the real work.

The dark theme uses true AMOLED black on purpose. The main mobile canvas is `#000000` so OLED screens can turn pixels off, reduce glare, and make repeated night or evening logging feel lighter. Do not "correct" the dark canvas into near-black. Surface layers sit above pure black only when the UI needs grouping, not because every section needs a panel.

The light theme is the structural sibling of the AMOLED theme. It can be calmer and softer around the edges, but it must keep the same open sections, rows, underlined inputs, sparse lime accent, and reduced card vocabulary. Recent work has been moving the app away from rounded filled input pills, stacked cards, decorative icon chips, and heavy paneling.

**Key Characteristics:**
- Mobile-first dark mode with intentional `#000000` AMOLED canvas.
- One visual language across dark and light themes: sections, rows, rules, and underlined fields.
- Lime is functional only: action, selected state, focus, recording/progress, or confirmation.
- Nutrition values are plain text first: calories, macros, units, dates, portions, and source context stay visible.
- Cards are exceptional surfaces, not the default layout primitive.
- Voice and agent features support structured logging; they do not replace inspectable controls.

## 2. Colors

The palette is restrained and mobile-native: pure AMOLED black, a small dark tonal ladder, a calm light theme, one high-visibility lime accent, and coral for error or destructive states.

### Primary
- **Ledger Lime**: The action and selection accent. Use it for primary buttons, active navigation, focus underlines, selected controls, progress marks, recording-ready states, and confirmed values.
- **Deep Ledger Lime**: The calmer active accent. Use it for selected icons, compact status marks, and text accents when full lime would be too loud.
- **Lime Wash**: A stateful accent wash. Use it for selected surfaces or success context only when an underline or icon is not enough.

### Secondary
- **Stop Coral**: Error, rejected save, invalid input, destructive confirmation, and recording stop states. Coral is never decoration.
- **Macro Color Roles**: Protein, carbs, and fat may use small semantic label colors, lines, or indicators. They should not become large colored cards or a decorative rainbow.

### Neutral
- **AMOLED Black Canvas**: `#000000` is the dark app canvas for scaffolds, navigation, bottom sheets, and open sections. It is intentional for mobile OLED behavior.
- **AMOLED Surface Ladder**: `#0a0a0a`, `#111111`, and `#1a1a1a` are rare grouping layers for dialogs, dense choice groups, status details, and exceptional surfaces.
- **AMOLED Rules**: `#1f1f1f` and `#161616` define dividers, underlines, sheet borders, bottom navigation borders, and section separators.
- **Light Screen**: The light theme uses a clean white screen with soft food-adjacent support surfaces. It must not reintroduce old rounded card stacks.
- **Ink**: Primary text and important numbers use strong ink. Soft and muted ink carry labels, units, metadata, helper copy, and inactive navigation.

### Named Rules

**The AMOLED Is Intentional Rule.** The dark canvas is pure black. Do not tint it to near-black, gradient it, or add decorative background layers.

**The Lime Has A Job Rule.** Lime must mean action, selection, progress, focus, recording, or confirmation. If a user cannot explain why something is lime, remove the color.

**The Same Structure Rule.** Light and dark themes keep the same layout and component language. Light mode must not fall back to legacy rounded cards and filled input pills.

## 3. Typography

**Display Font:** SF Pro Display with system fallbacks.
**Body Font:** SF Pro Text with system fallbacks.
**Number Font:** SF Pro Display or SF Pro Text with tabular numeric figures.

**Character:** Native, quiet, and numerically precise. Type should feel like a polished mobile utility, not a landing page, clinical diet app, gym console, or spreadsheet.

### Hierarchy
- **Display** (700, 48px, 1.16): Rare large values and high-impact empty or onboarding moments. Use sparingly inside product flows.
- **Headline** (700, 30px to 40px, 1.14 to 1.16): Screen-level context and major sheet steps.
- **Title** (600, 18px to 22px, 1.18 to 1.2): Screen titles, section titles, row groups, and modal headings.
- **Body** (400 to 700, 14px to 16px, 1.35): Meal names, explanations, field values, result rows, and settings summaries. Long prose stays under 75 characters per line when possible.
- **Label** (500 to 700, 12px, 1): Field labels, metadata, units, nav labels, and compact status text.
- **Numbers** (600 to 800, tabular): Calories, grams, percentages, dates, and hydration values. Units stay visible and adjacent.

### Named Rules

**The Useful Number Rule.** Calories, macros, portions, and dates must be visible as text. Do not hide them behind icon-only controls.

**The No Decorative Type Rule.** No display fonts in labels, buttons, rows, or data. Letter spacing is zero.

**The Unit Stays With The Value Rule.** A number and its unit read as one control or phrase. Avoid separate boxed fields for amount and unit.

## 4. Elevation

The system is flat by default. Depth comes from pure black contrast, tonal surface layers, rules, spacing, and persistent structure, not from shadows. Shadows appear only when a control must float above live content or communicate temporal state, such as camera overlays or recording controls.

### Shadow Vocabulary
- **Dark Ambient Lift**: A low-opacity shadow for rare raised choices or floating controls in dark mode. Use it only when separation cannot be solved with spacing and rules.
- **Voice Pulse Shadow**: A state shadow for the voice action button when recording is ready or active.
- **Camera HUD Blur**: A purposeful blur over live camera imagery. This is a readability tool for real image content, not a general glass effect.

### Named Rules

**The Flat First Rule.** If a section can be understood with a title, spacing, and a divider, do not add a card.

**The No Nested Surface Rule.** Do not put cards inside cards. Dense forms use rows, underlines, dividers, and progressive disclosure.

**The Camera Exception Rule.** Black, white, translucency, and blur are allowed over live camera imagery for readability. They are not default product chrome.

## 5. Components

### Buttons
- **Shape:** Pill for primary and secondary actions (999px radius), circle for compact icon actions.
- **Primary:** Lime background, black text, minimum height 52px, horizontal padding around 22px. Use for save, confirm, submit, and primary forward actions.
- **Secondary:** Transparent or screen background with ink text and a rule-colored border when separation is needed.
- **Text / Inline:** Used for small steppers, search actions, correction links, and low-emphasis commands. Preserve 44px tap targets through padding, not visible button chrome.
- **Disabled:** Muted surface and muted ink. Never use low-opacity lime for disabled state.

### Chips
- **Style:** Chips are stateful controls, not decoration. Use them for selected filters, portion candidates, compact suggestions, and macro presets.
- **State:** Selected chips may use lime wash or a lime rule. Unselected chips stay neutral. Avoid full-saturation accent fills on inactive chips.

### Cards / Containers
- **Corner Style:** Large framed surfaces use 24px to 32px only when a frame is justified. Bottom sheets use a 28px top radius.
- **Background:** Use screen by default. Use surface layers for dialogs, rare grouped choices, code blocks, status details, and exceptional dense states.
- **Shadow Strategy:** No shadow at rest for ordinary product content.
- **Border:** Thin rule-colored borders only. Colored side-stripe borders greater than 1px are forbidden.
- **Internal Padding:** 16px to 20px for framed states. Open sections use spacing and dividers instead of container padding.

### Inputs / Fields
- **Style:** Default inputs use a label above the value and a 1px underline. They are not filled rounded boxes.
- **Number + Unit:** Use one baseline with the unit attached. Use tabular figures and a muted unit label.
- **Macro Fields:** Protein, carbs, and fat appear as a compact three-column field row with colored labels or underlines, not three separate cards.
- **Goal Inputs:** Calorie and hydration goals use a large central value with quiet inline increment and decrement controls.
- **Search:** Search is a line or row with an action icon or text. Do not wrap a search field in a parent card just to make it visible.
- **Focus / Error:** Focus uses lime underline. Error uses coral underline plus readable message.

### Navigation
- **Style:** Bottom navigation is stable, labeled, and task-oriented. The center action can be stronger than the surrounding tabs, but it must remain understandable.
- **Active State:** Lime marks the active item or central action. Inactive items use muted ink.
- **Top Bars:** Headers stay quiet: title, back, overflow, and context actions. Avoid decorative avatars or large icon chips unless they carry real state.

### Sections And Rows
- **Style:** This is the default product pattern. Use a section title, full-width rows, visible values, and thin rules.
- **Rows:** Meal rows, history rows, settings rows, search results, and editor ingredients prioritize text and values over decorative icon chips.
- **Actions:** Secondary row actions use small icons or text at the trailing edge. Destructive actions need explicit copy and coral state.

### Voice And Agent
- **Voice:** The microphone affordance may use motion, pulse, and coral stop state because recording is temporal. It must not block typed or tapped workflows.
- **Agent Chat:** Chat is a structured assistant surface, not the product shell. Tool calls, drafts, and nutrition results read as rows and sections with visible data, not opaque chat bubbles hiding controls.

## 6. Do's and Don'ts

### Do:
- **Do** keep the AMOLED dark canvas pure black (`#000000`) for mobile OLED behavior.
- **Do** keep light and AMOLED themes structurally identical.
- **Do** show calories, macros, units, dates, portions, and source context plainly.
- **Do** use open sections, full-width rows, subtle rules, and underline fields as the default structure.
- **Do** reserve cards for exceptional states, dialogs, dense choice groups, and readability over camera imagery.
- **Do** make save, confirm, correct, continue, and submit actions obvious with familiar platform controls.
- **Do** preserve WCAG AA contrast, 44px tap targets, readable errors, and non-speech alternatives for voice flows.

### Don't:
- **Don't** tint the AMOLED canvas to near-black or add decorative gradients behind product screens.
- **Don't** make Better Calories feel like a cluttered MyFitnessPal-style database browser where the user does all the work.
- **Don't** make it feel like a clinical diet or medical compliance app.
- **Don't** make it feel like a dark gym-performance dashboard dominated by aggressive metrics.
- **Don't** make it chatbot-first. Agent and voice features must not hide structured controls behind conversation.
- **Don't** make it feel like a spreadsheet-like macro tracker with dense tables as the default surface.
- **Don't** make it feel like a generic AI app that invents nutrition values without source clarity or confirmation.
- **Don't** use side-stripe borders, gradient text, decorative blur, glassmorphism, identical card grids, or cards as the first layout answer.
- **Don't** let the light theme keep legacy rounded cards, filled pills, or decorative icon chips while the dark theme uses open sections.
