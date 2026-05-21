import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/mobile_update_view_model.dart';
import '../../l10n/app_localizations_context.dart';

class MobileUpdateDialogHost extends StatefulWidget {
  const MobileUpdateDialogHost({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;

  final Widget child;

  @override
  State<MobileUpdateDialogHost> createState() => _MobileUpdateDialogHostState();
}

class _MobileUpdateDialogHostState extends State<MobileUpdateDialogHost> {
  bool _dialogOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleDialogIfNeeded();
  }

  @override
  void didUpdateWidget(covariant MobileUpdateDialogHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleDialogIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MobileUpdateViewModel>();
    if (viewModel.shouldShowDialog) {
      _scheduleDialogIfNeeded();
    }
    return widget.child;
  }

  void _scheduleDialogIfNeeded() {
    if (_dialogOpen) return;
    final viewModel = context.read<MobileUpdateViewModel>();
    if (!viewModel.shouldShowDialog) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _showDialog());
  }

  Future<void> _showDialog() async {
    if (!mounted || _dialogOpen) return;
    final viewModel = context.read<MobileUpdateViewModel>();
    if (!viewModel.shouldShowDialog) return;
    final dialogContext = widget.navigatorKey.currentContext;
    if (dialogContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showDialog());
      return;
    }
    _dialogOpen = true;
    viewModel.markDialogHandled();
    await showDialog<void>(
      context: dialogContext,
      builder: (context) {
        final l10n = context.l10n;
        return AlertDialog(
          key: const ValueKey('mobile_update_dialog'),
          icon: const Icon(Icons.system_update_alt_rounded),
          title: Text(l10n.mobileUpdateTitle),
          content: Text(l10n.mobileUpdateMessage),
          actions: [
            TextButton(
              key: const ValueKey('mobile_update_later_button'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.mobileUpdateLater),
            ),
            FilledButton.icon(
              key: const ValueKey('mobile_update_now_button'),
              onPressed: () {
                Navigator.of(context).pop();
                viewModel.openUpdate();
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(l10n.mobileUpdateNow),
            ),
          ],
        );
      },
    );
    _dialogOpen = false;
  }
}
