part of '../voice_log_screen.dart';

class _OpenSection extends StatelessWidget {
  const _OpenSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FreshSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FreshSectionTitle(title: title),
          const SizedBox(height: FreshSpacing.sm),
          Divider(color: palette.ruleSoft, height: 1),
          const SizedBox(height: FreshSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final DailySummary summary;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final l10n = context.l10n;
    return _OpenSection(
      title: l10n.commonToday,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricBlock(
                  label: l10n.commonConsumed,
                  value: '${summary.consumed.calories}',
                  unit: l10n.commonKcal,
                  color: palette.lime,
                ),
              ),
              const SizedBox(width: FreshSpacing.md),
              Expanded(
                child: _MetricBlock(
                  label: l10n.commonRemaining,
                  value: '${summary.remaining.calories}',
                  unit: l10n.commonKcal,
                  color: palette.water,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MealsCard extends StatelessWidget {
  const _MealsCard({required this.meals});

  final List<Meal> meals;

  @override
  Widget build(BuildContext context) {
    return _OpenSection(
      title: 'Meals',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meals.isEmpty)
            const FreshEmptyState(
              icon: Icons.restaurant_rounded,
              title: 'No meals yet',
              message: 'Logged meals will appear here.',
            )
          else
            for (final meal in meals)
              _MealLine(
                title: meal.title,
                subtitle: '${meal.items.length} items',
                calories: meal.nutrition.calories,
              ),
        ],
      ),
    );
  }
}

class _NutritionItemsCard extends StatelessWidget {
  const _NutritionItemsCard({required this.items});

  final List<MealItem> items;

  @override
  Widget build(BuildContext context) {
    return _OpenSection(
      title: 'Nutrition matches',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            _MealLine(
              title: item.name,
              subtitle: '${formatQuantity(item.quantity)} ${item.unit}',
              calories: item.calories,
            ),
        ],
      ),
    );
  }
}

class _TemplatesCard extends StatelessWidget {
  const _TemplatesCard({required this.templates});

  final List<MealTemplate> templates;

  @override
  Widget build(BuildContext context) {
    return _OpenSection(
      title: 'Usual meals',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final template in templates)
            _MealLine(
              title: template.title,
              subtitle: template.aliases.join(', '),
              calories: template.nutrition.calories,
            ),
        ],
      ),
    );
  }
}

class _RemainingCard extends StatelessWidget {
  const _RemainingCard({required this.remaining});

  final NutritionSnapshot remaining;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final l10n = context.l10n;
    return _OpenSection(
      title: l10n.commonRemaining,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricBlock(
                  label: l10n.commonCalories,
                  value: '${remaining.calories}',
                  unit: l10n.commonKcal,
                  color: palette.lime,
                ),
              ),
              const SizedBox(width: FreshSpacing.md),
              Expanded(
                child: _MetricBlock(
                  label: l10n.commonProtein,
                  value: formatQuantity(remaining.proteinGrams),
                  unit: 'g',
                  color: palette.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.labelMedium?.copyWith(color: color)),
        const SizedBox(height: FreshSpacing.xs),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 4,
          children: [
            Text(
              value,
              style: textTheme.headlineMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(unit, style: textTheme.bodyMedium),
            ),
          ],
        ),
      ],
    );
  }
}

class _MealLine extends StatelessWidget {
  const _MealLine({
    required this.title,
    required this.subtitle,
    required this.calories,
  });

  final String title;
  final String subtitle;
  final int calories;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.freshPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.ruleSoft)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.bodyLarge),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: textTheme.bodyMedium?.copyWith(
                        color: palette.inkMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: FreshSpacing.sm),
            Text(
              '$calories Kcal',
              style: textTheme.labelLarge?.copyWith(
                color: palette.orange,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
