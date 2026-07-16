import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/mobile_update_view_model.dart';
import '../../data/services/mobile_update_service.dart';
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
  bool _errorSnackScheduled = false;

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
    if (viewModel.error?.isUserVisible ?? false) {
      _scheduleErrorIfNeeded();
    }
    return widget.child;
  }

  void _scheduleDialogIfNeeded() {
    if (_dialogOpen) return;
    final viewModel = context.read<MobileUpdateViewModel>();
    if (!viewModel.shouldShowDialog) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _showDialog());
  }

  void _scheduleErrorIfNeeded() {
    if (_errorSnackScheduled) return;
    final error = context.read<MobileUpdateViewModel>().error;
    if (error == null || !error.isUserVisible) return;
    _errorSnackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _showError(error));
  }

  void _showError(MobileUpdateFailureCode error) {
    _errorSnackScheduled = false;
    if (!mounted) return;
    final viewModel = context.read<MobileUpdateViewModel>();
    if (viewModel.error != error) return;
    final messengerContext = widget.navigatorKey.currentContext;
    if (messengerContext == null) {
      _scheduleErrorIfNeeded();
      return;
    }
    final l10n = messengerContext.l10n;
    final message = switch (error) {
      MobileUpdateFailureCode.downloadOpenFailed => l10n.mobileUpdateOpenFailed,
      MobileUpdateFailureCode.manifestRejected ||
      MobileUpdateFailureCode.downloadRejected =>
        l10n.mobileUpdateVerificationFailed,
      MobileUpdateFailureCode.checkUnavailable => null,
    };
    viewModel.clearError(error);
    if (message == null) return;
    ScaffoldMessenger.of(messengerContext)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('mobile_update_error_snack_bar'),
          content: Text(message),
        ),
      );
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
