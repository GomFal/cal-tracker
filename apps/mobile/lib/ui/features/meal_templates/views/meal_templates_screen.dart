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
    return ContentFrame(
      title: l10n.templatesTitle,
      subtitle: l10n.templatesSubtitle,
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
          backgroundColor: FreshColors.lime,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _UsualsExplainer(selectedSection: _selectedSection),
          const SizedBox(height: FreshSpacing.lg),
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
          if (viewModel.isLoading) ...[
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: FreshSpacing.md),
          ],
          if (viewModel.error != null) ...[
            FreshStatusBanner(
              icon: Icons.error_outline_rounded,
              title: l10n.usualsCouldNotLoad,
              message: viewModel.error!,
              color: FreshColors.coral,
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

class _UsualsExplainer extends StatelessWidget {
  const _UsualsExplainer({required this.selectedSection});

  final _UsualSection selectedSection;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final limeCardTextColor = FreshPalette.dark.limeWash;
    return FreshCard(
      color: FreshColors.limeSoft,
      radius: FreshRadii.xl,
      child: Row(
        children: [
          const FreshIconChip(
            icon: Icons.star_rounded,
            color: FreshColors.limeDeep,
            backgroundColor: FreshColors.surface,
          ),
          const SizedBox(width: FreshSpacing.md),
          Expanded(
            child: Text(
              selectedSection == _UsualSection.meals
                  ? l10n.templatesExplainer
                  : l10n.usualFoodsExplainer,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: limeCardTextColor),
            ),
          ),
        ],
      ),
    );
  }
}

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
      children: [
        for (final template in viewModel.templates)
          Padding(
            padding: const EdgeInsets.only(bottom: FreshSpacing.md),
            child: _TemplateCard(
              template: template,
              onLog: () => context.push(
                '/meal/create',
                extra: MealCreateInitialItems(template.items),
              ),
              onEdit: () => context.push(
                MealTemplateEditorScreen.editRoute(template.id),
              ),
              onDelete: () =>
                  _confirmDeleteTemplate(context, viewModel, template),
            ),
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
      children: [
        for (final food in viewModel.usualFoods)
          Padding(
            padding: const EdgeInsets.only(bottom: FreshSpacing.md),
            child: _UsualFoodCard(
              food: food,
              onEdit: () =>
                  context.push(UsualFoodEditorScreen.editRoute(food.id)),
              onDelete: () => _confirmDeleteFood(context, viewModel, food),
            ),
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
    return FreshCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FreshIconChip(
                icon: Icons.shopping_basket_rounded,
                color: FreshColors.leaf,
                backgroundColor: FreshColors.limeWash,
              ),
              const SizedBox(width: FreshSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(food.name, style: textTheme.titleMedium),
                    Text(
                      [
                        if (food.brand != null) food.brand!,
                        l10n.usualFoodsPerServing(
                          _formatQuantity(food.servingGrams),
                        ),
                        l10n.usualFoodsManualSource,
                      ].join(' · '),
                      style: textTheme.bodyMedium?.copyWith(
                        color: FreshColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('usual_food_edit_${food.id}'),
                tooltip: l10n.usualFoodsEditTooltip,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded),
              ),
              IconButton(
                key: ValueKey('usual_food_delete_${food.id}'),
                tooltip: l10n.usualFoodsDeleteTooltip,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: FreshSpacing.md),
          Wrap(
            spacing: FreshSpacing.sm,
            runSpacing: FreshSpacing.sm,
            children: [
              _NutritionChip(
                label: l10n.commonCalories,
                value: '${food.nutrition.calories}',
                unit: l10n.commonKcal,
                color: FreshColors.lime,
              ),
              _NutritionChip(
                label: l10n.commonProtein,
                value: _formatQuantity(food.nutrition.proteinGrams),
                unit: 'g',
                color: FreshColors.mint,
              ),
              _NutritionChip(
                label: l10n.commonCarbs,
                value: _formatQuantity(food.nutrition.carbsGrams),
                unit: 'g',
                color: FreshColors.water,
              ),
              _NutritionChip(
                label: l10n.commonFat,
                value: _formatQuantity(food.nutrition.fatGrams),
                unit: 'g',
                color: FreshColors.orange,
              ),
            ],
          ),
        ],
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
    return FreshCard(
      padding: const EdgeInsets.all(16),
      onTap: onLog,
      child: Column(
        children: [
          Row(
            children: [
              const FreshIconChip(
                icon: Icons.local_fire_department_rounded,
                color: FreshColors.orange,
                backgroundColor: FreshColors.yellow,
              ),
              const SizedBox(width: FreshSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(template.title, style: textTheme.titleMedium),
                    Text(
                      template.aliases.isEmpty
                          ? l10n.templatesNoAliasesYet
                          : template.aliases.join(', '),
                      style: textTheme.bodyMedium?.copyWith(
                        color: FreshColors.inkMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const FreshFoodStack(
                assets: [
                  'assets/images/meal_breakfast.webp',
                  'assets/images/meal_lunch.webp',
                ],
              ),
            ],
          ),
          const SizedBox(height: FreshSpacing.md),
          Row(
            children: [
              Expanded(
                child: _NutritionPill(
                  label: l10n.commonCalories,
                  value: '${template.nutrition.calories}',
                  unit: l10n.commonKcal,
                  color: FreshColors.lime,
                ),
              ),
              const SizedBox(width: FreshSpacing.sm),
              Expanded(
                child: _NutritionPill(
                  label: l10n.commonProtein,
                  value: _formatQuantity(template.nutrition.proteinGrams),
                  unit: 'g',
                  color: FreshColors.mint,
                ),
              ),
            ],
          ),
          const SizedBox(height: FreshSpacing.md),
          Row(
            children: [
              TextButton.icon(
                key: ValueKey('meal_template_edit_${template.id}'),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded),
                label: Text(l10n.commonEditIngredients),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: FreshColors.coral,
                ),
                label: Text(l10n.commonDelete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NutritionPill extends StatelessWidget {
  const _NutritionPill({
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(FreshRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.labelMedium),
          const SizedBox(height: FreshSpacing.xs),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 4,
            children: [
              Text(
                value,
                style: textTheme.titleLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(unit, style: textTheme.bodyMedium),
              ),
            ],
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(FreshRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: textTheme.labelSmall),
          const SizedBox(height: 2),
          Text('$value $unit', style: textTheme.labelLarge),
        ],
      ),
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
