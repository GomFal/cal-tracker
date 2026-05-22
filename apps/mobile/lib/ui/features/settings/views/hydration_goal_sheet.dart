import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations_context.dart';
import '../../../core/design_system.dart';
import '../../hydration/hydration_format.dart';

enum HydrationGoalUnit { liters, ounces }

class HydrationGoalSheet extends StatefulWidget {
  const HydrationGoalSheet({
    super.key,
    required this.initialLiters,
  });

  final double initialLiters;

  @override
  State<HydrationGoalSheet> createState() => _HydrationGoalSheetState();
}

class _HydrationGoalSheetState extends State<HydrationGoalSheet> {
  static const _stepLiters = 0.25;
  static const _maxLiters = 10.0;
  static const _ouncesPerLiter = 33.8140227;

  late double _liters;
  HydrationGoalUnit _unit = HydrationGoalUnit.liters;

  @override
  void initState() {
    super.initState();
    _liters = roundHydrationLiters(widget.initialLiters);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.86;
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
      child: SizedBox(
        height: maxHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 560;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.rule,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: FreshSpacing.lg),
                Text(
                  l10n.hydrationSheetTitle,
                  style: textTheme.titleLarge?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: FreshSpacing.xs),
                Text(
                  l10n.hydrationSheetSubtitle,
                  style: textTheme.bodyMedium?.copyWith(
                    color: palette.inkMuted,
                  ),
                ),
                SizedBox(height: compact ? FreshSpacing.md : FreshSpacing.lg),
                Text(
                  l10n.hydrationUnitTitle,
                  style: textTheme.titleMedium?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: FreshSpacing.sm),
                _UnitSegmentedControl(
                  selected: _unit,
                  onSelected: (unit) => setState(() => _unit = unit),
                  compact: compact,
                ),
                SizedBox(height: compact ? FreshSpacing.md : FreshSpacing.lg),
                Text(
                  l10n.hydrationDailyGoal,
                  style: textTheme.titleMedium?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: FreshSpacing.sm),
                _HydrationStepper(
                  unit: _unit,
                  liters: _liters,
                  canDecrease: _liters > 0,
                  canIncrease: _liters < _maxLiters,
                  onDecrease: () => _adjust(-_stepLiters),
                  onIncrease: () => _adjust(_stepLiters),
                  ouncesPerLiter: _ouncesPerLiter,
                ),
                const SizedBox(height: FreshSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.hydrationRecommendedRange,
                      style: textTheme.bodyMedium?.copyWith(
                        color: palette.inkMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.info_outline_rounded,
                      color: palette.inkMuted,
                      size: 18,
                    ),
                  ],
                ),
                SizedBox(height: compact ? FreshSpacing.md : FreshSpacing.lg),
                _HydrationInfoCard(compact: compact),
                const SizedBox(height: FreshSpacing.lg),
                FilledButton(
                  key: const ValueKey('save_goal_button'),
                  onPressed: () => Navigator.of(context).pop(_liters),
                  child: Text(l10n.commonSave),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _adjust(double delta) {
    setState(() {
      _liters = (_liters + delta).clamp(0, _maxLiters).toDouble();
      _liters = roundHydrationLiters(_liters);
    });
  }
}

class _UnitSegmentedControl extends StatelessWidget {
  const _UnitSegmentedControl({
    required this.selected,
    required this.onSelected,
    required this.compact,
  });

  final HydrationGoalUnit selected;
  final ValueChanged<HydrationGoalUnit> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final l10n = context.l10n;
    return Container(
      height: compact ? 52 : 56,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: _UnitOption(
              key: const ValueKey('hydration_unit_liters'),
              icon: Icons.water_drop_rounded,
              label: l10n.hydrationUnitLiters,
              selected: selected == HydrationGoalUnit.liters,
              onTap: () => onSelected(HydrationGoalUnit.liters),
              compact: compact,
            ),
          ),
          Expanded(
            child: _UnitOption(
              key: const ValueKey('hydration_unit_ounces'),
              icon: Icons.local_drink_outlined,
              label: l10n.hydrationUnitOunces,
              selected: selected == HydrationGoalUnit.ounces,
              onTap: () => onSelected(HydrationGoalUnit.ounces),
              compact: compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitOption extends StatelessWidget {
  const _UnitOption({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.compact,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: selected ? palette.limeWash : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: selected ? palette.limeDeep : palette.inkSoft,
                size: compact ? 20 : 22,
              ),
              const SizedBox(width: FreshSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: selected ? palette.limeDeep : palette.inkSoft,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HydrationStepper extends StatelessWidget {
  const _HydrationStepper({
    required this.unit,
    required this.liters,
    required this.canDecrease,
    required this.canIncrease,
    required this.onDecrease,
    required this.onIncrease,
    required this.ouncesPerLiter,
  });

  final HydrationGoalUnit unit;
  final double liters;
  final bool canDecrease;
  final bool canIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final double ouncesPerLiter;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final displayedValue = unit == HydrationGoalUnit.liters
        ? formatHydrationLiters(liters)
        : (liters * ouncesPerLiter).toStringAsFixed(1);
    final displayedUnit = unit == HydrationGoalUnit.liters ? 'L' : 'fl oz';
    final valueStyle =
        (textTheme.displaySmall ?? textTheme.headlineLarge)?.copyWith(
      color: palette.ink,
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return FreshCard(
      shadow: false,
      color: palette.surfaceSoft,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _RoundStepButton(
            key: const ValueKey('hydration_goal_decrease_button'),
            icon: Icons.remove_rounded,
            tooltip: l10n.hydrationDecreaseGoalTooltip,
            enabled: canDecrease,
            onPressed: onDecrease,
          ),
          const SizedBox(width: FreshSpacing.md),
          Expanded(
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(22),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      displayedValue,
                      key: const ValueKey('hydration_goal_value'),
                      style: valueStyle,
                    ),
                    const SizedBox(width: FreshSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        displayedUnit,
                        style: textTheme.headlineMedium?.copyWith(
                          color: palette.inkMuted,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: FreshSpacing.md),
          _RoundStepButton(
            key: const ValueKey('hydration_goal_increase_button'),
            icon: Icons.add_rounded,
            tooltip: l10n.hydrationIncreaseGoalTooltip,
            enabled: canIncrease,
            onPressed: onIncrease,
          ),
        ],
      ),
    );
  }
}

class _RoundStepButton extends StatelessWidget {
  const _RoundStepButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return FreshIconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      backgroundColor: palette.surface,
      foregroundColor: palette.inkSoft,
    );
  }
}

class _HydrationInfoCard extends StatelessWidget {
  const _HydrationInfoCard({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    return Container(
      padding:
          EdgeInsets.fromLTRB(14, compact ? 10 : 12, 14, compact ? 10 : 12),
      decoration: BoxDecoration(
        color: palette.limeWash,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 40 : 44,
            height: compact ? 40 : 44,
            decoration: BoxDecoration(
              color: palette.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.water_drop_rounded,
              color: palette.limeDeep,
              size: compact ? 24 : 26,
            ),
          ),
          const SizedBox(width: FreshSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.hydrationInfoTitle,
                  style: textTheme.titleMedium?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: FreshSpacing.xs),
                Text(
                  l10n.hydrationInfoMessage,
                  maxLines: compact ? 2 : null,
                  overflow: compact ? TextOverflow.ellipsis : null,
                  style: textTheme.bodyMedium?.copyWith(
                    color: palette.inkMuted,
                    height: 1.28,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
