import 'package:flutter/material.dart';

typedef LocalToolkitRouteCallback = void Function(LocalToolkitRoute route);
typedef LocalToolkitScenarioCallback = void Function(
  LocalToolkitScenario scenario,
);

enum LocalToolkitRoute {
  auth,
  dashboard,
  logMeal,
  history,
  templates,
  newUsualMeal,
  editFirstUsualMeal,
  newUsualFood,
  editFirstUsualFood,
  scanUsualFood,
  settings,
}

enum LocalToolkitScenario {
  unauthenticated,
  emptyDay,
  normalDay,
  overTarget,
  goalsNotConfigured,
  proposalReady,
  clarificationRequired,
  autoCommittedMeal,
  templateHeavyAccount,
}

class LocalToolkitOverlayLabels {
  const LocalToolkitOverlayLabels({
    required this.toolButtonTooltip,
    required this.panelTitle,
    required this.panelSubtitle,
    required this.routeSectionTitle,
    required this.scenarioSectionTitle,
    required this.quickMutatorsSectionTitle,
    required this.routeAuth,
    required this.routeDashboard,
    required this.routeLogMeal,
    required this.routeHistory,
    required this.routeTemplates,
    required this.routeSettings,
    required this.routeNewUsualMeal,
    required this.routeEditFirstUsualMeal,
    required this.routeNewUsualFood,
    required this.routeEditFirstUsualFood,
    required this.routeScanUsualFood,
    required this.scenarioUnauthenticated,
    required this.scenarioEmptyDay,
    required this.scenarioNormalDay,
    required this.scenarioOverTarget,
    required this.scenarioGoalsNotConfigured,
    required this.scenarioProposalReady,
    required this.scenarioClarificationRequired,
    required this.scenarioAutoCommittedMeal,
    required this.scenarioTemplateHeavyAccount,
    required this.quickResetScenario,
    required this.quickAddSampleMeal,
    required this.quickClearMeals,
    required this.quickToggleTrustedMode,
    required this.quickSwitchLocale,
    required this.quickSwitchTheme,
    required this.quickTogglePerformanceOverlay,
    required this.performanceOverlayOn,
    required this.performanceOverlayOff,
    required this.trustedModeOn,
    required this.trustedModeOff,
    required this.closeTooltip,
  });

  final String toolButtonTooltip;
  final String panelTitle;
  final String panelSubtitle;
  final String routeSectionTitle;
  final String scenarioSectionTitle;
  final String quickMutatorsSectionTitle;
  final String routeAuth;
  final String routeDashboard;
  final String routeLogMeal;
  final String routeHistory;
  final String routeTemplates;
  final String routeSettings;
  final String routeNewUsualMeal;
  final String routeEditFirstUsualMeal;
  final String routeNewUsualFood;
  final String routeEditFirstUsualFood;
  final String routeScanUsualFood;
  final String scenarioUnauthenticated;
  final String scenarioEmptyDay;
  final String scenarioNormalDay;
  final String scenarioOverTarget;
  final String scenarioGoalsNotConfigured;
  final String scenarioProposalReady;
  final String scenarioClarificationRequired;
  final String scenarioAutoCommittedMeal;
  final String scenarioTemplateHeavyAccount;
  final String quickResetScenario;
  final String quickAddSampleMeal;
  final String quickClearMeals;
  final String quickToggleTrustedMode;
  final String quickSwitchLocale;
  final String quickSwitchTheme;
  final String quickTogglePerformanceOverlay;
  final String performanceOverlayOn;
  final String performanceOverlayOff;
  final String trustedModeOn;
  final String trustedModeOff;
  final String closeTooltip;

