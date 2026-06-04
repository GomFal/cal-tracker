import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../data/services/audio_recorder_service.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../../l10n/app_localizations_context.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../core/design_system.dart';
import '../../../core/user_visible_error.dart';
import '../view_models/meal_templates_view_model.dart';

class UsualFoodEditorScreen extends StatefulWidget {
  const UsualFoodEditorScreen({
    super.key,
    this.foodId,
    this.initialDraft,
    this.audioRecorderService,
  });

  static const newRoute = '/templates/ingredients/new';

  static String editRoute(String foodId) =>
      '/templates/ingredients/$foodId/edit';

  final String? foodId;
  final UsualFoodDraft? initialDraft;
  final AudioRecorderService? audioRecorderService;

  @override
  State<UsualFoodEditorScreen> createState() => _UsualFoodEditorScreenState();
}

enum _VoiceDraftPhase {
  idle,
  requestingPermission,
  recording,
  stopping,
  transcribing,
  drafting,
  error,
}

class _UsualFoodEditorScreenState extends State<UsualFoodEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final AudioRecorderService _audioRecorderService;
  late final bool _ownsAudioRecorderService;
  late final TextEditingController _nameController;
  late final TextEditingController _brandController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _aliasesController;
  late final TextEditingController _servingGramsController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;
  late final TextEditingController _saltController;
  late final TextEditingController _sodiumController;
  late final TextEditingController _fiberController;
  late final TextEditingController _sugarsController;
  late final TextEditingController _servingDescriptionController;
  bool _loadComplete = false;
  bool _initializedFromFood = false;
  bool _isSaving = false;
  String? _canonicalName;
  _VoiceDraftPhase _voicePhase = _VoiceDraftPhase.idle;
  String? _transcript;
  String? _voiceStatus;
  bool _voiceStatusIsError = false;

  bool get _isEditing => widget.foodId != null;
  bool get _isVoiceBusy =>
      _voicePhase == _VoiceDraftPhase.requestingPermission ||
      _voicePhase == _VoiceDraftPhase.stopping ||
      _voicePhase == _VoiceDraftPhase.transcribing ||
      _voicePhase == _VoiceDraftPhase.drafting;

  @override
  void initState() {
    super.initState();
    _audioRecorderService =
        widget.audioRecorderService ?? AudioRecorderService();
    _ownsAudioRecorderService = widget.audioRecorderService == null;
    _nameController = TextEditingController();
    _brandController = TextEditingController();
    _barcodeController = TextEditingController();
    _aliasesController = TextEditingController();
    _servingGramsController = TextEditingController();
    _caloriesController = TextEditingController();
    _proteinController = TextEditingController();
    _carbsController = TextEditingController();
    _fatController = TextEditingController();
    _saltController = TextEditingController();
    _sodiumController = TextEditingController();
    _fiberController = TextEditingController();
    _sugarsController = TextEditingController();
    _servingDescriptionController = TextEditingController();
    final initialDraft = widget.initialDraft;
    if (initialDraft != null) {
      _applyDraft(initialDraft);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadForEdit());
  }

  @override
  void dispose() {
    if (_voicePhase == _VoiceDraftPhase.recording) {
      _audioRecorderService.cancel();
    }
    if (_ownsAudioRecorderService) {
      _audioRecorderService.dispose();
    }
    _nameController.dispose();
    _brandController.dispose();
    _barcodeController.dispose();
    _aliasesController.dispose();
    _servingGramsController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _saltController.dispose();
    _sodiumController.dispose();
    _fiberController.dispose();
    _sugarsController.dispose();
    _servingDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadForEdit() async {
    await context.read<MealTemplatesViewModel>().load();
    if (!mounted) return;
    setState(() => _loadComplete = true);
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MealTemplatesViewModel>();
    final l10n = context.l10n;
    final food = _findFood(viewModel);
    if (food != null && !_initializedFromFood) {
      _populateFromFood(food);
    }

    final isWaitingForEditFood =
        _isEditing && food == null && (viewModel.isLoading || !_loadComplete);
    final title =
        _isEditing ? l10n.usualFoodsEditTitle : l10n.usualFoodsCreateTitle;
    return Scaffold(
      backgroundColor: context.freshPalette.screen,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: FreshHeader(
                    title: title,
                    subtitle: l10n.usualFoodsEditorSubtitle,
                    leading: FreshIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: l10n.commonBack,
                      onPressed: _leaveEditor,
                    ),
                  ),
                ),
                Expanded(
                  child: isWaitingForEditFood
                      ? const Center(child: CircularProgressIndicator())
                      : food == null && _isEditing
                          ? _NotFoundState(onBack: _leaveEditor)
                          : _buildForm(viewModel, food),
                ),
                if (!isWaitingForEditFood && (food != null || !_isEditing))
                  _BottomSaveBar(
                    isSaving: _isSaving || _isVoiceBusy,
                    isEditing: _isEditing,
                    onCancel: _leaveEditor,
                    onSave: () => _submit(viewModel, food),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(MealTemplatesViewModel viewModel, UsualFood? food) {
    final l10n = context.l10n;
    final palette = context.freshPalette;
    final form = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 112),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _VoiceDraftCard(
              phase: _voicePhase,
              transcript: _transcript,
              status: _voiceStatus,
              statusIsError: _voiceStatusIsError,
              onPressed:
                  _isVoiceBusy ? null : () => _toggleVoiceDraft(viewModel),
            ),
            const SizedBox(height: FreshSpacing.lg),
            _EditorSection(
              title: l10n.usualFoodsIdentitySectionTitle,
              icon: Icons.badge_outlined,
              child: Column(
                children: [
                  _textField(
                    key: 'usual_food_name_field',
                    controller: _nameController,
                    label: l10n.usualFoodsNameLabel,
                    validator: _requiredTextValidator,
                    textInputAction: TextInputAction.next,
                    autofocus: !_isEditing,
                  ),
                  _textField(
                    key: 'usual_food_brand_field',
                    controller: _brandController,
                    label: l10n.usualFoodsBrandLabel,
                    textInputAction: TextInputAction.next,
                  ),
                ],
              ),
            ),
            const SizedBox(height: FreshSpacing.lg),
            _EditorSection(
              title: l10n.usualFoodsServingSectionTitle,
              icon: Icons.scale_rounded,
              child: _textField(
                key: 'usual_food_serving_grams_field',
                controller: _servingGramsController,
                label: l10n.usualFoodsServingGramsLabel,
                keyboardType: TextInputType.number,
                validator: (value) => _positiveNumberValidator(value, l10n),
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(height: FreshSpacing.lg),
            _EditorSection(
              title: l10n.usualFoodsMacrosSectionTitle,
              icon: Icons.monitor_heart_outlined,
              child: _MacroGrid(
                children: [
                  _textField(
                    key: 'usual_food_calories_field',
                    controller: _caloriesController,
                    label: l10n.usualFoodsCaloriesLabel,
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        _nonNegativeIntegerValidator(value, l10n),
                    textInputAction: TextInputAction.next,
                  ),
                  _textField(
                    key: 'usual_food_protein_field',
                    controller: _proteinController,
                    label: l10n.usualFoodsProteinLabel,
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        _nonNegativeNumberValidator(value, l10n),
                    textInputAction: TextInputAction.next,
                  ),
                  _textField(
                    key: 'usual_food_carbs_field',
                    controller: _carbsController,
                    label: l10n.usualFoodsCarbsLabel,
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        _nonNegativeNumberValidator(value, l10n),
                    textInputAction: TextInputAction.next,
                  ),
                  _textField(
                    key: 'usual_food_fat_field',
                    controller: _fatController,
                    label: l10n.usualFoodsFatLabel,
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        _nonNegativeNumberValidator(value, l10n),
                    textInputAction: TextInputAction.next,
                  ),
                ],
              ),
            ),
            const SizedBox(height: FreshSpacing.lg),
            _OptionalNutrientsSection(
              children: [
                _TwoColumnFields(
                  children: [
                    _textField(
                      key: 'usual_food_salt_field',
                      controller: _saltController,
                      label: l10n.usualFoodsSaltLabel,
                      keyboardType: TextInputType.number,
                      validator: (value) =>
                          _optionalNumberValidator(value, l10n),
                      textInputAction: TextInputAction.next,
                    ),
                    _textField(
                      key: 'usual_food_sodium_field',
                      controller: _sodiumController,
                      label: l10n.usualFoodsSodiumLabel,
                      keyboardType: TextInputType.number,
                      validator: (value) =>
                          _optionalNumberValidator(value, l10n),
                      textInputAction: TextInputAction.next,
                    ),
                  ],
                ),
                _TwoColumnFields(
                  children: [
                    _textField(
                      key: 'usual_food_fiber_field',
                      controller: _fiberController,
                      label: l10n.usualFoodsFiberLabel,
                      keyboardType: TextInputType.number,
                      validator: (value) =>
                          _optionalNumberValidator(value, l10n),
                      textInputAction: TextInputAction.next,
                    ),
                    _textField(
                      key: 'usual_food_sugars_field',
                      controller: _sugarsController,
                      label: l10n.usualFoodsSugarsLabel,
                      keyboardType: TextInputType.number,
                      validator: (value) =>
                          _optionalNumberValidator(value, l10n),
                      textInputAction: TextInputAction.next,
                    ),
                  ],
                ),
                _textField(
                  key: 'usual_food_serving_description_field',
                  controller: _servingDescriptionController,
                  label: l10n.usualFoodsServingDescriptionLabel,
                  textInputAction: TextInputAction.next,
                ),
                _textField(
                  key: 'usual_food_barcode_field',
                  controller: _barcodeController,
                  label: l10n.usualFoodsBarcodeLabel,
                  textInputAction: TextInputAction.next,
                ),
                _textField(
                  key: 'usual_food_aliases_field',
                  controller: _aliasesController,
                  label: l10n.usualFoodsAliasesLabel,
                  textInputAction: TextInputAction.done,
                ),
              ],
            ),
            if (viewModel.error != null) ...[
              const SizedBox(height: FreshSpacing.lg),
              FreshStatusBanner(
                icon: Icons.error_outline_rounded,
                title: l10n.usualFoodsSaveFailedTitle,
                message: viewModel.error,
                color: palette.coral,
              ),
            ],
          ],
        ),
      ),
    );
    if (!_isVoiceBusy) return form;
    return Stack(
      children: [
        AbsorbPointer(absorbing: true, child: form),
        Positioned.fill(
          child: _VoiceDraftBlockingOverlay(
            message: _voiceStatus ?? l10n.usualFoodsVoiceDraftingStatus,
          ),
        ),
      ],
    );
  }

  Widget _textField({
    required String key,
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    TextInputAction? textInputAction,
    bool autofocus = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FreshSpacing.md),
      child: TextFormField(
        key: ValueKey(key),
        controller: controller,
        autofocus: autofocus,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        validator: validator,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  UsualFood? _findFood(MealTemplatesViewModel viewModel) {
    final foodId = widget.foodId;
    if (foodId == null) return null;
    for (final food in viewModel.usualFoods) {
      if (food.id == foodId) return food;
    }
    return null;
  }

  void _populateFromFood(UsualFood food) {
    _initializedFromFood = true;
    _nameController.text = food.name;
    _brandController.text = food.brand ?? '';
    _canonicalName = food.canonicalName;
    _barcodeController.text = food.barcode ?? '';
    _aliasesController.text = food.aliases.join(', ');
    _servingGramsController.text = _formatQuantity(food.servingGrams);
    _caloriesController.text = food.nutrition.calories.toString();
    _proteinController.text = _formatQuantity(food.nutrition.proteinGrams);
    _carbsController.text = _formatQuantity(food.nutrition.carbsGrams);
    _fatController.text = _formatQuantity(food.nutrition.fatGrams);
    _saltController.text = _formatOptionalNutrient(food, 'saltGrams');
    _sodiumController.text = _formatOptionalNutrient(food, 'sodiumMilligrams');
    _fiberController.text = _formatOptionalNutrient(food, 'fiberGrams');
    _sugarsController.text = _formatOptionalNutrient(food, 'sugarsGrams');
    _servingDescriptionController.text =
        food.nutrients['servingDescription']?.toString() ?? '';
  }

  Future<void> _toggleVoiceDraft(MealTemplatesViewModel viewModel) async {
    if (_voicePhase == _VoiceDraftPhase.recording) {
      await _stopAndDraft(viewModel);
      return;
    }
    await _startRecording();
  }

  Future<void> _startRecording() async {
    setState(() {
      _voicePhase = _VoiceDraftPhase.requestingPermission;
      _voiceStatus = context.l10n.usualFoodsVoicePermissionStatus;
      _voiceStatusIsError = false;
    });
    try {
      await _audioRecorderService.start();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _voicePhase = _VoiceDraftPhase.recording;
        _voiceStatus = context.l10n.usualFoodsVoiceRecordingStatus;
      });
    } on RecorderException catch (error) {
      if (!mounted) return;
      setState(() {
        _voicePhase = _VoiceDraftPhase.error;
        _voiceStatus = error.code == 'permission_denied'
            ? context.l10n.usualFoodsVoicePermissionError
            : error.message ??
                userVisibleErrorMessage(
                  error,
                  context: UserErrorContext.voiceRecording,
                );
        _voiceStatusIsError = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _voicePhase = _VoiceDraftPhase.error;
        _voiceStatus = userVisibleErrorMessage(
          error,
          context: UserErrorContext.voiceRecording,
        );
        _voiceStatusIsError = true;
      });
    }
  }

  Future<void> _stopAndDraft(MealTemplatesViewModel viewModel) async {
    setState(() {
      _voicePhase = _VoiceDraftPhase.stopping;
      _voiceStatus = context.l10n.usualFoodsVoiceStoppingStatus;
      _voiceStatusIsError = false;
    });
    String? path;
    try {
      final audio = await _audioRecorderService.stop();
      if (audio == null) {
        throw const RecorderException(
          'missing_file',
          'No audio file was created.',
        );
      }
      path = audio.path;
      setState(() {
        _voicePhase = _VoiceDraftPhase.transcribing;
        _voiceStatus = context.l10n.usualFoodsVoiceTranscribingStatus;
      });
      final transcript = await viewModel.transcribeUsualFoodAudio(File(path));
      if (!mounted) return;
      setState(() {
        _transcript = transcript;
        _voicePhase = _VoiceDraftPhase.drafting;
        _voiceStatus = context.l10n.usualFoodsVoiceDraftingStatus;
      });
      final draft = await viewModel.draftUsualFood(transcript);
      if (!mounted) return;
      setState(() {
        _applyDraft(draft);
        _voicePhase = _VoiceDraftPhase.idle;
        _voiceStatus = draft.missingRequiredFields.isEmpty
            ? context.l10n.usualFoodsDraftApplied
            : context.l10n.usualFoodsDraftMissingFields;
        _voiceStatusIsError = false;
      });
    } on RecorderException catch (error) {
      if (!mounted) return;
      setState(() {
        _voicePhase = _VoiceDraftPhase.error;
        _voiceStatus = error.message ??
            userVisibleErrorMessage(
              error,
              context: UserErrorContext.voiceRecording,
            );
        _voiceStatusIsError = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _voicePhase = _VoiceDraftPhase.error;
        _voiceStatus = userVisibleErrorMessage(
          error,
          context: UserErrorContext.voiceTranscription,
        );
        _voiceStatusIsError = true;
      });
    } finally {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {
          // Temporary audio cleanup is best effort.
        }
      }
    }
  }

  void _applyDraft(UsualFoodDraft draft) {
    _setTextIfPresent(_nameController, draft.name);
    _setTextIfPresent(_brandController, draft.brand);
    if (draft.canonicalName != null && draft.canonicalName!.trim().isNotEmpty) {
      _canonicalName = draft.canonicalName!.trim();
    }
    _setTextIfPresent(_barcodeController, draft.barcode);
    if (draft.aliases.isNotEmpty) {
      _aliasesController.text = draft.aliases.join(', ');
    }
    _setNumberIfPresent(_servingGramsController, draft.servingGrams);
    if (draft.calories != null) {
      _caloriesController.text = draft.calories.toString();
    }
    _setNumberIfPresent(_proteinController, draft.proteinGrams);
    _setNumberIfPresent(_carbsController, draft.carbsGrams);
    _setNumberIfPresent(_fatController, draft.fatGrams);
    _setNutrientIfPresent(_saltController, draft, 'saltGrams');
    _setNutrientIfPresent(_sodiumController, draft, 'sodiumMilligrams');
    _setNutrientIfPresent(_fiberController, draft, 'fiberGrams');
    _setNutrientIfPresent(_sugarsController, draft, 'sugarsGrams');
    _setTextIfPresent(
      _servingDescriptionController,
      draft.nutrients['servingDescription']?.toString(),
    );
  }

  Future<void> _submit(
    MealTemplatesViewModel viewModel,
    UsualFood? food,
  ) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final input = UsualFoodInput(
      name: _nameController.text.trim(),
      brand: _optionalTrimmed(_brandController.text),
      canonicalName: _canonicalName,
      barcode: _optionalTrimmed(_barcodeController.text),
      aliases: _aliasesController.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      servingGrams: _parseDouble(_servingGramsController.text)!,
      nutrition: NutritionSnapshot(
        calories: int.parse(_caloriesController.text.trim()),
        proteinGrams: _parseDouble(_proteinController.text)!,
        carbsGrams: _parseDouble(_carbsController.text)!,
        fatGrams: _parseDouble(_fatController.text)!,
      ),
      nutrients: _nutrientsJson(),
    );
    if (food == null) {
      await viewModel.createUsualFood(input);
    } else {
      await viewModel.updateUsualFood(food, input);
    }
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (viewModel.error == null) {
      _leaveEditor();
    }
  }

  void _leaveEditor() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/templates');
    }
  }

  Map<String, Object?> _nutrientsJson() {
    final nutrients = <String, Object?>{};
    _putOptionalNumber(nutrients, 'saltGrams', _saltController.text);
    _putOptionalNumber(nutrients, 'sodiumMilligrams', _sodiumController.text);
    _putOptionalNumber(nutrients, 'fiberGrams', _fiberController.text);
    _putOptionalNumber(nutrients, 'sugarsGrams', _sugarsController.text);
    final servingDescription = _optionalTrimmed(
      _servingDescriptionController.text,
    );
    if (servingDescription != null) {
      nutrients['servingDescription'] = servingDescription;
    }
    return nutrients;
  }

  String? _requiredTextValidator(String? value) {
    if ((value ?? '').trim().isEmpty) {
      return context.l10n.usualFoodsRequiredFieldError;
    }
    return null;
  }

  String? _positiveNumberValidator(String? value, AppLocalizations l10n) {
    final parsed = _parseDouble(value);
    if (parsed == null || parsed <= 0) {
      return l10n.usualFoodsPositiveNumberError;
    }
    return null;
  }

  String? _nonNegativeIntegerValidator(String? value, AppLocalizations l10n) {
    final parsed = int.tryParse((value ?? '').trim());
    if (parsed == null || parsed < 0) {
      return l10n.usualFoodsNonNegativeNumberError;
    }
    return null;
  }

  String? _nonNegativeNumberValidator(String? value, AppLocalizations l10n) {
    final parsed = _parseDouble(value);
    if (parsed == null || parsed < 0) {
      return l10n.usualFoodsNonNegativeNumberError;
    }
    return null;
  }

  String? _optionalNumberValidator(String? value, AppLocalizations l10n) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return null;
    final parsed = _parseDouble(trimmed);
    if (parsed == null || parsed < 0) {
      return l10n.usualFoodsNonNegativeNumberError;
    }
    return null;
  }
}

