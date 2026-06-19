import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../domain/models/nutrition_models.dart';
import '../../../../l10n/app_localizations_context.dart';
import '../../../core/content_frame.dart';
import '../../../core/design_system.dart';
import '../../voice_log/views/voice_log_screen.dart';
import '../view_models/meal_templates_view_model.dart';
import 'meal_template_editor_screen.dart';
import 'usual_food_editor_screen.dart';

class MealTemplatesScreen extends StatefulWidget {
  const MealTemplatesScreen({super.key});

  @override
  State<MealTemplatesScreen> createState() => _MealTemplatesScreenState();
}

class _MealTemplatesScreenState extends State<MealTemplatesScreen> {
  var _selectedSection = _UsualSection.meals;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<MealTemplatesViewModel>().load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MealTemplatesViewModel>();
    final l10n = context.l10n;
    final palette = context.freshPalette;
    return ContentFrame(
      title: l10n.templatesTitle,
      actions: [
        FreshIconButton(
          onPressed: () => viewModel.load(forceRefresh: true),
          icon: Icons.refresh_rounded,
          tooltip: l10n.commonRefresh,
        ),
        FreshIconButton(
          onPressed: () => _showAddAction(context),
          icon: Icons.add_rounded,
          tooltip: _selectedSection == _UsualSection.meals
              ? l10n.templatesAddTooltip
              : l10n.usualFoodsAddTooltip,
          backgroundColor: palette.lime,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<_UsualSection>(
            key: const ValueKey('usuals_section_tabs'),
            segments: [
              ButtonSegment(
                value: _UsualSection.meals,
                label: Text(l10n.usualsMealsTab),
                icon: const Icon(Icons.restaurant_menu_rounded),
              ),
              ButtonSegment(
                value: _UsualSection.ingredients,
                label: Text(l10n.usualsIngredientsTab),
                icon: const Icon(Icons.shopping_basket_rounded),
              ),
            ],
            selected: {_selectedSection},
            onSelectionChanged: (selection) {
              setState(() => _selectedSection = selection.single);
            },
          ),
          const SizedBox(height: FreshSpacing.lg),
          Text(
            _selectedSection == _UsualSection.meals
                ? l10n.templatesExplainer
                : l10n.usualFoodsExplainer,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: palette.inkMuted),
          ),
          const SizedBox(height: FreshSpacing.lg),
          if (viewModel.isLoading) ...[
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: FreshSpacing.md),
          ],
          if (viewModel.error != null) ...[
            FreshStatusBanner(
              icon: Icons.error_outline_rounded,
              title: l10n.usualsCouldNotLoad,
              message: viewModel.error!,
              color: palette.coral,
            ),
            const SizedBox(height: FreshSpacing.md),
          ],
          if (_selectedSection == _UsualSection.meals)
            _MealsSection(viewModel: viewModel)
          else
            _IngredientsSection(viewModel: viewModel),
        ],
      ),
    );
  }

  Future<void> _showAddAction(BuildContext context) async {
    if (_selectedSection == _UsualSection.meals) {
      await context.push(MealTemplateEditorScreen.newRoute);
      return;
    }
    await context.push(UsualFoodEditorScreen.newRoute);
  }
}

enum _UsualSection { meals, ingredients }

class _MealsSection extends StatelessWidget {
  const _MealsSection({required this.viewModel});

  final MealTemplatesViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    if (viewModel.templates.isEmpty) {
      return FreshEmptyState(
        icon: Icons.restaurant_menu_rounded,
        title: context.l10n.templatesNoUsualMealsYet,
        message: context.l10n.templatesNoUsualMealsMessage,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final template in viewModel.templates)
          _TemplateCard(
            template: template,
            onLog: () => context.push(
              '/meal/create',
              extra: MealCreateInitialItems(template.items),
            ),
            onEdit: () => context.push(
              MealTemplateEditorScreen.editRoute(template.id),
            ),
            onDelete: () => _confirmDeleteTemplate(context, viewModel, template),
          ),
      ],
    );
  }

  Future<void> _confirmDeleteTemplate(
    BuildContext context,
    MealTemplatesViewModel viewModel,
    MealTemplate template,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.templatesDeleteUsualMealTitle),
        content: Text(template.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await viewModel.deleteTemplate(template);
    }
  }
}

class _IngredientsSection extends StatelessWidget {
  const _IngredientsSection({required this.viewModel});

  final MealTemplatesViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    if (viewModel.usualFoods.isEmpty) {
      return FreshEmptyState(
        icon: Icons.shopping_basket_rounded,
        title: context.l10n.usualFoodsEmptyTitle,
        message: context.l10n.usualFoodsEmptyMessage,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final food in viewModel.usualFoods)
          _UsualFoodCard(
            food: food,
            onEdit: () => context.push(UsualFoodEditorScreen.editRoute(food.id)),
            onDelete: () => _confirmDeleteFood(context, viewModel, food),
          ),
      ],
    );
  }

  Future<void> _confirmDeleteFood(
    BuildContext context,
    MealTemplatesViewModel viewModel,
    UsualFood food,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.usualFoodsDeleteTitle),
        content: Text(context.l10n.usualFoodsDeleteMessage(food.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('usual_food_confirm_delete_button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await viewModel.deleteUsualFood(food);
    }
  }
}

