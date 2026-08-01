import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/nutrition_repository.dart';
import '../../../../domain/models/nutrition_models.dart';
import '../../../../l10n/app_localizations_context.dart';
import '../../../core/design_system.dart';
import '../../../core/motion.dart';
import '../../../core/user_visible_error.dart';
import '../../../core/voice_action_button.dart';
import '../../meal_templates/views/meal_template_editor_screen.dart';
import '../../meal_templates/views/usual_food_editor_screen.dart';
import '../../meal_templates/views/usual_food_scan_screen.dart';
import '../view_models/agent_chat_view_model.dart';

class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({super.key});

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  final _messageController = TextEditingController();
  final _composerFocusNode = FocusNode();
  final _scrollController = ScrollController();
  String _lastScrollSignature = '';
  int _autoScrollGeneration = 0;

  static const _autoScrollPassDelays = [
    Duration.zero,
    Duration(milliseconds: 45),
    Duration(milliseconds: 110),
    Duration(milliseconds: 190),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<AgentChatViewModel>().prepareForEntry());
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _composerFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AgentChatViewModel>();
    final palette = context.freshPalette;
    final errorMessage = viewModel.errorCode == 'microphone_permission_denied'
        ? context.l10n.voiceMicrophonePermissionDenied
        : viewModel.errorMessage;
    _scheduleScrollToBottom(viewModel);
    return Scaffold(
      backgroundColor: palette.screen,
      body: Stack(
        children: [
          const Positioned.fill(child: FreshScreenBackdrop()),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                      child: FreshHeader(
                        title: context.l10n.agentChatTitle,
                        subtitle: context.l10n.agentChatSubtitle,
                        leading: FreshIconButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: context.l10n.commonBack,
                          onPressed: () => context.canPop()
                              ? context.pop()
                              : context.go('/dashboard'),
                        ),
                        actions: [
                          FreshIconButton(
                            key: const ValueKey('agent_chat_new_chat_button'),
                            icon: Icons.add_comment_rounded,
                            tooltip: context.l10n.agentChatNewChatTooltip,
                            onPressed: viewModel.isBusy || viewModel.isRecording
                                ? null
                                : () => unawaited(
                                      viewModel.startNewConversation(),
                                    ),
                          ),
                          FreshIconButton(
                            key: const ValueKey('agent_chat_history_button'),
                            icon: Icons.history_rounded,
                            tooltip: context.l10n.agentChatHistoryTooltip,
                            onPressed: () =>
                                unawaited(_showConversationHistory(context)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        key: const ValueKey('agent_chat_timeline'),
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                        children: [
                          if (errorMessage != null) ...[
                            FreshFadeSlide(
                              child: FreshStatusBanner(
                                icon: Icons.error_outline_rounded,
                                title: context.l10n.agentChatErrorTitle,
                                message: localizedPublicAiErrorMessage(
                                  context.l10n,
                                  viewModel.errorCode,
                                  fallback: errorMessage,
                                ),
                                color: palette.coral,
                              ),
                            ),
                            const SizedBox(height: FreshSpacing.md),
                          ],
                          if (viewModel.entries.isEmpty) ...[
                            FreshFadeSlide(
                              child: _AgentWelcomeCard(
                                onPromptSelected: _sendPrompt,
                              ),
                            ),
                          ] else ...[
                            for (final entry in viewModel.entries) ...[
                              FreshFadeSlide(
                                key: ValueKey('agent_timeline_${entry.id}'),
                                child: _AgentTimelineEntry(
                                  entry: entry,
                                  onProposalAction: _handleProposalAction,
                                  onMealCorrectionAction:
                                      _handleMealCorrectionAction,
                                ),
                              ),
                              const SizedBox(height: FreshSpacing.md),
                            ],
                          ],
                          if (viewModel.statusMessage != null &&
                              viewModel.isBusy) ...[
                            FreshFadeSlide(
                              key: ValueKey(
                                'agent_status_${viewModel.statusMessage}',
                              ),
                              child: _AgentStatusCard(
                                message: viewModel.statusMessage!,
                              ),
                            ),
                            const SizedBox(height: FreshSpacing.md),
                          ],
                          const SizedBox(
                            key: ValueKey('agent_chat_bottom_breathing_room'),
                            height: 72,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _AgentInputBar(
        controller: _messageController,
        viewModel: viewModel,
        focusNode: _composerFocusNode,
        onScanLabel: _scanNutritionLabel,
        onSubmitted: _sendMessage,
      ),
    );
  }

  void _scheduleScrollToBottom(AgentChatViewModel viewModel) {
    final signature = [
      for (final entry in viewModel.entries)
        '${entry.id}:${entry.text.length}:${entry.toolStatus}:${entry.result?.kind}:${entry.error ?? ''}',
      viewModel.statusMessage ?? '',
      viewModel.errorMessage ?? '',
      viewModel.errorCode ?? '',
    ].join('|');
    if (signature == _lastScrollSignature) return;
    _lastScrollSignature = signature;
    final generation = ++_autoScrollGeneration;
    for (final delay in _autoScrollPassDelays) {
      _queueAutoScrollPass(generation, delay);
    }
  }

  void _queueAutoScrollPass(int generation, Duration delay) {
    Future<void>.delayed(delay, () {
      if (!mounted || generation != _autoScrollGeneration) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _autoScrollGeneration) return;
        _scrollToCurrentBottom();
      });
    });
  }

  void _scrollToCurrentBottom() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = position.maxScrollExtent;
    final distance = target - position.pixels;
    if (distance <= 1) return;

    // Assistant markdown can grow over several layouts while the typewriter
    // reveals text. Short, repeated animations keep the viewport following the
    // newly available extent instead of waiting for the full message to finish.
    unawaited(
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _scanNutritionLabel() async {
    final ocrText = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const UsualFoodScanScreen(
          resultMode: UsualFoodScanResultMode.ocrText,
        ),
      ),
    );
    final trimmed = ocrText?.trim();
    if (!mounted || trimmed == null || trimmed.isEmpty) return;
    final prompt = context.l10n.agentChatScanLabelPrompt(trimmed);
    unawaited(context.read<AgentChatViewModel>().sendText(prompt));
  }

  void _handleProposalAction(AgentChatProposalAction action) {
    final viewModel = context.read<AgentChatViewModel>();
    if (action.type == AgentChatProposalActionType.correct) {
      viewModel.beginProposalCorrection(action);
      _composerFocusNode.requestFocus();
      return;
    }
    unawaited(viewModel.commitProposalAction(action));
  }

  void _handleMealCorrectionAction(AgentChatMealCorrectionAction action) {
    final viewModel = context.read<AgentChatViewModel>();
    if (action.type == AgentChatMealCorrectionActionType.cancel) {
      viewModel.cancelMealCorrection(action);
      return;
    }
    unawaited(viewModel.confirmMealCorrection(action));
  }

  void _sendPrompt(String prompt) {
    _messageController.text = prompt;
    _sendMessage();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    unawaited(context.read<AgentChatViewModel>().sendText(text));
  }

  Future<void> _showConversationHistory(BuildContext context) async {
    final viewModel = context.read<AgentChatViewModel>();
    unawaited(viewModel.refreshConversationHistory());
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          key: const ValueKey('agent_chat_history_sheet'),
          child: Consumer<AgentChatViewModel>(
            builder: (context, model, _) {
              final conversations = model.conversations;
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  FreshSpacing.lg,
                  0,
                  FreshSpacing.lg,
                  FreshSpacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n.agentChatHistoryTitle,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (model.isRefreshingHistory)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: FreshSpacing.md),
                    if (conversations.isEmpty && model.isLoadingHistory)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: FreshSpacing.xl,
                        ),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (conversations.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: FreshSpacing.xl,
                        ),
                        child: Text(context.l10n.agentChatHistoryEmpty),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: conversations.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: FreshSpacing.md),
                          itemBuilder: (context, index) {
                            final conversation = conversations[index];
                            return ListTile(
                              key: ValueKey('agent_chat_history_item_$index'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                conversation.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                context.l10n.agentChatHistoryUpdatedAt(
                                  _formatHistoryTime(
                                    context,
                                    conversation.updatedAt,
                                  ),
                                ),
                              ),
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                unawaited(
                                  model.loadConversation(conversation.id),
                                );
                              },
                              trailing: IconButton(
                                key: ValueKey(
                                  'agent_chat_history_delete_$index',
                                ),
                                tooltip:
                                    context.l10n.agentChatHistoryDeleteTooltip,
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () => unawaited(
                                  _confirmDeleteConversation(
                                    sheetContext,
                                    model,
                                    conversation.id,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _formatHistoryTime(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final date = MaterialLocalizations.of(context).formatShortDate(local);
    final time = TimeOfDay.fromDateTime(local).format(context);
    return '$date $time';
  }

  Future<void> _confirmDeleteConversation(
    BuildContext sheetContext,
    AgentChatViewModel model,
    String conversationId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.agentChatDeleteDialogTitle),
        content: Text(dialogContext.l10n.agentChatDeleteDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('agent_chat_delete_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.agentChatDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await model.deleteConversation(conversationId);
    if (!sheetContext.mounted || model.errorMessage != null) return;
    ScaffoldMessenger.of(sheetContext).showSnackBar(
      SnackBar(content: Text(sheetContext.l10n.agentChatDeletionAccepted)),
    );
  }
}

class _AgentWelcomeCard extends StatelessWidget {
  const _AgentWelcomeCard({required this.onPromptSelected});

  final ValueChanged<String> onPromptSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;
    final prompts = [
      context.l10n.agentChatPromptYesterday,
      context.l10n.agentChatPromptRemaining,
      context.l10n.agentChatPromptUsual,
    ];
    return Padding(
      key: const ValueKey('agent_chat_welcome_card'),
      padding: const EdgeInsets.symmetric(
        horizontal: FreshSpacing.xs,
        vertical: FreshSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, color: palette.limeDeep, size: 28),
          const SizedBox(height: FreshSpacing.sm),
          Text(
            context.l10n.agentChatWelcomeTitle,
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: FreshSpacing.sm),
          Text(
            context.l10n.agentChatWelcomeMessage,
            style: textTheme.bodyMedium?.copyWith(color: palette.inkSoft),
          ),
          const SizedBox(height: FreshSpacing.lg),
          Wrap(
            spacing: FreshSpacing.sm,
            runSpacing: FreshSpacing.sm,
            children: [
              for (final prompt in prompts)
                ActionChip(
                  label: Text(prompt),
                  onPressed: () => onPromptSelected(prompt),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgentTimelineEntry extends StatelessWidget {
  const _AgentTimelineEntry({
    required this.entry,
    required this.onProposalAction,
    required this.onMealCorrectionAction,
  });

  final AgentChatEntry entry;
  final ValueChanged<AgentChatProposalAction> onProposalAction;
  final ValueChanged<AgentChatMealCorrectionAction> onMealCorrectionAction;

  @override
  Widget build(BuildContext context) {
    return switch (entry.kind) {
      AgentChatEntryKind.user => _UserBubble(text: entry.text),
      AgentChatEntryKind.assistant => _AssistantBubble(entry: entry),
      AgentChatEntryKind.tool => _ToolCallCard(
          entry: entry,
          onProposalAction: onProposalAction,
          onMealCorrectionAction: onMealCorrectionAction,
        ),
    };
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          key: const ValueKey('agent_user_message'),
          padding: const EdgeInsets.symmetric(
            horizontal: FreshSpacing.md,
            vertical: FreshSpacing.sm,
          ),
          child: Text(
            text,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.entry});

  final AgentChatEntry entry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          key: const ValueKey('agent_assistant_message'),
          padding: const EdgeInsets.symmetric(
            horizontal: FreshSpacing.lg,
            vertical: FreshSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.text.trim().isNotEmpty)
                MarkdownBody(
                  data: entry.text,
                  selectable: false,
                  styleSheet: _agentMarkdownStyleSheet(context),
                ),
              if (entry.suggestions.isNotEmpty) ...[
                if (entry.text.trim().isNotEmpty)
                  const SizedBox(height: FreshSpacing.md),
                _AssistantSuggestionButtons(
                  entryId: entry.id,
                  suggestions: entry.suggestions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantSuggestionButtons extends StatelessWidget {
  const _AssistantSuggestionButtons({
    required this.entryId,
    required this.suggestions,
  });

  final String entryId;
  final List<AgentChatSuggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AgentChatViewModel>();
    return Wrap(
      spacing: FreshSpacing.sm,
      runSpacing: FreshSpacing.sm,
      children: [
        for (var index = 0; index < suggestions.length; index++)
          FilledButton.tonal(
            key: ValueKey('agent_chat_suggestion_$index'),
            onPressed: viewModel.isBusy
                ? null
                : () {
                    final value = suggestions[index].value;
                    viewModel.dismissSuggestions(entryId);
                    unawaited(viewModel.sendText(value));
                  },
            child: Text(suggestions[index].label),
          ),
      ],
    );
  }
}

MarkdownStyleSheet _agentMarkdownStyleSheet(BuildContext context) {
  final theme = Theme.of(context);
  final palette = context.freshPalette;
  final textTheme = theme.textTheme;
  final bodyStyle = textTheme.bodyMedium?.copyWith(
    color: palette.inkSoft,
    height: 1.35,
  );
  final headingStyle = textTheme.titleMedium?.copyWith(
    color: palette.ink,
    fontWeight: FontWeight.w800,
    height: 1.2,
  );
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: bodyStyle,
    h1: textTheme.titleLarge?.copyWith(
      color: palette.ink,
      fontWeight: FontWeight.w800,
      height: 1.2,
    ),
    h2: headingStyle,
    h3: headingStyle,
    h4: bodyStyle?.copyWith(color: palette.ink, fontWeight: FontWeight.w800),
    strong: TextStyle(color: palette.ink, fontWeight: FontWeight.w800),
    em: TextStyle(color: palette.inkSoft, fontStyle: FontStyle.italic),
    listBullet: bodyStyle,
    blockquote: bodyStyle?.copyWith(color: palette.inkSoft),
    blockquotePadding: const EdgeInsets.symmetric(
      horizontal: FreshSpacing.md,
      vertical: FreshSpacing.sm,
    ),
    blockquoteDecoration: BoxDecoration(
      color: palette.surfaceMuted,
      borderRadius: BorderRadius.circular(FreshRadii.sm),
      border: Border.all(color: palette.ruleSoft),
    ),
    code: textTheme.bodyMedium?.copyWith(
      color: palette.ink,
      backgroundColor: palette.surfaceMuted,
      fontFamily: 'monospace',
      fontSize: (textTheme.bodyMedium?.fontSize ?? 14) * 0.88,
    ),
    codeblockPadding: const EdgeInsets.all(FreshSpacing.md),
    codeblockDecoration: BoxDecoration(
      color: palette.surfaceMuted,
      borderRadius: BorderRadius.circular(FreshRadii.sm),
      border: Border.all(color: palette.ruleSoft),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: palette.rule, width: 1)),
    ),
  );
}

class _AgentStatusCard extends StatelessWidget {
  const _AgentStatusCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return FreshStatusBanner(
      key: const ValueKey('agent_chat_status_card'),
      icon: Icons.psychology_alt_rounded,
      title: message,
      color: palette.water,
    );
  }
}

class _ToolCallCard extends StatelessWidget {
  const _ToolCallCard({
    required this.entry,
    required this.onProposalAction,
    required this.onMealCorrectionAction,
  });

  final AgentChatEntry entry;
  final ValueChanged<AgentChatProposalAction> onProposalAction;
  final ValueChanged<AgentChatMealCorrectionAction> onMealCorrectionAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final toolCall = entry.toolCall;
    final status = entry.toolStatus ?? AgentChatToolStatus.running;
    final icon = switch (status) {
      AgentChatToolStatus.running => Icons.sync_rounded,
      AgentChatToolStatus.completed => Icons.check_circle_rounded,
      AgentChatToolStatus.failed => Icons.error_outline_rounded,
      AgentChatToolStatus.interrupted => Icons.pause_circle_outline_rounded,
    };
    final color = switch (status) {
      AgentChatToolStatus.running => palette.water,
      AgentChatToolStatus.completed => palette.limeDeep,
      AgentChatToolStatus.failed => palette.coral,
      AgentChatToolStatus.interrupted => palette.orange,
    };
    final summary = _visibleToolSummary(context, entry);
    return DecoratedBox(
      key: ValueKey('agent_tool_${toolCall?.id ?? entry.id}'),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: palette.ruleSoft),
          bottom: BorderSide(color: palette.ruleSoft),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: FreshSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: FreshSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        toolCall?.label ?? context.l10n.agentChatToolFallback,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (summary != null) ...[
                        const SizedBox(height: FreshSpacing.xs),
                        Text(
                          summary,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: palette.inkSoft),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (status == AgentChatToolStatus.running) ...[
              const SizedBox(height: FreshSpacing.md),
              const LinearProgressIndicator(minHeight: 3),
            ],
            if (entry.result != null) ...[
              const SizedBox(height: FreshSpacing.lg),
              FreshFadeSlide(
                key: ValueKey(
                  'agent_result_${toolCall?.id ?? entry.id}_${entry.result!.kind}',
                ),
                child: _AgentResultWidget(
                  entryId: entry.id,
                  result: entry.result!,
                  completionMessage: entry.completionMessage,
                  sourceToolCallId: toolCall?.id,
                  onProposalAction: onProposalAction,
                  onMealCorrectionAction: onMealCorrectionAction,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String? _visibleToolSummary(BuildContext context, AgentChatEntry entry) {
  if (entry.error != null || entry.errorCode != null) {
    return localizedPublicAiErrorMessage(
      context.l10n,
      entry.errorCode,
      fallback: entry.error ?? '',
    );
  }
  final summary = entry.toolCall?.summary.trim() ?? '';
  if (summary.isEmpty || _isTechnicalToolPayload(summary)) return null;
  return summary;
}

bool _isTechnicalToolPayload(String value) {
  final summary = value.trim();
  return (summary.startsWith('{') || summary.startsWith('[')) ||
      summary.contains('"actionId"') ||
      summary.contains("'actionId'");
}

class _AgentResultWidget extends StatelessWidget {
  const _AgentResultWidget({
    required this.entryId,
    required this.result,
    required this.onProposalAction,
    required this.onMealCorrectionAction,
    this.sourceToolCallId,
    this.completionMessage,
  });

  final String entryId;
  final AgentRunResult result;
  final String? sourceToolCallId;
  final ValueChanged<AgentChatProposalAction> onProposalAction;
  final ValueChanged<AgentChatMealCorrectionAction> onMealCorrectionAction;
  final String? completionMessage;

  @override
  Widget build(BuildContext context) {
    if (result.kind == 'meal_correction_preview' && result.meal != null) {
      return _MealCorrectionPreview(
        meal: result.meal!,
        entryId: entryId,
        sourceToolCallId: sourceToolCallId,
        onAction: onMealCorrectionAction,
      );
    }
    final proposal = result.proposal;
    if (proposal != null) {
      return _ProposalSummary(
        proposal: proposal,
        entryId: entryId,
        sourceToolCallId: sourceToolCallId,
        onProposalAction: onProposalAction,
      );
    }
    if (result.meal != null) return _MealSummary(meal: result.meal!);
    if (result.summary != null) {
      return _SummarySnapshot(summary: result.summary!);
    }
    if (result.remaining != null) {
      return _NutritionSnapshotGrid(snapshot: result.remaining!);
    }
    if (result.meals != null) return _MealList(meals: result.meals!);
    if (result.items != null) return _ItemList(items: result.items!);
    if (result.usualFoods != null) {
      return _UsualFoodList(foods: result.usualFoods!);
    }
    if (result.templates != null) {
      return _TemplateList(templates: result.templates!);
    }
    if (result.template != null) {
      return _TemplateDetail(template: result.template!);
    }
    if (result.usualFoodDraft != null) {
      return _UsualFoodDraftReview(
        entryId: entryId,
        draft: result.usualFoodDraft!,
        completionMessage: completionMessage,
      );
    }
    if (result.usualMealDraft != null) {
      return _UsualMealDraftReview(
        entryId: entryId,
        draft: result.usualMealDraft!,
        completionMessage: completionMessage,
      );
    }
    return Text(result.message);
  }
}

class _UsualFoodDraftReview extends StatelessWidget {
  const _UsualFoodDraftReview({
    required this.entryId,
    required this.draft,
    this.completionMessage,
  });

  final String entryId;
  final UsualFoodDraft draft;
  final String? completionMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.freshPalette;
    final title = draft.name?.trim().isNotEmpty == true
        ? draft.name!.trim()
        : l10n.agentChatUsualFoodDraftUnnamed;
    final missing = draft.missingRequiredFields
        .map((field) => _usualFoodDraftFieldLabel(context, field))
        .join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DraftHeader(
          icon: Icons.shopping_basket_rounded,
          title: l10n.agentChatUsualFoodDraftTitle,
          subtitle: l10n.agentChatUsualFoodDraftSubtitle,
        ),
        const SizedBox(height: FreshSpacing.md),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (draft.brand?.trim().isNotEmpty == true) ...[
          const SizedBox(height: FreshSpacing.xs),
          Text(
            draft.brand!.trim(),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
          ),
        ],
        const SizedBox(height: FreshSpacing.sm),
        _UsualFoodDraftMetrics(draft: draft),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: FreshSpacing.sm),
          Text(
            l10n.agentChatDraftMissingFields(missing),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.orange,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
        const SizedBox(height: FreshSpacing.md),
        if (completionMessage != null)
          FreshStatusBanner(
            icon: Icons.check_circle_rounded,
            title: completionMessage!,
            color: palette.limeDeep,
          )
        else
          FilledButton.icon(
            key: const ValueKey('agent_chat_review_usual_food_draft_button'),
            onPressed: () => unawaited(_openEditor(context)),
            icon: const Icon(Icons.edit_note_rounded),
            label: Text(l10n.agentChatReviewUsualFoodDraftAction),
          ),
      ],
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    final saved = await Navigator.of(context).push<UsualFood>(
      MaterialPageRoute(
        builder: (_) => UsualFoodEditorScreen(initialDraft: draft),
      ),
    );
    if (!context.mounted || saved == null) return;
    final message = context.l10n.agentChatUsualFoodSaved(saved.name);
    context.read<AgentChatViewModel>().markEntryCompleted(entryId, message);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _UsualMealDraftReview extends StatelessWidget {
  const _UsualMealDraftReview({
    required this.entryId,
    required this.draft,
    this.completionMessage,
  });

  final String entryId;
  final UsualMealDraft draft;
  final String? completionMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.freshPalette;
    final title = draft.title?.trim().isNotEmpty == true
        ? draft.title!.trim()
        : l10n.agentChatUsualMealDraftUnnamed;
    final missingFields = [
      if (draft.title?.trim().isNotEmpty != true) 'title',
      if (draft.items.isEmpty) 'items',
    ];
    final missing = missingFields
        .map((field) => _usualMealDraftFieldLabel(context, field))
        .join(', ');
    final nutrition =
        draft.items.isEmpty ? null : _sumMealItemNutrition(draft.items);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DraftHeader(
          icon: Icons.restaurant_menu_rounded,
          title: l10n.agentChatUsualMealDraftTitle,
          subtitle: l10n.agentChatUsualMealDraftSubtitle,
        ),
        const SizedBox(height: FreshSpacing.md),
        if (nutrition != null)
          _NutritionHeader(title: title, nutrition: nutrition)
        else
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        if (draft.items.isNotEmpty) ...[
          const SizedBox(height: FreshSpacing.md),
          _ItemList(items: draft.items),
        ],
        if (missing.isNotEmpty) ...[
          const SizedBox(height: FreshSpacing.sm),
          Text(
            l10n.agentChatDraftMissingFields(missing),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.orange,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
        const SizedBox(height: FreshSpacing.md),
        if (completionMessage != null)
          FreshStatusBanner(
            icon: Icons.check_circle_rounded,
            title: completionMessage!,
            color: palette.limeDeep,
          )
        else
          FilledButton.icon(
            key: const ValueKey('agent_chat_review_usual_meal_draft_button'),
            onPressed: () => unawaited(_openEditor(context)),
            icon: const Icon(Icons.edit_note_rounded),
            label: Text(l10n.agentChatReviewUsualMealDraftAction),
          ),
      ],
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    final saved = await Navigator.of(context).push<MealTemplate>(
      MaterialPageRoute(
        builder: (_) => MealTemplateEditorScreen(initialDraft: draft),
      ),
    );
    if (!context.mounted || saved == null) return;
    final message = context.l10n.agentChatUsualMealSaved(saved.title);
    context.read<AgentChatViewModel>().markEntryCompleted(entryId, message);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DraftHeader extends StatelessWidget {
  const _DraftHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: palette.limeDeep, size: 22),
        const SizedBox(width: FreshSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: FreshSpacing.xs),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.inkMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UsualFoodDraftMetrics extends StatelessWidget {
  const _UsualFoodDraftMetrics({required this.draft});

  final UsualFoodDraft draft;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return Wrap(
      spacing: FreshSpacing.sm,
      runSpacing: FreshSpacing.sm,
      children: [
        if (draft.servingGrams != null)
          _MetricPill(
            label: context.l10n.usualFoodsServingSectionTitle,
            value: '${_grams(draft.servingGrams!)}g',
            color: palette.water,
          ),
        if (draft.calories != null)
          _MetricPill(
            label: context.l10n.commonKcal,
            value: '${draft.calories}',
            color: palette.limeDeep,
          ),
        if (draft.proteinGrams != null)
          _MetricPill(
            label: context.l10n.commonProtein,
            value: '${_grams(draft.proteinGrams!)}g',
            color: palette.coral,
          ),
        if (draft.carbsGrams != null)
          _MetricPill(
            label: context.l10n.commonCarbs,
            value: '${_grams(draft.carbsGrams!)}g',
            color: palette.orange,
          ),
        if (draft.fatGrams != null)
          _MetricPill(
            label: context.l10n.commonFat,
            value: '${_grams(draft.fatGrams!)}g',
            color: palette.leaf,
          ),
      ],
    );
  }
}

class _ProposalSummary extends StatelessWidget {
  const _ProposalSummary({
    required this.proposal,
    required this.entryId,
    required this.sourceToolCallId,
    required this.onProposalAction,
  });

  final MealProposal proposal;
  final String entryId;
  final String? sourceToolCallId;
  final ValueChanged<AgentChatProposalAction> onProposalAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NutritionHeader(title: proposal.title, nutrition: proposal.nutrition),
        const SizedBox(height: FreshSpacing.md),
        _ItemList(items: proposal.items),
        const SizedBox(height: FreshSpacing.md),
        _ProposalActions(
          proposal: proposal,
          entryId: entryId,
          sourceToolCallId: sourceToolCallId,
          onProposalAction: onProposalAction,
        ),
      ],
    );
  }
}

class _ProposalActions extends StatelessWidget {
  const _ProposalActions({
    required this.proposal,
    required this.entryId,
    required this.sourceToolCallId,
    required this.onProposalAction,
  });

  final MealProposal proposal;
  final String entryId;
  final String? sourceToolCallId;
  final ValueChanged<AgentChatProposalAction> onProposalAction;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AgentChatViewModel>();
    final state = viewModel.proposalActionState(proposal.id);
    final conversationId = viewModel.conversationId;
    final canAct = sourceToolCallId != null &&
        conversationId != null &&
        viewModel.activeProposalId == proposal.id &&
        !viewModel.isProposalCommitted(proposal.id) &&
        state != AgentChatProposalActionState.succeeded;
    AgentChatProposalAction action(AgentChatProposalActionType type) =>
        AgentChatProposalAction(
          type: type,
          conversationId: conversationId!,
          entryId: entryId,
          sourceToolCallId: sourceToolCallId!,
          proposalId: proposal.id,
        );
    if (state == AgentChatProposalActionState.succeeded) {
      return Semantics(
        label: context.l10n.agentChatProposalSaved,
        child: Text(context.l10n.agentChatProposalSaved),
      );
    }
    final isSaving = state == AgentChatProposalActionState.saving;
    return Wrap(
      spacing: FreshSpacing.sm,
      runSpacing: FreshSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          button: true,
          label: isSaving
              ? context.l10n.agentChatProposalSaving
              : state == AgentChatProposalActionState.failed
                  ? context.l10n.agentChatProposalRetry
                  : context.l10n.agentChatProposalSave,
          child: FilledButton(
            key: ValueKey('agent_chat_proposal_save_button_${proposal.id}'),
            onPressed: canAct && !isSaving
                ? () => onProposalAction(
                      action(AgentChatProposalActionType.commit),
                    )
                : null,
            child: Text(
              isSaving
                  ? context.l10n.agentChatProposalSaving
                  : state == AgentChatProposalActionState.failed
                      ? context.l10n.agentChatProposalRetry
                      : context.l10n.agentChatProposalSave,
            ),
          ),
        ),
        Semantics(
          button: true,
          label: context.l10n.agentChatProposalCorrect,
          child: OutlinedButton(
            key: ValueKey('agent_chat_proposal_correct_button_${proposal.id}'),
            onPressed: canAct && !isSaving
                ? () => onProposalAction(
                      action(AgentChatProposalActionType.correct),
                    )
                : null,
            child: Text(context.l10n.agentChatProposalCorrect),
          ),
        ),
        if (isSaving)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        if (state == AgentChatProposalActionState.failed)
          Text(context.l10n.agentChatProposalSaveError),
      ],
    );
  }
}

class _MealSummary extends StatelessWidget {
  const _MealSummary({required this.meal});

  final Meal meal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NutritionHeader(title: meal.title, nutrition: meal.nutrition),
        const SizedBox(height: FreshSpacing.md),
        _ItemList(items: meal.items),
      ],
    );
  }
}

class _MealCorrectionPreview extends StatelessWidget {
  const _MealCorrectionPreview({
    required this.meal,
    required this.entryId,
    required this.sourceToolCallId,
    required this.onAction,
  });

  final Meal meal;
  final String entryId;
  final String? sourceToolCallId;
  final ValueChanged<AgentChatMealCorrectionAction> onAction;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AgentChatViewModel>();
    final toolCallId = sourceToolCallId;
    final state = toolCallId == null
        ? AgentChatMealCorrectionActionState.failed
        : viewModel.mealCorrectionActionState(toolCallId);
    final conversationId = viewModel.conversationId;
    final isSaving = state == AgentChatMealCorrectionActionState.saving;
    final canAct = toolCallId != null &&
        conversationId != null &&
        state != AgentChatMealCorrectionActionState.succeeded &&
        state != AgentChatMealCorrectionActionState.cancelled;
    AgentChatMealCorrectionAction action(
      AgentChatMealCorrectionActionType type,
    ) =>
        AgentChatMealCorrectionAction(
          type: type,
          conversationId: conversationId!,
          entryId: entryId,
          sourceToolCallId: toolCallId!,
          mealId: meal.id,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DraftHeader(
          icon: Icons.edit_note_rounded,
          title: context.l10n.agentChatMealCorrectionPreviewTitle,
          subtitle: context.l10n.agentChatMealCorrectionPreviewSubtitle,
        ),
        const SizedBox(height: FreshSpacing.md),
        _NutritionHeader(title: meal.title, nutrition: meal.nutrition),
        const SizedBox(height: FreshSpacing.md),
        _ItemList(items: meal.items),
        const SizedBox(height: FreshSpacing.md),
        if (state == AgentChatMealCorrectionActionState.succeeded)
          FreshStatusBanner(
            key: const ValueKey('agent_chat_meal_correction_succeeded'),
            icon: Icons.check_circle_rounded,
            title: context.l10n.agentChatMealCorrectionApplied,
            color: context.freshPalette.limeDeep,
          )
        else if (state == AgentChatMealCorrectionActionState.cancelled)
          Text(
            context.l10n.agentChatMealCorrectionCancelled,
            key: const ValueKey('agent_chat_meal_correction_cancelled'),
          )
        else if (state == AgentChatMealCorrectionActionState.stale)
          FreshStatusBanner(
            key: const ValueKey('agent_chat_meal_correction_stale'),
            icon: Icons.refresh_rounded,
            title: context.l10n.agentChatMealCorrectionStale,
            color: context.freshPalette.orange,
          )
        else ...[
          Wrap(
            spacing: FreshSpacing.sm,
            runSpacing: FreshSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                button: true,
                label: isSaving
                    ? context.l10n.agentChatMealCorrectionSaving
                    : state == AgentChatMealCorrectionActionState.failed
                        ? context.l10n.agentChatMealCorrectionRetry
                        : context.l10n.agentChatMealCorrectionConfirm,
                child: FilledButton(
                  key: ValueKey(
                    'agent_chat_meal_correction_confirm_${meal.id}',
                  ),
                  onPressed: canAct && !isSaving
                      ? () => onAction(
                            action(
                              AgentChatMealCorrectionActionType.confirm,
                            ),
                          )
                      : null,
                  child: Text(
                    isSaving
                        ? context.l10n.agentChatMealCorrectionSaving
                        : state == AgentChatMealCorrectionActionState.failed
                            ? context.l10n.agentChatMealCorrectionRetry
                            : context.l10n.agentChatMealCorrectionConfirm,
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: context.l10n.agentChatMealCorrectionCancel,
                child: OutlinedButton(
                  key: ValueKey(
                    'agent_chat_meal_correction_cancel_${meal.id}',
                  ),
                  onPressed: canAct &&
                          !isSaving &&
                          state != AgentChatMealCorrectionActionState.stale
                      ? () => onAction(
                            action(AgentChatMealCorrectionActionType.cancel),
                          )
                      : null,
                  child: Text(context.l10n.agentChatMealCorrectionCancel),
                ),
              ),
              if (isSaving)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (state == AgentChatMealCorrectionActionState.failed) ...[
            const SizedBox(height: FreshSpacing.sm),
            Text(context.l10n.agentChatMealCorrectionError),
          ],
        ],
      ],
    );
  }
}

class _SummarySnapshot extends StatelessWidget {
  const _SummarySnapshot({required this.summary});

  final DailySummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NutritionHeader(
          title: context.l10n.agentChatConsumedToday,
          nutrition: summary.consumed,
        ),
        const SizedBox(height: FreshSpacing.md),
        _MealList(meals: summary.meals),
      ],
    );
  }
}

class _NutritionHeader extends StatelessWidget {
  const _NutritionHeader({required this.title, required this.nutrition});

  final String title;
  final NutritionSnapshot nutrition;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: FreshSpacing.sm),
        Wrap(
          spacing: FreshSpacing.sm,
          runSpacing: FreshSpacing.sm,
          children: [
            _MetricPill(
              label: context.l10n.commonKcal,
              value: '${nutrition.calories}',
              color: palette.limeDeep,
            ),
            _MetricPill(
              label: context.l10n.commonProtein,
              value: '${_grams(nutrition.proteinGrams)}g',
              color: palette.coral,
            ),
            _MetricPill(
              label: context.l10n.commonCarbs,
              value: '${_grams(nutrition.carbsGrams)}g',
              color: palette.orange,
            ),
            _MetricPill(
              label: context.l10n.commonFat,
              value: '${_grams(nutrition.fatGrams)}g',
              color: palette.leaf,
            ),
          ],
        ),
      ],
    );
  }
}