class _VoiceDraftCard extends StatelessWidget {
  const _VoiceDraftCard({
    required this.phase,
    required this.transcript,
    required this.status,
    required this.statusIsError,
    required this.onPressed,
  });

  final _VoiceDraftPhase phase;
  final String? transcript;
  final String? status;
  final bool statusIsError;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.freshPalette;
    final isRecording = phase == _VoiceDraftPhase.recording;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isBusy = phase == _VoiceDraftPhase.requestingPermission ||
        phase == _VoiceDraftPhase.stopping ||
        phase == _VoiceDraftPhase.transcribing ||
        phase == _VoiceDraftPhase.drafting;
    return FreshCard(
      color: isRecording
          ? isDark
              ? palette.limeWash
              : palette.limeSoft
          : palette.surface,
      radius: FreshRadii.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FreshIconChip(
                icon: isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                color: isRecording ? palette.coral : palette.limeDeep,
                backgroundColor:
                    isRecording ? palette.surface : palette.limeWash,
              ),
              const SizedBox(width: FreshSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.usualFoodsVoiceDraftTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: FreshSpacing.xs),
                    Text(
                      l10n.usualFoodsVoiceDraftMessage,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: FreshSpacing.md),
          FilledButton.icon(
            key: const ValueKey('usual_food_voice_draft_button'),
            onPressed: onPressed,
            icon: isBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(isRecording ? Icons.stop_rounded : Icons.mic_rounded),
            label: Text(
              isRecording
                  ? l10n.usualFoodsVoiceStopButton
                  : l10n.usualFoodsVoiceRecordButton,
            ),
          ),
          if (status != null) ...[
            const SizedBox(height: FreshSpacing.md),
            Text(
              status!,
              key: const ValueKey('usual_food_voice_status'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: statusIsError
                        ? Theme.of(context).colorScheme.error
                        : palette.inkSoft,
                  ),
            ),
          ],
          if (transcript != null && transcript!.trim().isNotEmpty) ...[
            const SizedBox(height: FreshSpacing.md),
            DecoratedBox(
              key: const ValueKey('usual_food_transcript_card'),
              decoration: BoxDecoration(
                color: isDark ? palette.surfaceMuted : palette.surfaceSoft,
                borderRadius: BorderRadius.circular(FreshRadii.md),
                border: Border.all(color: palette.ruleSoft),
              ),
              child: Padding(
                padding: const EdgeInsets.all(FreshSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.usualFoodsTranscriptLabel,
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: palette.inkMuted),
                    ),
                    const SizedBox(height: FreshSpacing.xs),
                    SelectableText(
                      transcript!,
                      key: const ValueKey('usual_food_transcript_text'),
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: palette.inkSoft),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VoiceDraftBlockingOverlay extends StatelessWidget {
  const _VoiceDraftBlockingOverlay({required this.message});

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
                  key: const ValueKey('usual_food_voice_blocking_message'),
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

class _EditorSection extends StatelessWidget {
  const _EditorSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return FreshCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FreshIconChip(
                icon: icon,
                color: palette.leaf,
                backgroundColor: palette.limeWash,
              ),
              const SizedBox(width: FreshSpacing.md),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: FreshSpacing.lg),
          child,
        ],
      ),
    );
  }
}