  String routeLabel(LocalToolkitRoute route) {
    return switch (route) {
      LocalToolkitRoute.auth => routeAuth,
      LocalToolkitRoute.dashboard => routeDashboard,
      LocalToolkitRoute.logMeal => routeLogMeal,
      LocalToolkitRoute.history => routeHistory,
      LocalToolkitRoute.templates => routeTemplates,
      LocalToolkitRoute.newUsualMeal => routeNewUsualMeal,
      LocalToolkitRoute.editFirstUsualMeal => routeEditFirstUsualMeal,
      LocalToolkitRoute.newUsualFood => routeNewUsualFood,
      LocalToolkitRoute.editFirstUsualFood => routeEditFirstUsualFood,
      LocalToolkitRoute.scanUsualFood => routeScanUsualFood,
      LocalToolkitRoute.settings => routeSettings,
    };
  }

  String scenarioLabel(LocalToolkitScenario scenario) {
    return switch (scenario) {
      LocalToolkitScenario.unauthenticated => scenarioUnauthenticated,
      LocalToolkitScenario.emptyDay => scenarioEmptyDay,
      LocalToolkitScenario.normalDay => scenarioNormalDay,
      LocalToolkitScenario.overTarget => scenarioOverTarget,
      LocalToolkitScenario.goalsNotConfigured => scenarioGoalsNotConfigured,
      LocalToolkitScenario.proposalReady => scenarioProposalReady,
      LocalToolkitScenario.clarificationRequired =>
        scenarioClarificationRequired,
      LocalToolkitScenario.autoCommittedMeal => scenarioAutoCommittedMeal,
      LocalToolkitScenario.templateHeavyAccount => scenarioTemplateHeavyAccount,
    };
  }
}

class LocalToolkitOverlay extends StatefulWidget {
  const LocalToolkitOverlay({
    required this.child,
    required this.labels,
    super.key,
    this.enabled = true,
    this.activeScenario,
    this.trustedModeEnabled,
    this.currentLocaleLabel,
    this.currentThemeLabel,
    this.onRouteJump,
    this.onScenarioSelected,
    this.onResetScenario,
    this.onAddSampleMeal,
    this.onClearMeals,
    this.onToggleTrustedMode,
    this.onSwitchLocale,
    this.onSwitchTheme,
    this.onTogglePerformanceOverlay,
    this.showPerformanceOverlay = false,
    this.alignment = Alignment.bottomRight,
    this.margin = const EdgeInsets.all(16),
  });

  static const floatingButtonKey = ValueKey<String>(
    'local_toolkit_floating_button',
  );
  static const panelKey = ValueKey<String>('local_toolkit_panel');
  static const scrimKey = ValueKey<String>('local_toolkit_scrim');

  final Widget child;
  final LocalToolkitOverlayLabels labels;
  final bool enabled;
  final LocalToolkitScenario? activeScenario;
  final bool? trustedModeEnabled;
  final String? currentLocaleLabel;
  final String? currentThemeLabel;
  final LocalToolkitRouteCallback? onRouteJump;
  final LocalToolkitScenarioCallback? onScenarioSelected;
  final VoidCallback? onResetScenario;
  final VoidCallback? onAddSampleMeal;
  final VoidCallback? onClearMeals;
  final VoidCallback? onToggleTrustedMode;
  final VoidCallback? onSwitchLocale;
  final VoidCallback? onSwitchTheme;
  final VoidCallback? onTogglePerformanceOverlay;
  final bool showPerformanceOverlay;
  final AlignmentGeometry alignment;
  final EdgeInsets margin;

  @override
  State<LocalToolkitOverlay> createState() => _LocalToolkitOverlayState();
}

