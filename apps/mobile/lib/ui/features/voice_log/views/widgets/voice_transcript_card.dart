part of '../voice_log_screen.dart';

class _VoiceTranscriptCard extends StatelessWidget {
  const _VoiceTranscriptCard({required this.transcript});

  final String transcript;

  @override
  Widget build(BuildContext context) {
    final palette = context.freshPalette;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      key: const ValueKey('voice_transcript_card'),
      padding: const EdgeInsets.symmetric(
        horizontal: FreshSpacing.xs,
        vertical: FreshSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.graphic_eq_rounded, color: palette.limeDeep, size: 18),
          const SizedBox(width: FreshSpacing.sm),
          Text(
            context.l10n.voiceTranscriptHeardLabel,
            style: textTheme.labelLarge?.copyWith(
              color: palette.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: FreshSpacing.sm),
          Expanded(
            child: Text(
              transcript,
              style: textTheme.bodySmall?.copyWith(
                color: palette.inkSoft,
                height: 1.25,
                letterSpacing: 0,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
