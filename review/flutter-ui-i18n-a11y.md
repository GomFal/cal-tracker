## Review

Nota operativa: no he modificado ficheros ni he escrito `progress.md`/`review/flutter-ui-i18n-a11y.md` porque la instrucción “READ-ONLY / No modifiques ningún fichero” entra en conflicto con “Update progress” y “Write your findings”. `plan.md` no existe; `progress.md` indica revisión en progreso.

- Correct:
  - La infraestructura i18n existe con ARB en/es y muchas claves ya están disponibles: `app_en.arb:683-766`, `app_es.arb:384-460`.
  - Hay base de tema claro/oscuro con `FreshPalette` y `ThemeExtension`: `apps/mobile/lib/app/theme.dart:33-56`, `apps/mobile/lib/ui/core/design_system.dart:30-98`.
  - Hay auditoría básica anti-colores light-only: `apps/mobile/test/dark_mode_static_audit_test.dart:6-27`.
  - Algunas pantallas ya tienen pruebas de español: auth en `apps/mobile/test/widget_test.dart:53-70`, wizard en `apps/mobile/test/calorie_calculator_wizard_test.dart:126-170`.

- Fixed:
  - Ninguno. Revisión read-only.

- Blocker:
  - **P1 — `voice_log_screen.dart` muestra muchas cadenas hardcodeadas en inglés aunque las claves ARB ya existen.** Ejemplos:
    - Título/acciones: `voice_log_screen.dart:57-69` usa `'Create meal'`, `'Back'`, `'Start over'`; existen `voiceTitle`, `commonBack`, `voiceStartOver`.
    - Estados: `voice_log_screen.dart:85-127`, `1534-1591` usa `'Transcribing...'`, `'Something went wrong'`, `'Logged...'`, etc.
    - Secciones: `voice_log_screen.dart:1609-1732` usa `'Today'`, `'Meals'`, `'Nutrition matches'`, `'Usual meals'`, `'Remaining'`.
    - Editor/propuesta: `voice_log_screen.dart:1853-2251` usa `'Custom meal type'`, `'Confirm'`, `'Edit ingredients'`, `'Add ingredient'`, `'Ingredient'`, `'Quantity'`, `'Delete ingredient'`.
    - El ViewModel también emite mensajes en inglés: `voice_log_view_model.dart:676`, `763`.
    - Impacto: usuarios en español verán una mezcla de idiomas. Recomiendo reemplazar por `context.l10n.*` y cambiar mensajes del ViewModel a códigos/estados localizables en UI.
  - **P1 — Auth tiene datos demo prellenados en producción UI.** `auth_screen.dart:29-31` inicializa email/password/nombre con `demo@example.com`, `password123`, `Test User`. Esto afecta UX, privacidad percibida y pruebas que dependen de defaults (`auth_screen_error_test.dart:54-56`). Debería estar vacío o limitado a flavor local/dev explícito.

- Note:
  - **P1 — Accesibilidad insuficiente en controles custom.**
    - El selector OCR usa `GestureDetector` + `CustomPaint` sin `Semantics`: `usual_food_scan_screen.dart:437-470`.
    - El overlay pinta textos con Canvas, invisibles para lectores de pantalla: `scan_viewfinder_overlay.dart:101-140`.
    - El ruler del wizard usa `GestureDetector` + `CustomPaint` sin `Semantics`, `increasedValue/decreasedValue` ni acciones increment/decrement: `calorie_target_sheet.dart:1842-1872`.
    - La navegación custom usa `InkWell` con texto visual pero sin `Semantics(selected: ...)`: `app_shell.dart:348-363`.
  - **P2 — Componentes duplicados y widgets monolíticos.**
    - `voice_log_screen.dart` contiene muchas clases privadas desde `MealCreateScreen` hasta `_MealLine` (`voice_log_screen.dart:19`, `2535`) y duplica búsqueda/editor de ingredientes.
    - Ya existen componentes compartidos: `FoodSearchPanel` (`shared/food_search_panel.dart:11`) y `MealItemEditorSheet` (`shared/meal_item_editor_sheet.dart:12`), pero voice log reimplementa `_FoodSearchBox`, `_ProposalEditorSheet`, `_EditableIngredientRow`, `_InlineReplacementFoodSearch` (`voice_log_screen.dart:871`, `1982`, `2167`, `2372`).
  - **P2 — Dark mode / design system drift.**
    - Hay colores raw en pantallas, fuera de `FreshPalette`: `dashboard_screen.dart:692-805`.
    - La auditoría actual solo detecta `FreshColors` y `Colors.white/black`, no `Color(0x...)`: `dark_mode_static_audit_test.dart:19-22`.
    - Recomiendo mover colores semánticos al palette y ampliar el test con allowlist.
  - **P2 — Responsive/text scale.**
    - El hero auth fija alturas grandes `318/372`: `auth_screen.dart:452-457`.
    - El overlay OCR pinta texto con tamaños fijos y `TextDirection.ltr`, ignorando text scale/locale direction: `scan_viewfinder_overlay.dart:102-133`.
    - Añadir pruebas con `textScaleFactor`, viewport pequeño y español para voice log/scan/wizard.