class _NutritionSnapshotGrid extends StatelessWidget {
  const _NutritionSnapshotGrid({required this.snapshot});

  final NutritionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _NutritionHeader(
      title: context.l10n.commonRemaining,
      nutrition: snapshot,
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: FreshSpacing.sm),
      child: Text(
        '$value $label',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _ItemList extends StatelessWidget {
  const _ItemList({required this.items});

  final List<MealItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Text(context.l10n.agentChatNoItems);
    return Column(
      children: [
        for (final item in items)
          _CompactRow(
            title: item.name,
            subtitle: '${_grams(item.quantity)} ${item.unit}',
            trailing: '${item.calories} ${context.l10n.commonKcal}',
          ),
      ],
    );
  }
}

class _MealList extends StatelessWidget {
  const _MealList({required this.meals});

  final List<Meal> meals;

  @override
  Widget build(BuildContext context) {
    if (meals.isEmpty) return Text(context.l10n.agentChatNoMeals);
    return Column(
      children: [
        for (final meal in meals.take(6))
          _CompactRow(
            title: meal.title,
            subtitle: meal.mealLabel?.label ??
                meal.occurredAt.toLocal().toString().substring(0, 16),
            trailing: '${meal.nutrition.calories} ${context.l10n.commonKcal}',
          ),
      ],
    );
  }
}

class _UsualFoodList extends StatelessWidget {
  const _UsualFoodList({required this.foods});

