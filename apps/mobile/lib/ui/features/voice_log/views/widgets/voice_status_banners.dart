part of '../voice_log_screen.dart';

class _ProposalChangeSuccessToast extends StatelessWidget {
  const _ProposalChangeSuccessToast();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.freshPalette;
    return DecoratedBox(
      key: const ValueKey('proposal_change_success_toast'),
      decoration: BoxDecoration(
        color: palette.limeWash,
        border: Border.all(color: palette.lime.withValues(alpha: 0.36)),
        borderRadius: BorderRadius.circular(FreshRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FreshSpacing.md,
          vertical: FreshSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, color: palette.limeDeep, size: 20),
            const SizedBox(width: FreshSpacing.sm),
            Flexible(
              child: Text(
                context.l10n.voiceChangesApplied,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return FreshStatusBanner(
      icon: Icons.info_outline_rounded,
      title: 'Update',
      message: message,
      color: context.freshPalette.water,
    );
  }
}

class _RecordingIndicator extends StatelessWidget {
  const _RecordingIndicator({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return FreshStatusBanner(
      icon: Icons.fiber_manual_record_rounded,
      title: '$minutes:$seconds',
      message: 'Recording voice input from the emulator microphone.',
      color: context.freshPalette.coral,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FreshStatusBanner(
      icon: Icons.error_outline_rounded,
      title: 'Something went wrong',
      message: message,
      color: context.freshPalette.coral,
      action: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Try again'),
      ),
    );
  }
}

class _LoggedMealBanner extends StatelessWidget {
  const _LoggedMealBanner({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return FreshStatusBanner(
      icon: Icons.check_rounded,
      title: title,
      message: context.l10n.voiceLoggedMessage,
      color: context.freshPalette.limeDeep,
    );
  }
}
