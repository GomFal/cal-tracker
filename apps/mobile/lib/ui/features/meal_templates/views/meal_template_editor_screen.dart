import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../data/services/audio_recorder_service.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../../l10n/app_localizations_context.dart';
import '../../../core/content_frame.dart';
import '../../../core/design_system.dart';
import '../../../core/user_visible_error.dart';
import '../../../core/voice_action_button.dart';
import '../../../shared/food_search_panel.dart';
import '../view_models/meal_templates_view_model.dart';

class MealTemplateEditorScreen extends StatefulWidget {
  const MealTemplateEditorScreen({
    super.key,
    this.templateId,
    this.initialDraft,
    this.audioRecorderService,
  });

  static const newRoute = '/templates/meals/new';

  static String editRoute(String templateId) =>
      '/templates/meals/$templateId/edit';

  final String? templateId;
  final UsualMealDraft? initialDraft;
  final AudioRecorderService? audioRecorderService;

  @override
  State<MealTemplateEditorScreen> createState() =>
      _MealTemplateEditorScreenState();
}

class _MealTemplateEditorScreenState extends State<MealTemplateEditorScreen> {
  final _titleController = TextEditingController();
  final _aliasesController = TextEditingController();
  final _draftController = TextEditingController();
  final _items = <_TemplateMealItemController>[];
  List<FoodCandidateGroup> _candidateGroups = const [];
  bool _hydrated = false;
  bool _loadRequested = false;
  bool _isDrafting = false;
  bool _isRecording = false;
  bool _isTranscribing = false;
  String? _status;
  bool _statusIsError = false;
  late final AudioRecorderService _audioRecorderService;
  late final bool _ownsAudioRecorderService;

  bool get _isEditing => widget.templateId != null;

