# Auditoría UI AMOLED: Mis alimentos, editores, scanner y toolkit local

## 1. Alcance

Plan de análisis para continuar la transición de “Mis alimentos” y editores relacionados hacia el lenguaje visual AMOLED minimalista. Se centra en pantallas accesibles desde `/templates`, flujos de crear/editar comida guardada, crear/editar ingrediente guardado, scanner de etiqueta y rutas del local toolkit.

Archivos revisados:

- `apps/mobile/lib/app/router.dart`
- `apps/mobile/lib/main_local.dart`
- `apps/mobile/lib/local_toolkit/**`
- `apps/mobile/lib/ui/features/meal_templates/views/meal_templates_screen.dart`
- `apps/mobile/lib/ui/features/meal_templates/views/meal_template_editor_screen.dart`
- `apps/mobile/lib/ui/features/meal_templates/views/usual_food_editor_screen.dart`
- `apps/mobile/lib/ui/features/meal_templates/views/usual_food_scan_screen.dart`
- `apps/mobile/lib/ui/core/design_system.dart`

## 2. Mapa de rutas/componentes y accesibilidad

| Pantalla/componente | Ruta / entrada | Acceso visible | Confianza |
|---|---|---:|---:|
| Mis alimentos | `/templates` | Bottom nav | Alta (`router.dart:133-140`) |
| Nuevo ingrediente | `/templates/ingredients/new` | Botón `+` en tab ingredientes; local toolkit | Alta (`router.dart:143-153`) |
| Editar ingrediente | `/templates/ingredients/:id/edit` | Tap en fila de ingrediente; local toolkit | Alta (`router.dart:154-162`) |
| Nueva comida guardada | `/templates/meals/new` | Botón `+` en tab comidas; local toolkit | Alta (`router.dart:163-173`) |
| Editar comida guardada | `/templates/meals/:id/edit` | Menú `⋯` en fila de comida; local toolkit | Alta (`router.dart:174-182`) |
| Scanner etiqueta | `/templates/ingredients/scan` | CTA desde editor; local toolkit | Alta (`router.dart:71-76`) |
| Local toolkit overlay | `main_local.dart` | `flutter run --flavor local --target lib/main_local.dart` | Alta (`main_local.dart`, rutas en `_handleRouteJump`) |

## 3. Hallazgos

| Severidad | Archivo / widget | Evidencia | Antipatrón | Dirección propuesta |
|---|---|---|---|---|
| Ya mitigado / vigilar | `meal_templates_screen.dart` — `_TemplateCard`, `_UsualFoodCard` | Filas con `Container` + divisor, clases aún llamadas `Card` | Visualmente ya no son tarjetas, pero el naming puede inducir futuras regresiones. | Opcional: renombrar a `_TemplateRow` / `_UsualFoodRow` cuando se toque de nuevo. Mantener filas full-width con dividers. |
| Alta | `meal_template_editor_screen.dart` — `_MealTemplateBasicsSection` | `Container` con `palette.surface`, radio MD, padding, líneas `346-379` | Formulario básico dentro de caja; parece tarjeta antigua. | Convertir a sección abierta: título + fields apilados sobre fondo screen; usar spacing y regla inferior. |
| Alta | `meal_template_editor_screen.dart` — `_TemplateItemCard` | Clase y `Container` con surface/radius en líneas `527-579` | Cada ingrediente editable es una mini tarjeta. En editores largos crea pila de cajas. | Convertir a bloque de formulario por ingrediente con divisor inferior, header textual “Ingrediente 1”, delete discreto al final/derecha. |
| Media-alta | `meal_template_editor_screen.dart` — `_SaveBar` | `DecoratedBox` con surface, border radius y border, líneas `737-787` | Barra inferior parece tarjeta flotante. | Hacer bottom bar plana: fondo screen, borde superior, total izquierda, botón primario derecha; sin radio ni caja. |
| Media | `meal_template_editor_screen.dart` — candidate chips | `ActionChip` con avatar en líneas `428-440` | Chips múltiples pueden ensuciar; no son tarjetas pero añaden chrome. | Mantener si son selección semántica, pero quitar avatar o bajar prominencia. |
| Alta | `usual_food_editor_screen.dart` — `_EditorSection` | Icono + `Container` surface/radius en líneas `577-599` | Cada sección del editor es una caja. Choca con “no tarjetas”. | Rehacer como sección abierta con título de texto, sin icono decorativo por defecto, campos directos y divisor inferior. |
| Media-alta | `usual_food_editor_screen.dart` — `_OptionalNutrientsSection` | `Container` surface/radius + `ExpansionTile`, líneas `614-644` | Acordeón dentro de caja. | Convertir en expansión plana: encabezado row + divider; children con padding lateral mínimo. |
| Media | `usual_food_editor_screen.dart` — `_ScanFromPhotoCta` | `Container` con surface, border y radio, líneas `784-790` | CTA parece tarjeta/botón grande. | Convertir a row CTA con icono pequeño, texto y chevron/botón; separador inferior. |
| Media | `usual_food_editor_screen.dart` — `_BottomSaveBar` | `DecoratedBox` con screen y border superior, líneas `716-735` | Este ya va en buena dirección; no es card pesada. | Mantener; revisar spacing y que no parezca panel elevado. |
| Alta | `usual_food_scan_screen.dart` — `_StateCard` | Usa `Card` explícito para error/preview/progreso en líneas `622-675`, `679-705`, `741+` | Scanner usa cards blancas/rojas sobre cámara; visualmente fuera del lenguaje AMOLED. | Rediseñar como overlays HUD: barras translúcidas oscuras, texto blanco, error coral sin card Material blanca, botones planos. |
| Media | `design_system.dart` — `FreshCard`, `FreshMetricCard`, `FreshIconChip` | Componentes siguen disponibles y usados en settings/history/editors | El sistema facilita recaer en cards. | Crear guía interna o componente alternativo para rows/sections; migrar usos visibles por pantalla, no borrar de golpe. |
| Media | Local toolkit overlay | `main_local.dart` route jumps a todos los estados importantes | Puede no estar alineado visualmente, pero es herramienta dev. | No rediseñar salvo que tape/estorbe la validación; usarlo para revisar estados. |