class _OptionalNutrientsSection extends StatelessWidget {
  const _OptionalNutrientsSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return FreshCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('usual_food_optional_nutrients_section'),
          tilePadding: const EdgeInsets.symmetric(
            horizontal: FreshSpacing.lg,
            vertical: FreshSpacing.sm,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          leading: FreshIconChip(
            icon: Icons.tune_rounded,
            color: palette.orange,
            backgroundColor: palette.yellow,
          ),
          title: Text(
            context.l10n.usualFoodsOptionalSectionTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            context.l10n.usualFoodsOptionalSectionSubtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.inkMuted),
          ),
          children: children,
        ),
      ),
    );
  }
}

class _TwoColumnFields extends StatelessWidget {
  const _TwoColumnFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(children: children);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(child: children[index]),
              if (index != children.length - 1)
                const SizedBox(width: FreshSpacing.md),
            ],
          ],
        );
      },
    );
  }
}

class _MacroGrid extends StatelessWidget {
  const _MacroGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 4 : 2;
        final itemWidth =
            (constraints.maxWidth - FreshSpacing.md * (columns - 1)) / columns;
        return Wrap(
          spacing: FreshSpacing.md,
          runSpacing: FreshSpacing.sm,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _BottomSaveBar extends StatelessWidget {
  const _BottomSaveBar({
    required this.isSaving,
    required this.isEditing,
    required this.onCancel,
    required this.onSave,
  });

  final bool isSaving;
  final bool isEditing;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.screen,
        boxShadow: [
          BoxShadow(
            color: palette.ink.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: isSaving ? null : onCancel,
                child: Text(context.l10n.commonCancel),
              ),
            ),
            const SizedBox(width: FreshSpacing.md),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                key: const ValueKey('usual_food_save_button'),
                onPressed: isSaving ? null : onSave,
                icon: isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  isEditing
                      ? context.l10n.commonSave
                      : context.l10n.commonCreate,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotFoundState extends StatelessWidget {
  const _NotFoundState({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: FreshEmptyState(
        icon: Icons.search_off_rounded,
        title: context.l10n.usualFoodsNotFoundTitle,
        message: context.l10n.usualFoodsNotFoundMessage,
      ),
    );
  }
}

void _setTextIfPresent(TextEditingController controller, String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return;
  controller.text = trimmed;
}

void _setNumberIfPresent(TextEditingController controller, num? value) {
  if (value == null) return;
  controller.text = _formatQuantity(value.toDouble());
}

void _setNutrientIfPresent(
  TextEditingController controller,
  UsualFoodDraft draft,
  String key,
) {
  final value = draft.nutrients[key];
  if (value is num) {
    controller.text = _formatQuantity(value.toDouble());
  }
}

String? _optionalTrimmed(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double? _parseDouble(String? value) {
  final normalized = (value ?? '').trim().replaceAll(',', '.');
  return double.tryParse(normalized);
}

void _putOptionalNumber(
  Map<String, Object?> nutrients,
  String key,
  String value,
) {
  final parsed = _parseDouble(value);
  if (parsed != null) nutrients[key] = parsed;
}

String _formatOptionalNutrient(UsualFood? food, String key) {
  final value = food?.nutrients[key];
  if (value is num) return _formatQuantity(value.toDouble());
  return '';
}

String _formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