class _UsualFoodCard extends StatelessWidget {
  const _UsualFoodCard({
    required this.food,
    required this.onEdit,
    required this.onDelete,
  });

  final UsualFood food;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final palette = context.freshPalette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('usual_food_edit_${food.id}'),
        onTap: onEdit,
        borderRadius: BorderRadius.circular(FreshRadii.sm),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: palette.rule, width: 1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                food.name,
                style: textTheme.titleMedium?.copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: FreshSpacing.xs),
              Text(
                [
                  if (food.brand != null) food.brand!,
                  l10n.usualFoodsPerServing(_formatQuantity(food.servingGrams)),
                  l10n.usualFoodsManualSource,
                ].join(' · '),
                style: textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
              ),
              const SizedBox(height: FreshSpacing.md),
              Wrap(
                spacing: FreshSpacing.lg,
                runSpacing: FreshSpacing.sm,
                children: [
                  _NutritionChip(
                    label: l10n.commonCalories,
                    value: '${food.nutrition.calories}',
                    unit: l10n.commonKcal,
                    color: palette.lime,
                  ),
                  _NutritionChip(
                    label: l10n.commonProtein,
                    value: _formatQuantity(food.nutrition.proteinGrams),
                    unit: 'g',
                    color: palette.lime,
                  ),
                  _NutritionChip(
                    label: l10n.commonCarbs,
                    value: _formatQuantity(food.nutrition.carbsGrams),
                    unit: 'g',
                    color: palette.lime,
                  ),
                  _NutritionChip(
                    label: l10n.commonFat,
                    value: _formatQuantity(food.nutrition.fatGrams),
                    unit: 'g',
                    color: palette.lime,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onLog,
    required this.onEdit,
    required this.onDelete,
  });

  final MealTemplate template;
  final VoidCallback onLog;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final palette = context.freshPalette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onLog,
        borderRadius: BorderRadius.circular(FreshRadii.sm),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: palette.rule, width: 1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          template.title,
                          style: textTheme.titleMedium?.copyWith(
                            color: palette.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: FreshSpacing.xs),
                        Text(
                          template.aliases.isEmpty
                              ? l10n.templatesNoAliasesYet
                              : template.aliases.join(', '),
                          style: textTheme.bodyMedium?.copyWith(
                            color: palette.inkMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  FreshIconButton(
                    key: ValueKey('meal_template_actions_${template.id}'),
                    tooltip: l10n.commonEditIngredients,
                    onPressed: () => _showTemplateActions(context),
                    icon: Icons.more_horiz_rounded,
                    size: 38,
                  ),
                ],
              ),
              const SizedBox(height: FreshSpacing.md),
              Wrap(
                spacing: FreshSpacing.lg,
                runSpacing: FreshSpacing.sm,
                children: [
                  _NutritionChip(
                    label: l10n.commonCalories,
                    value: '${template.nutrition.calories}',
                    unit: l10n.commonKcal,
                    color: palette.lime,
                  ),
                  _NutritionChip(
                    label: l10n.commonProtein,
                    value: _formatQuantity(template.nutrition.proteinGrams),
                    unit: 'g',
                    color: palette.lime,
                  ),
                  _NutritionChip(
                    label: l10n.commonCarbs,
                    value: _formatQuantity(template.nutrition.carbsGrams),
                    unit: 'g',
                    color: palette.lime,
                  ),
                  _NutritionChip(
                    label: l10n.commonFat,
                    value: _formatQuantity(template.nutrition.fatGrams),
                    unit: 'g',
                    color: palette.lime,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTemplateActions(BuildContext context) async {
    final palette = context.freshPalette;
    final l10n = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(template.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: FreshSpacing.md),
              TextButton.icon(
                key: ValueKey('meal_template_edit_${template.id}'),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  onEdit();
                },
                icon: const Icon(Icons.edit_rounded),
                label: Text(l10n.commonEditIngredients),
              ),
              TextButton.icon(
                key: ValueKey('meal_template_delete_${template.id}'),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  onDelete();
                },
                icon: Icon(Icons.delete_outline_rounded, color: palette.coral),
                label: Text(l10n.commonDelete),
                style: TextButton.styleFrom(foregroundColor: palette.coral),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NutritionChip extends StatelessWidget {
  const _NutritionChip({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.freshPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: textTheme.labelSmall?.copyWith(
            color: palette.inkMuted,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$value $unit',
          style: textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

String _formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