## 4. Plan propuesto

1. **Renombrar mentalmente el patrón**: en implementación futura, tratar `*Card` en templates/editors como deuda visual aunque el widget ya sea una fila.
2. **Editor de ingrediente primero** (`usual_food_editor_screen.dart`): quitar cajas de `_EditorSection`, `_OptionalNutrientsSection` y suavizar `_ScanFromPhotoCta`.
3. **Editor de comida guardada después** (`meal_template_editor_screen.dart`): quitar caja de detalles, convertir `_TemplateItemCard` en row/section plana y simplificar `_SaveBar`.
4. **Scanner de etiqueta** (`usual_food_scan_screen.dart`): sustituir `Card` Material por overlays HUD oscuros/translúcidos. Mantener alta legibilidad sobre cámara.
5. **Design system**: introducir o consolidar patrón `section + divider` para que nuevas pantallas no vuelvan a `FreshCard` por defecto.
6. **Local toolkit**: usar rutas rápidas para comparar estados: templates, new/edit meal, new/edit food, scan.

## 5. No-goals

- No cambiar parsing/LLM, búsqueda de alimentos ni lógica de guardado.
- No cambiar rutas ni contratos de `GoRouter`.
- No rediseñar el overlay del local toolkit salvo problemas de validación.
- No eliminar todos los `Card`/`Container` del repositorio; algunos son estructurales o necesarios.
- No tocar scanner si no se puede validar visualmente con cámara/mock local.

## 6. Validación

Automática:

```bash
cd apps/mobile
flutter analyze --no-pub
flutter test test/meal_templates_widget_test.dart
flutter test test/meal_template_editor_widget_test.dart
flutter test test/usual_food_scan*  # si existe
flutter test
```

Manual/local toolkit:

```bash
flutter run --flavor local --debug --target lib/main_local.dart --dart-define=API_BASE_URL=http://10.0.2.2:3000 -d emulator-5554
```

Rutas a revisar con toolkit:

- `LocalToolkitRoute.templates` → `/templates`
- `LocalToolkitRoute.newUsualMeal` → `/templates/meals/new`
- `LocalToolkitRoute.editFirstUsualMeal` → `/templates/meals/:id/edit`
- `LocalToolkitRoute.newUsualFood` → `/templates/ingredients/new`
- `LocalToolkitRoute.editFirstUsualFood` → `/templates/ingredients/:id/edit`
- `LocalToolkitRoute.scanUsualFood` → `/templates/ingredients/scan`

Checks visuales:

- Las secciones deben leerse por títulos, no por cajas.
- Las filas/bloques deben ocupar todo el ancho útil.
- Los delete/edit secundarios deben ser discretos.
- El scanner debe tener overlays legibles sin parecer modal/card blanco.

## 7. Riesgos y preguntas abiertas

- Los formularios largos pueden perder agrupación si se quitan todas las cajas; usar divisores y títulos con spacing generoso.
- En scanner, las cards blancas aportan contraste sobre cámara; el reemplazo HUD debe probarse con fondos claros/oscuros.
- `ActionChip` en candidatos puede ser aceptable por ser selección; decidir si se aplaza.
- Pregunta de producto: ¿los editores deben sentirse “documento/formulario” o “lista editable”? Para el estilo actual, se recomienda formulario-documento con reglas.