  @override
  void initState() {
    super.initState();
    _audioRecorderService =
        widget.audioRecorderService ?? AudioRecorderService();
    _ownsAudioRecorderService = widget.audioRecorderService == null;
    if (!_isEditing) {
      _items.add(_TemplateMealItemController.empty());
      _hydrated = true;
    }
    final initialDraft = widget.initialDraft;
    if (initialDraft != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _applyDraft(initialDraft));
      });
    }
  }

  @override
  void dispose() {
    if (_isRecording) {
      unawaited(_audioRecorderService.cancel());
    }
    if (_ownsAudioRecorderService) {
      unawaited(_audioRecorderService.dispose());
    }
    _titleController.dispose();
    _aliasesController.dispose();
    _draftController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MealTemplatesViewModel>();
    _requestLoad(viewModel);
    final template = widget.templateId == null
        ? null
        : viewModel.templateById(widget.templateId!);
    if (template != null && !_hydrated) {
      _hydrate(template);
    }

    final l10n = context.l10n;
    final isMissingTemplate =
        _isEditing && viewModel.hasLoaded && template == null;
    final isVoiceProcessing = _isDrafting || _isTranscribing;
    return ContentFrame(
      title: _isEditing
          ? l10n.mealTemplateEditorEditTitle
          : l10n.mealTemplateEditorCreateTitle,
      subtitle: l10n.mealTemplateEditorSubtitle,
      actions: [
        FreshIconButton(
          onPressed: () => _closeEditor(context),
          icon: Icons.close_rounded,
          tooltip: l10n.commonClose,
        ),
      ],
      child: isMissingTemplate
          ? FreshStatusBanner(
              icon: Icons.error_outline_rounded,
              title: l10n.mealTemplateEditorMissingTemplateTitle,
              message: l10n.mealTemplateEditorMissingTemplateMessage,
              color: FreshColors.coral,
            )
          : Stack(
              children: [
                AbsorbPointer(
                  absorbing: isVoiceProcessing,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (viewModel.isLoading && !_hydrated) ...[
                        const LinearProgressIndicator(minHeight: 3),
                        const SizedBox(height: FreshSpacing.md),
                      ],
                      _MealTemplateBasicsCard(
                        titleController: _titleController,
                        aliasesController: _aliasesController,
                      ),
                      const SizedBox(height: FreshSpacing.md),
                      _DraftBuilderCard(
                        controller: _draftController,
                        isDrafting: _isDrafting,
                        isRecording: _isRecording,
                        isTranscribing: _isTranscribing,
                        status: _status,
                        statusIsError: _statusIsError,
                        onVoiceToggle: _toggleVoiceDraft,
                      ),
                      if (_candidateGroups.isNotEmpty) ...[
                        const SizedBox(height: FreshSpacing.md),
                        _CandidateGroupsCard(
                          groups: _candidateGroups,
                          onSelected: _applyCandidate,
                        ),
                      ],
                      const SizedBox(height: FreshSpacing.md),
                      _TemplateItemsSection(
                        items: _items,
                        onAddBlank: () {
                          setState(() {
                            _items.add(_TemplateMealItemController.empty());
                          });
                        },
                        onAddFood: (item) {
                          setState(() {
                            _items.add(
                              _TemplateMealItemController.fromMealItem(item),
                            );
                          });
                        },
                        onDelete: (index) {
                          setState(() {
                            _items.removeAt(index).dispose();
                            if (_items.isEmpty) {
                              _items.add(_TemplateMealItemController.empty());
                            }
                          });
                        },
                      ),
                      const SizedBox(height: FreshSpacing.lg),
                      _SaveBar(
                        isSaving: (viewModel.isLoading && _hydrated) ||
                            isVoiceProcessing,
                        nutrition: _totalNutrition(),
                        onSave: template == null && _isEditing
                            ? null
                            : () => _save(viewModel, template),
                      ),
                    ],
                  ),
                ),
                if (isVoiceProcessing)
                  Positioned.fill(
                    child: _MealTemplateBlockingOverlay(
                      message:
                          _status ?? l10n.mealTemplateEditorVoiceTranscribing,
                    ),
                  ),
              ],
            ),
    );
  }

  void _requestLoad(MealTemplatesViewModel viewModel) {
    if (_loadRequested) return;
    _loadRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      viewModel.load();
    });
  }

  void _hydrate(MealTemplate template) {
    _titleController.text = template.title;
    _aliasesController.text = template.aliases.join(', ');
    for (final item in _items) {
      item.dispose();
    }
    _items
      ..clear()
      ..addAll(template.items.map(_TemplateMealItemController.fromMealItem));
    if (_items.isEmpty) {
      _items.add(_TemplateMealItemController.empty());
    }
    _hydrated = true;
  }

  Future<void> _applyDraftFromText() async {
    final text = _draftController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _status = context.l10n.mealTemplateEditorDraftEmptyError;
        _statusIsError = true;
      });
      return;
    }
    setState(() {
      _isDrafting = true;
      _status = null;
      _statusIsError = false;
    });
    try {
      final draft = await context.read<MealTemplatesViewModel>().draftUsualMeal(
            text,
          );
      if (!mounted) return;
      setState(() => _applyDraft(draft));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = userVisibleErrorMessage(error);
        _statusIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isDrafting = false);
      }
    }
  }

  void _applyDraft(UsualMealDraft draft) {
    if (draft.title != null && draft.title!.trim().isNotEmpty) {
      _titleController.text = draft.title!.trim();
    }
    if (draft.aliases.isNotEmpty) {
      _aliasesController.text = draft.aliases.join(', ');
    }
    if (draft.items.isNotEmpty) {
      for (final item in _items) {
        item.dispose();
      }
      _items
        ..clear()
        ..addAll(draft.items.map(_TemplateMealItemController.fromMealItem));
    }
    _candidateGroups = draft.candidateGroups;
    _status = draft.items.isEmpty && draft.candidateGroups.isEmpty
        ? context.l10n.mealTemplateEditorDraftNeedsItems
        : context.l10n.mealTemplateEditorDraftApplied;
    _statusIsError = false;
  }

  Future<void> _toggleVoiceDraft() async {
    if (_isDrafting || _isTranscribing) return;
    if (_isRecording) {
      await _stopVoiceDraft();
      return;
    }
    try {
      await _audioRecorderService.start();
      VoiceActionHaptics.recordingStarted();
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _status = context.l10n.mealTemplateEditorVoiceRecording;
        _statusIsError = false;
      });
    } on RecorderException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = error.message ??
            userVisibleErrorMessage(
              error,
              context: UserErrorContext.voiceRecording,
            );
        _statusIsError = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = userVisibleErrorMessage(
          error,
          context: UserErrorContext.voiceRecording,
        );
        _statusIsError = true;
      });
    }
  }

  Future<void> _stopVoiceDraft() async {
    setState(() {
      _isRecording = false;
      _isTranscribing = true;
      _status = context.l10n.mealTemplateEditorVoiceTranscribing;
      _statusIsError = false;
    });
    VoiceActionHaptics.recordingStopped();
    String? path;
    final viewModel = context.read<MealTemplatesViewModel>();
    try {
      final audio = await _audioRecorderService.stop();
      path = audio?.path;
      if (path == null) {
        throw const RecorderException(
          'missing_file',
          'No audio file was created.',
        );
      }
      final transcript = await viewModel.transcribeAudio(File(path));
      if (!mounted) return;
      _draftController.text = transcript;
      await _applyDraftFromText();
    } on RecorderException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = error.message ??
            userVisibleErrorMessage(
              error,
              context: UserErrorContext.voiceRecording,
            );
        _statusIsError = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = userVisibleErrorMessage(
          error,
          context: UserErrorContext.voiceTranscription,
        );
        _statusIsError = true;
      });
    } finally {
      if (path != null) {
        unawaited(_deleteTemporaryAudio(path));
      }
      if (mounted) {
        setState(() => _isTranscribing = false);
      }
    }
  }

  void _applyCandidate(FoodCandidateGroup group, MealItem candidate) {
    final adjusted = _candidateWithMentionQuantity(candidate, group.mention);
    setState(() {
      final index = _items.indexWhere((item) => item.matchesGroup(group));
      if (index == -1) {
        _items.add(_TemplateMealItemController.fromMealItem(adjusted));
        return;
      }
      _items[index].replaceWith(adjusted);
    });
  }

  Future<void> _save(
    MealTemplatesViewModel viewModel,
    MealTemplate? template,
  ) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() {
        _status = context.l10n.mealTemplateEditorTitleRequired;
        _statusIsError = true;
      });
      return;
    }
    final items = _validItems();
    if (items == null) {
      setState(() {
        _status = context.l10n.commonIngredientDetailsError;
        _statusIsError = true;
      });
      return;
    }
    if (items.isEmpty) {
      setState(() {
        _status = context.l10n.commonAddAtLeastOneIngredient;
        _statusIsError = true;
      });
      return;
    }
    final aliases = _aliasesController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    try {
      final saved = template == null
          ? await viewModel.createTemplate(
              title: title,
              items: items,
              aliases: aliases,
            )
          : await viewModel.updateTemplate(
              template,
              title: title,
              items: items,
              aliases: aliases,
            );
      if (!mounted) return;
      _closeEditor(context, saved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = userVisibleErrorMessage(
          error,
          context: UserErrorContext.mealTemplatesSave,
        );
        _statusIsError = true;
      });
    }
  }

  List<MealItem>? _validItems() {
    final items = <MealItem>[];
    for (final item in _items) {
      final parsed = item.toMealItemOrNull();
      if (parsed == null) {
        final hasAnyValue = item.hasAnyValue;
        if (hasAnyValue) return null;
        continue;
      }
      items.add(parsed);
    }
    return items;
  }

  NutritionSnapshot _totalNutrition() {
    var calories = 0;
    var protein = 0.0;
    var carbs = 0.0;
    var fat = 0.0;
    for (final item in _validItems() ?? const <MealItem>[]) {
      calories += item.calories;
      protein += item.proteinGrams;
      carbs += item.carbsGrams;
      fat += item.fatGrams;
    }
    return NutritionSnapshot(
      calories: calories,
      proteinGrams: _roundMacro(protein),
      carbsGrams: _roundMacro(carbs),
      fatGrams: _roundMacro(fat),
    );
  }
}