  final List<UsualFood> foods;

  @override
  Widget build(BuildContext context) {
    if (foods.isEmpty) return Text(context.l10n.agentChatNoUsualFoods);
    return Column(
      children: [
        for (final food in foods.take(6))
          _CompactRow(
            title: food.name,
            subtitle: food.brand ??
                context.l10n.usualFoodsPerServing(_grams(food.servingGrams)),
            trailing: '${food.nutrition.calories} ${context.l10n.commonKcal}',
          ),
      ],
    );
  }
}

class _TemplateList extends StatelessWidget {
  const _TemplateList({required this.templates});

  final List<MealTemplate> templates;

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) return Text(context.l10n.agentChatNoTemplates);
    return Column(
      children: [
        for (final template in templates.take(6))
          _CompactRow(
            title: template.title,
            subtitle:
                '${template.items.length} ${context.l10n.commonIngredient}',
            trailing:
                '${template.nutrition.calories} ${context.l10n.commonKcal}',
          ),
      ],
    );
  }
}

class _TemplateDetail extends StatelessWidget {
  const _TemplateDetail({required this.template});

  final MealTemplate template;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NutritionHeader(
          title: template.title,
          nutrition: template.nutrition,
        ),
        const SizedBox(height: FreshSpacing.md),
        _ItemList(items: template.items),
      ],
    );
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FreshSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: palette.inkMuted),
                ),
              ],
            ),
          ),
          Text(trailing, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _AgentInputBar extends StatelessWidget {
  const _AgentInputBar({
    required this.controller,
    required this.viewModel,
    required this.focusNode,
    required this.onScanLabel,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final AgentChatViewModel viewModel;
  final FocusNode focusNode;
  final VoidCallback onScanLabel;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final isRecording = viewModel.isRecording;
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.screen,
          border: Border(top: BorderSide(color: palette.ruleSoft)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('agent_chat_message_field'),
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  enabled: !viewModel.isBusy && !isRecording,
                  decoration: freshUnderlineInputDecoration(
                    context,
                    hintText: viewModel.isCorrectingProposal
                        ? context.l10n.agentChatProposalCorrectionHint
                        : context.l10n.agentChatInputHint,
                  ),
                  onSubmitted: (_) => onSubmitted(),
                ),
              ),
              const SizedBox(width: FreshSpacing.sm),
              IconButton(
                key: const ValueKey('agent_chat_scan_label_button'),
                tooltip: context.l10n.agentChatScanLabelTooltip,
                onPressed: viewModel.isBusy || isRecording ? null : onScanLabel,
                icon: const Icon(Icons.document_scanner_outlined),
              ),
              const SizedBox(width: FreshSpacing.sm),
              IconButton(
                key: const ValueKey('agent_chat_mic_button'),
                tooltip: isRecording
                    ? context.l10n.agentChatStopRecording
                    : context.l10n.agentChatStartRecording,
                onPressed: viewModel.isBusy
                    ? null
                    : () {
                        if (!isRecording) VoiceActionHaptics.recordingStarted();
                        if (isRecording) VoiceActionHaptics.recordingStopped();
                        unawaited(viewModel.toggleRecording());
                      },
                color: isRecording ? palette.coral : palette.inkSoft,
                icon: Icon(
                  isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                ),
              ),
              const SizedBox(width: FreshSpacing.sm),
              IconButton(
                key: const ValueKey('agent_chat_send_button'),
                onPressed: viewModel.isBusy || isRecording ? null : onSubmitted,
                color: palette.limeDeep,
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

NutritionSnapshot _sumMealItemNutrition(List<MealItem> items) {
  return NutritionSnapshot(
    calories: items.fold<int>(0, (total, item) => total + item.calories),
    proteinGrams: items.fold<double>(
      0,
      (total, item) => total + item.proteinGrams,
    ),
    carbsGrams: items.fold<double>(0, (total, item) => total + item.carbsGrams),
    fatGrams: items.fold<double>(0, (total, item) => total + item.fatGrams),
  );
}

String _usualFoodDraftFieldLabel(BuildContext context, String field) {
  final l10n = context.l10n;
  return switch (field) {
    'name' => l10n.usualFoodsNameLabel,
    'servingGrams' => l10n.usualFoodsServingGramsLabel,
    'calories' => l10n.usualFoodsCaloriesLabel,
    'proteinGrams' => l10n.usualFoodsProteinLabel,
    'carbsGrams' => l10n.usualFoodsCarbsLabel,
    'fatGrams' => l10n.usualFoodsFatLabel,
    _ => field,
  };
}

String _usualMealDraftFieldLabel(BuildContext context, String field) {
  final l10n = context.l10n;
  return switch (field) {
    'title' => l10n.mealTemplateEditorTitleLabel,
    'items' => l10n.commonIngredient,
    _ => field,
  };
}

String _grams(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
}