class _LocalToolkitOverlayState extends State<LocalToolkitOverlay> {
  var _isPanelOpen = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Stack(
      children: [
        widget.child,
        if (widget.showPerformanceOverlay) ...[
          Positioned.fill(
            child: PerformanceOverlay.allEnabled(),
          ),
        ],
        if (_isPanelOpen) ...[
          Positioned.fill(
            child: GestureDetector(
              key: LocalToolkitOverlay.scrimKey,
              behavior: HitTestBehavior.opaque,
              onTap: _closePanel,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.18),
              ),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Material(
                  elevation: 12,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.86,
                    ),
                    child: LocalToolkitPanel(
                      key: LocalToolkitOverlay.panelKey,
                      labels: widget.labels,
                      activeScenario: widget.activeScenario,
                      trustedModeEnabled: widget.trustedModeEnabled,
                      currentLocaleLabel: widget.currentLocaleLabel,
                      currentThemeLabel: widget.currentThemeLabel,
                      onClose: _closePanel,
                      onRouteJump: widget.onRouteJump,
                      onScenarioSelected: widget.onScenarioSelected,
                      onResetScenario: widget.onResetScenario,
                      onAddSampleMeal: widget.onAddSampleMeal,
                      onClearMeals: widget.onClearMeals,
                      onToggleTrustedMode: widget.onToggleTrustedMode,
                      onSwitchLocale: widget.onSwitchLocale,
                      onSwitchTheme: widget.onSwitchTheme,
                      showPerformanceOverlay: widget.showPerformanceOverlay,
                      onTogglePerformanceOverlay: widget.onTogglePerformanceOverlay,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (!_isPanelOpen)
          Positioned.fill(
            child: SafeArea(
              minimum: widget.margin,
              child: Align(
                alignment: widget.alignment,
                child: Semantics(
                  label: widget.labels.toolButtonTooltip,
                  button: true,
                  child: FloatingActionButton.small(
                    key: LocalToolkitOverlay.floatingButtonKey,
                    heroTag: null,
                    onPressed: _openPanel,
                    child: const Icon(Icons.construction_rounded),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openPanel() {
    setState(() => _isPanelOpen = true);
  }

  void _closePanel() {
    if (!_isPanelOpen || !mounted) return;
    setState(() => _isPanelOpen = false);
  }
}

class LocalToolkitPanel extends StatelessWidget {
  const LocalToolkitPanel({
    required this.labels,
    super.key,
    this.activeScenario,
    this.trustedModeEnabled,
    this.currentLocaleLabel,
    this.currentThemeLabel,
    this.onClose,
    this.onRouteJump,
    this.onScenarioSelected,
    this.onResetScenario,
    this.onAddSampleMeal,
    this.onClearMeals,
    this.onToggleTrustedMode,
    this.onSwitchLocale,
    this.onSwitchTheme,
    this.showPerformanceOverlay,
    this.onTogglePerformanceOverlay,
  });

  final LocalToolkitOverlayLabels labels;
  final LocalToolkitScenario? activeScenario;
  final bool? trustedModeEnabled;
  final String? currentLocaleLabel;
  final String? currentThemeLabel;
  final VoidCallback? onClose;
  final LocalToolkitRouteCallback? onRouteJump;
  final LocalToolkitScenarioCallback? onScenarioSelected;
  final VoidCallback? onResetScenario;
  final VoidCallback? onAddSampleMeal;
  final VoidCallback? onClearMeals;
  final VoidCallback? onToggleTrustedMode;
  final VoidCallback? onSwitchLocale;
  final VoidCallback? onSwitchTheme;
  final bool? showPerformanceOverlay;
  final VoidCallback? onTogglePerformanceOverlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, viewInsets.bottom + 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          labels.panelTitle,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          labels.panelSubtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('local_toolkit_close_button'),
                    onPressed: onClose,
                    icon: Icon(
                      Icons.close_rounded,
                      semanticLabel: labels.closeTooltip,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ToolkitSection(
                title: labels.routeSectionTitle,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final route in LocalToolkitRoute.values)
                      ActionChip(
                        key: ValueKey<String>(
                          'local_toolkit_route_${route.toolkitKey}',
                        ),
                        avatar: Icon(route.icon, size: 18),
                        label: Text(labels.routeLabel(route)),
                        onPressed: onRouteJump == null
                            ? null
                            : () {
                                onClose?.call();
                                onRouteJump?.call(route);
                              },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _ToolkitSection(
                title: labels.scenarioSectionTitle,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final scenario in LocalToolkitScenario.values)
                      ChoiceChip(
                        key: ValueKey<String>(
                          'local_toolkit_scenario_${scenario.toolkitKey}',
                        ),
                        selected: scenario == activeScenario,
                        showCheckmark: false,
                        avatar: Icon(scenario.icon, size: 18),
                        label: Text(labels.scenarioLabel(scenario)),
                        onSelected: onScenarioSelected == null
                            ? null
                            : (_) {
                                onClose?.call();
                                onScenarioSelected?.call(scenario);
                              },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _ToolkitSection(
                title: labels.quickMutatorsSectionTitle,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumn = constraints.maxWidth >= 430;
                    final width = twoColumn
                        ? (constraints.maxWidth - 8) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MutatorButton(
                          key: const ValueKey<String>(
                            'local_toolkit_quick_reset_scenario',
                          ),
                          width: width,
                          icon: Icons.restart_alt_rounded,
                          label: labels.quickResetScenario,
                          onClose: onClose,
                          onPressed: onResetScenario,
                        ),
                        _MutatorButton(
                          key: const ValueKey<String>(
                            'local_toolkit_quick_add_sample_meal',
                          ),
                          width: width,
                          icon: Icons.add_circle_outline_rounded,
                          label: labels.quickAddSampleMeal,
                          onClose: onClose,
                          onPressed: onAddSampleMeal,
                        ),
                        _MutatorButton(
                          key: const ValueKey<String>(
                            'local_toolkit_quick_clear_meals',
                          ),
                          width: width,
                          icon: Icons.delete_sweep_rounded,
                          label: labels.quickClearMeals,
                          onClose: onClose,
                          onPressed: onClearMeals,
                        ),
                        _MutatorButton(
                          key: const ValueKey<String>(
                            'local_toolkit_quick_toggle_trusted_mode',
                          ),
                          width: width,
                          icon: trustedModeEnabled == true
                              ? Icons.verified_rounded
                              : Icons.verified_outlined,
                          label: labels.quickToggleTrustedMode,
                          value: trustedModeEnabled == null
                              ? null
                              : trustedModeEnabled == true
                                  ? labels.trustedModeOn
                                  : labels.trustedModeOff,
                          onClose: onClose,
                          onPressed: onToggleTrustedMode,
                        ),
                        _MutatorButton(
                          key: const ValueKey<String>(
                            'local_toolkit_quick_switch_locale',
                          ),
                          width: width,
                          icon: Icons.translate_rounded,
                          label: labels.quickSwitchLocale,
                          value: currentLocaleLabel,
                          onClose: onClose,
                          onPressed: onSwitchLocale,
                        ),
                        _MutatorButton(
                          key: const ValueKey<String>(
                            'local_toolkit_quick_switch_theme',
                          ),
                          width: width,
                          icon: Icons.contrast_rounded,
                          label: labels.quickSwitchTheme,
                          value: currentThemeLabel,
                          onClose: onClose,
                          onPressed: onSwitchTheme,
                        ),
                        _MutatorButton(
                          key: const ValueKey<String>(
                            'local_toolkit_quick_toggle_performance_overlay',
                          ),
                          width: width,
                          icon: showPerformanceOverlay == true
                              ? Icons.speed_rounded
                              : Icons.speed_outlined,
                          label: labels.quickTogglePerformanceOverlay,
                          value: showPerformanceOverlay == null
                              ? null
                              : showPerformanceOverlay == true
                                  ? labels.performanceOverlayOn
                                  : labels.performanceOverlayOff,
                          onClose: onClose,
                          onPressed: onTogglePerformanceOverlay,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolkitSection extends StatelessWidget {
  const _ToolkitSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _MutatorButton extends StatelessWidget {
  const _MutatorButton({
    required this.width,
    required this.icon,
    required this.label,
    required this.onClose,
    required this.onPressed,
    super.key,
    this.value,
  });

  final double width;
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onClose;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size.fromHeight(44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onPressed == null
            ? null
            : () {
                onClose?.call();
                onPressed?.call();
              },
        icon: Icon(icon, size: 19),
        label: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: onPressed == null
                        ? theme.disabledColor
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

extension on LocalToolkitRoute {
  String get toolkitKey {
    return switch (this) {
      LocalToolkitRoute.auth => 'auth',
      LocalToolkitRoute.dashboard => 'dashboard',
      LocalToolkitRoute.logMeal => 'log_meal',
      LocalToolkitRoute.history => 'history',
      LocalToolkitRoute.templates => 'templates',
      LocalToolkitRoute.newUsualMeal => 'new_usual_meal',
      LocalToolkitRoute.editFirstUsualMeal => 'edit_first_usual_meal',
      LocalToolkitRoute.newUsualFood => 'new_usual_food',
      LocalToolkitRoute.editFirstUsualFood => 'edit_first_usual_food',
      LocalToolkitRoute.scanUsualFood => 'scan_usual_food',
      LocalToolkitRoute.settings => 'settings',
    };
  }

  IconData get icon {
    return switch (this) {
      LocalToolkitRoute.auth => Icons.login_rounded,
      LocalToolkitRoute.dashboard => Icons.dashboard_rounded,
      LocalToolkitRoute.logMeal => Icons.mic_rounded,
      LocalToolkitRoute.history => Icons.query_stats_rounded,
      LocalToolkitRoute.templates => Icons.bookmarks_rounded,
      LocalToolkitRoute.newUsualMeal => Icons.restaurant_menu_rounded,
      LocalToolkitRoute.editFirstUsualMeal => Icons.edit_note_rounded,
      LocalToolkitRoute.newUsualFood => Icons.add_shopping_cart_rounded,
      LocalToolkitRoute.editFirstUsualFood => Icons.edit_attributes_rounded,
      LocalToolkitRoute.scanUsualFood => Icons.document_scanner_rounded,
      LocalToolkitRoute.settings => Icons.settings_rounded,
    };
  }
}

extension on LocalToolkitScenario {
  String get toolkitKey {
    return switch (this) {
      LocalToolkitScenario.unauthenticated => 'unauthenticated',
      LocalToolkitScenario.emptyDay => 'empty_day',
      LocalToolkitScenario.normalDay => 'normal_day',
      LocalToolkitScenario.overTarget => 'over_target',
      LocalToolkitScenario.goalsNotConfigured => 'goals_not_configured',
      LocalToolkitScenario.proposalReady => 'proposal_ready',
      LocalToolkitScenario.clarificationRequired => 'clarification_required',
      LocalToolkitScenario.autoCommittedMeal => 'auto_committed_meal',
      LocalToolkitScenario.templateHeavyAccount => 'template_heavy_account',
    };
  }

  IconData get icon {
    return switch (this) {
      LocalToolkitScenario.unauthenticated => Icons.lock_open_rounded,
      LocalToolkitScenario.emptyDay => Icons.inbox_rounded,
      LocalToolkitScenario.normalDay => Icons.today_rounded,
      LocalToolkitScenario.overTarget => Icons.local_fire_department_rounded,
      LocalToolkitScenario.goalsNotConfigured => Icons.flag_outlined,
      LocalToolkitScenario.proposalReady => Icons.fact_check_rounded,
      LocalToolkitScenario.clarificationRequired => Icons.help_outline_rounded,
      LocalToolkitScenario.autoCommittedMeal => Icons.check_circle_rounded,
      LocalToolkitScenario.templateHeavyAccount => Icons.bookmarks_rounded,
    };
  }
}