void _closeEditor(BuildContext context, [Object? result]) {
  if (context.canPop()) {
    context.pop(result);
    return;
  }
  Navigator.of(context).maybePop(result);
}

class _MealTemplateBasicsCard extends StatelessWidget {
  const _MealTemplateBasicsCard({
    required this.titleController,
    required this.aliasesController,
  });

  final TextEditingController titleController;
  final TextEditingController aliasesController;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FreshCard(
      radius: FreshRadii.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const FreshIconChip(
                icon: Icons.restaurant_menu_rounded,
                color: FreshColors.orange,
                backgroundColor: FreshColors.yellow,
              ),
              const SizedBox(width: FreshSpacing.md),
              Expanded(
                child: Text(
                  l10n.mealTemplateEditorDetailsSection,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: FreshSpacing.md),
          TextField(
            key: const ValueKey('meal_template_title_field'),
            controller: titleController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.mealTemplateEditorTitleLabel,
              hintText: l10n.mealTemplateEditorTitleHint,
            ),
          ),
          const SizedBox(height: FreshSpacing.md),
          TextField(
            key: const ValueKey('meal_template_aliases_field'),
            controller: aliasesController,
            decoration: InputDecoration(
              labelText: l10n.mealTemplateEditorAliasesLabel,
              hintText: l10n.mealTemplateEditorAliasesHint,
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftBuilderCard extends StatelessWidget {
  const _DraftBuilderCard({
    required this.controller,
    required this.isDrafting,
    required this.isRecording,
    required this.isTranscribing,
    required this.status,
    required this.statusIsError,
    required this.onVoiceToggle,
  });

  final TextEditingController controller;
  final bool isDrafting;
  final bool isRecording;
  final bool isTranscribing;
  final String? status;
  final bool statusIsError;
  final VoidCallback onVoiceToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = isDrafting || isTranscribing;
    return FreshCard(
      radius: FreshRadii.xl,
      color: FreshColors.limeWash,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.mealTemplateEditorDraftSection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: FreshSpacing.xs),
          Text(
            l10n.mealTemplateEditorDraftHelper,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: FreshColors.inkMuted),
          ),
          const SizedBox(height: FreshSpacing.md),
          TextField(
            key: const ValueKey('meal_template_voice_transcript_field'),
            controller: controller,
            readOnly: true,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: l10n.mealTemplateEditorDraftLabel,
              hintText: l10n.mealTemplateEditorDraftHint,
            ),
          ),
          const SizedBox(height: FreshSpacing.md),
          Wrap(
            spacing: FreshSpacing.md,
            runSpacing: FreshSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                button: true,
                label: isRecording
                    ? l10n.mealTemplateEditorStopVoiceTooltip
                    : l10n.mealTemplateEditorVoiceTooltip,
                child: VoiceActionButtonChrome(
                  dimension: 48,
                  backgroundColor:
                      isRecording ? FreshColors.coral : FreshColors.lime,
                  isRecording: isRecording,
                  child: IconButton(
                    key: const ValueKey('meal_template_voice_button'),
                    onPressed: busy ? null : onVoiceToggle,
                    tooltip: isRecording
                        ? l10n.mealTemplateEditorStopVoiceTooltip
                        : l10n.mealTemplateEditorVoiceTooltip,
                    icon: Icon(
                      isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                      color: FreshColors.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (status != null) ...[
            const SizedBox(height: FreshSpacing.md),
            Text(
              status!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: statusIsError ? FreshColors.coral : null,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CandidateGroupsCard extends StatelessWidget {
  const _CandidateGroupsCard({required this.groups, required this.onSelected});

  final List<FoodCandidateGroup> groups;
  final void Function(FoodCandidateGroup group, MealItem candidate) onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FreshCard(
      radius: FreshRadii.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.mealTemplateEditorCandidatesSection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: FreshSpacing.xs),
          Text(
            l10n.mealTemplateEditorCandidatesHelper,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: FreshColors.inkMuted),
          ),
          const SizedBox(height: FreshSpacing.md),
          for (final group in groups) ...[
            Text(
              group.mention.originalText,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: FreshSpacing.sm),
            if (group.candidates.isEmpty)
              Text(
                l10n.mealTemplateEditorNoCandidates,
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              Wrap(
                spacing: FreshSpacing.sm,
                runSpacing: FreshSpacing.sm,
                children: [
                  for (final candidate in group.candidates.take(10))
                    ActionChip(
                      key: ValueKey(
                        'meal_template_candidate_${group.mention.originalText}_${candidate.name}',
                      ),
                      avatar: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: Text(candidate.name),
                      onPressed: () => onSelected(group, candidate),
                    ),
                ],
              ),
            const SizedBox(height: FreshSpacing.md),
          ],
        ],
      ),
    );
  }
}

class _MealTemplateBlockingOverlay extends StatelessWidget {
  const _MealTemplateBlockingOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.freshPalette.screen.withValues(alpha: 0.72),
      child: Center(
        child: FreshCard(
          padding: const EdgeInsets.all(18),
          radius: FreshRadii.xl,
          shadow: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: FreshSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  message,
                  key: const ValueKey('meal_template_voice_blocking_message'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateItemsSection extends StatefulWidget {
  const _TemplateItemsSection({
    required this.items,
    required this.onAddBlank,
    required this.onAddFood,
    required this.onDelete,
  });

  final List<_TemplateMealItemController> items;
  final VoidCallback onAddBlank;
  final ValueChanged<MealItem> onAddFood;
  final ValueChanged<int> onDelete;

  @override
  State<_TemplateItemsSection> createState() => _TemplateItemsSectionState();
}

class _TemplateItemsSectionState extends State<_TemplateItemsSection> {
  bool _searchExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FreshSectionTitle(title: l10n.mealEditorIngredientsSection),
        const SizedBox(height: FreshSpacing.sm),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: _searchExpanded
              ? FoodSearchPanel(
                  key: const ValueKey('meal_template_food_search_panel'),
                  keyPrefix: 'meal_template_food_search',
                  searchFoods:
                      context.read<MealTemplatesViewModel>().searchFoods,
                  onSelected: (item) {
                    widget.onAddFood(item);
                    setState(() => _searchExpanded = false);
                  },
                  onClose: () => setState(() => _searchExpanded = false),
                )
              : Align(
                  key: const ValueKey('meal_template_food_search_collapsed'),
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const ValueKey('meal_template_add_from_search_button'),
                    onPressed: () => setState(() => _searchExpanded = true),
                    icon: const Icon(Icons.search_rounded),
                    label: Text(l10n.mealTemplateEditorAddFromSearch),
                  ),
                ),
        ),
        const SizedBox(height: FreshSpacing.md),
        for (var index = 0; index < widget.items.length; index++) ...[
          _TemplateItemCard(
            key: ValueKey('meal_template_item_card_$index'),
            item: widget.items[index],
            index: index,
            onDelete: () => widget.onDelete(index),
          ),
          const SizedBox(height: FreshSpacing.md),
        ],
        OutlinedButton.icon(
          key: const ValueKey('meal_template_add_blank_item_button'),
          onPressed: widget.onAddBlank,
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.commonAddIngredient),
        ),
      ],
    );
  }
}

class _TemplateItemCard extends StatefulWidget {
  const _TemplateItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.onDelete,
  });

  final _TemplateMealItemController item;
  final int index;
  final VoidCallback onDelete;

  @override
  State<_TemplateItemCard> createState() => _TemplateItemCardState();
}

class _TemplateItemCardState extends State<_TemplateItemCard> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final nutrition = widget.item.previewNutrition;
    return FreshCard(
      padding: const EdgeInsets.all(16),
      shadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.commonIngredient,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                key: ValueKey('meal_template_delete_item_${widget.index}'),
                onPressed: widget.onDelete,
                tooltip: l10n.commonDeleteIngredient,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: FreshSpacing.sm),
          TextField(
            key: ValueKey('meal_template_item_name_${widget.index}'),
            controller: widget.item.nameController,
            decoration: InputDecoration(labelText: l10n.foodSearchName),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: FreshSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('meal_template_item_quantity_${widget.index}'),
                  controller: widget.item.quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: l10n.commonAmount),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: FreshSpacing.sm),
              SizedBox(
                width: 92,
                child: TextField(
                  key: ValueKey('meal_template_item_unit_${widget.index}'),
                  controller: widget.item.unitController,
                  decoration: InputDecoration(labelText: l10n.commonUnit),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: FreshSpacing.sm),
          TextField(
            key: ValueKey('meal_template_item_calories_${widget.index}'),
            controller: widget.item.caloriesController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.commonCalories),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: FreshSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _macroField(
                  context,
                  key: 'meal_template_item_protein_${widget.index}',
                  controller: widget.item.proteinController,
                  label: l10n.commonProtein,
                ),
              ),
              const SizedBox(width: FreshSpacing.sm),
              Expanded(
                child: _macroField(
                  context,
                  key: 'meal_template_item_carbs_${widget.index}',
                  controller: widget.item.carbsController,
                  label: l10n.commonCarbs,
                ),
              ),
              const SizedBox(width: FreshSpacing.sm),
              Expanded(
                child: _macroField(
                  context,
                  key: 'meal_template_item_fat_${widget.index}',
                  controller: widget.item.fatController,
                  label: l10n.commonFat,
                ),
              ),
            ],
          ),
          if (nutrition != null) ...[
            const SizedBox(height: FreshSpacing.sm),
            Text(
              _nutritionLabel(context, nutrition),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: FreshColors.inkMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _macroField(
    BuildContext context, {
    required String key,
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      key: ValueKey(key),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.isSaving,
    required this.nutrition,
    required this.onSave,
  });

  final bool isSaving;
  final NutritionSnapshot nutrition;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return FreshCard(
      radius: FreshRadii.xl,
      color: FreshColors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 420;
          final total = _TotalNutrition(nutrition: nutrition);
          final button = FilledButton.icon(
            key: const ValueKey('meal_template_save_button'),
            onPressed: isSaving ? null : onSave,
            icon: isSaving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(context.l10n.mealTemplateEditorSaveButton),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                total,
                const SizedBox(height: FreshSpacing.md),
                button,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: total),
              const SizedBox(width: FreshSpacing.md),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _TotalNutrition extends StatelessWidget {
  const _TotalNutrition({required this.nutrition});

  final NutritionSnapshot nutrition;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.mealEditorMealTotal,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: FreshSpacing.xs),
        Text(
          _nutritionLabel(context, nutrition),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _TemplateMealItemController {
  _TemplateMealItemController({
    required String name,
    required String quantity,
    required String unit,
    required String calories,
    required String protein,
    required String carbs,
    required String fat,
    this.originalText,
    this.canonicalName,
    this.language,
    this.source = 'manual',
    this.externalSource,
    this.externalId,
    this.sourceUrl,
    this.license,
    this.confidence,
    this.needsReview,
    this.resolvedGrams,
    this.portionDescription,
  })  : nameController = TextEditingController(text: name),
        quantityController = TextEditingController(text: quantity),
        unitController = TextEditingController(text: unit),
        caloriesController = TextEditingController(text: calories),
        proteinController = TextEditingController(text: protein),
        carbsController = TextEditingController(text: carbs),
        fatController = TextEditingController(text: fat);

  factory _TemplateMealItemController.empty() {
    return _TemplateMealItemController(
      name: '',
      quantity: '',
      unit: 'g',
      calories: '',
      protein: '',
      carbs: '',
      fat: '',
    );
  }

  factory _TemplateMealItemController.fromMealItem(MealItem item) {
    return _TemplateMealItemController(
      name: item.name,
      quantity: _formatQuantity(item.quantity),
      unit: item.unit,
      calories: item.calories.toString(),
      protein: _formatQuantity(item.proteinGrams),
      carbs: _formatQuantity(item.carbsGrams),
      fat: _formatQuantity(item.fatGrams),
      originalText: item.originalText,
      canonicalName: item.canonicalName,
      language: item.language,
      source: item.source,
      externalSource: item.externalSource,
      externalId: item.externalId,
      sourceUrl: item.sourceUrl,
      license: item.license,
      confidence: item.confidence,
      needsReview: item.needsReview,
      resolvedGrams: item.resolvedGrams,
      portionDescription: item.portionDescription,
    );
  }

  final TextEditingController nameController;
  final TextEditingController quantityController;
  final TextEditingController unitController;
  final TextEditingController caloriesController;
  final TextEditingController proteinController;
  final TextEditingController carbsController;
  final TextEditingController fatController;
  String? originalText;
  String? canonicalName;
  String? language;
  String source;
  String? externalSource;
  String? externalId;
  String? sourceUrl;
  String? license;
  double? confidence;
  bool? needsReview;
  double? resolvedGrams;
  String? portionDescription;

  bool get hasAnyValue {
    final unit = unitController.text.trim();
    return nameController.text.trim().isNotEmpty ||
        quantityController.text.trim().isNotEmpty ||
        (unit.isNotEmpty && unit != 'g') ||
        caloriesController.text.trim().isNotEmpty ||
        proteinController.text.trim().isNotEmpty ||
        carbsController.text.trim().isNotEmpty ||
        fatController.text.trim().isNotEmpty;
  }

  NutritionSnapshot? get previewNutrition {
    final calories = int.tryParse(caloriesController.text.trim());
    final protein = _parseDouble(proteinController.text);
    final carbs = _parseDouble(carbsController.text);
    final fat = _parseDouble(fatController.text);
    if (calories == null || protein == null || carbs == null || fat == null) {
      return null;
    }
    return NutritionSnapshot(
      calories: calories,
      proteinGrams: _roundMacro(protein),
      carbsGrams: _roundMacro(carbs),
      fatGrams: _roundMacro(fat),
    );
  }

  void replaceWith(MealItem item) {
    nameController.text = item.name;
    quantityController.text = _formatQuantity(item.quantity);
    unitController.text = item.unit;
    caloriesController.text = item.calories.toString();
    proteinController.text = _formatQuantity(item.proteinGrams);
    carbsController.text = _formatQuantity(item.carbsGrams);
    fatController.text = _formatQuantity(item.fatGrams);
    originalText = item.originalText;
    canonicalName = item.canonicalName;
    language = item.language;
    source = item.source;
    externalSource = item.externalSource;
    externalId = item.externalId;
    sourceUrl = item.sourceUrl;
    license = item.license;
    confidence = item.confidence;
    needsReview = item.needsReview;
    resolvedGrams = item.resolvedGrams;
    portionDescription = item.portionDescription;
  }

  bool matchesGroup(FoodCandidateGroup group) {
    final names = _normalizedValues([
      nameController.text,
      canonicalName,
      originalText,
    ]);
    final mentionNames = _normalizedValues([
      group.mention.originalText,
      group.mention.canonicalName,
      group.mention.canonicalEnglishName,
    ]);
    return names.intersection(mentionNames).isNotEmpty;
  }

  MealItem? toMealItemOrNull() {
    final name = nameController.text.trim();
    final quantity = _parseDouble(quantityController.text);
    final unit = unitController.text.trim();
    final calories = int.tryParse(caloriesController.text.trim());
    final protein = _parseDouble(proteinController.text);
    final carbs = _parseDouble(carbsController.text);
    final fat = _parseDouble(fatController.text);
    if (name.isEmpty ||
        quantity == null ||
        quantity <= 0 ||
        unit.isEmpty ||
        calories == null ||
        calories < 0 ||
        protein == null ||
        protein < 0 ||
        carbs == null ||
        carbs < 0 ||
        fat == null ||
        fat < 0) {
      return null;
    }
    return MealItem(
      name: name,
      quantity: quantity,
      unit: unit,
      calories: calories,
      proteinGrams: _roundMacro(protein),
      carbsGrams: _roundMacro(carbs),
      fatGrams: _roundMacro(fat),
      source: source,
      originalText: originalText,
      canonicalName: canonicalName,
      language: language,
      externalSource: externalSource,
      externalId: externalId,
      sourceUrl: sourceUrl,
      license: license,
      confidence: confidence,
      needsReview: needsReview,
      resolvedGrams: resolvedGrams,
      portionDescription: portionDescription,
    );
  }

  void dispose() {
    nameController.dispose();
    quantityController.dispose();
    unitController.dispose();
    caloriesController.dispose();
    proteinController.dispose();
    carbsController.dispose();
    fatController.dispose();
  }
}

MealItem _candidateWithMentionQuantity(
  MealItem candidate,
  FoodMention mention,
) {
  if (candidate.unit.trim().toLowerCase() !=
          mention.unit.trim().toLowerCase() ||
      candidate.quantity <= 0 ||
      mention.quantity <= 0) {
    return candidate;
  }
  final factor = mention.quantity / candidate.quantity;
  return candidate.copyWith(
    quantity: mention.quantity,
    unit: mention.unit,
    calories: (candidate.calories * factor).round(),
    proteinGrams: _roundMacro(candidate.proteinGrams * factor),
    carbsGrams: _roundMacro(candidate.carbsGrams * factor),
    fatGrams: _roundMacro(candidate.fatGrams * factor),
  );
}

String _nutritionLabel(BuildContext context, NutritionSnapshot nutrition) {
  final l10n = context.l10n;
  return '${nutrition.calories} ${l10n.commonKcal} · '
      '${_formatQuantity(nutrition.proteinGrams)}g ${l10n.commonProtein} · '
      '${_formatQuantity(nutrition.carbsGrams)}g ${l10n.commonCarbs} · '
      '${_formatQuantity(nutrition.fatGrams)}g ${l10n.commonFat}';
}

double? _parseDouble(String? value) {
  final normalized = (value ?? '').trim().replaceAll(',', '.');
  return double.tryParse(normalized);
}

double _roundMacro(double value) => (value * 10).roundToDouble() / 10;

Set<String> _normalizedValues(List<String?> values) {
  return values
      .map((value) => value?.trim().toLowerCase())
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .toSet();
}

Future<void> _deleteTemporaryAudio(String path) async {
  try {
    await File(path).delete();
  } catch (_) {
    // Ignore cleanup errors for temporary recordings.
  }
}

String _formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
