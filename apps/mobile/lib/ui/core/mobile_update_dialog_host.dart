import 'dart:async';

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

class _MobileUpdateDialogHostState extends State<MobileUpdateDialogHost>
    with WidgetsBindingObserver {
  bool _dialogOpen = false;
  bool _errorSnackScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    unawaited(
      context.read<MobileUpdateViewModel>().resumePendingInstallation(),
    );
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
      MobileUpdateFailureCode.manifestRejected ||
      MobileUpdateFailureCode.downloadRejected =>
        l10n.mobileUpdateVerificationFailed,
      MobileUpdateFailureCode.downloadFailed => l10n.mobileUpdateDownloadFailed,
      MobileUpdateFailureCode.installPermissionDenied =>
        l10n.mobileUpdatePermissionDenied,
      MobileUpdateFailureCode.installFailed => l10n.mobileUpdateInstallFailed,
      MobileUpdateFailureCode.installPermissionRequired ||
      MobileUpdateFailureCode.checkUnavailable =>
        null,
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
        return Consumer<MobileUpdateViewModel>(
          builder: (context, viewModel, _) {
            final progress = viewModel.downloadProgress;
            final waitingForPermission = viewModel.awaitingInstallPermission;
            final busy = viewModel.opening || waitingForPermission;
            return AlertDialog(
              key: const ValueKey('mobile_update_dialog'),
              icon: const Icon(Icons.system_update_alt_rounded),
              title: Text(l10n.mobileUpdateTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.mobileUpdateMessage),
                  if (waitingForPermission) ...[
                    const SizedBox(height: 16),
                    Text(
                      l10n.mobileUpdatePermissionInstructions,
                      key: const ValueKey(
                        'mobile_update_permission_instructions',
                      ),
                    ),
                  ] else if (viewModel.opening) ...[
                    const SizedBox(height: 16),
                    Text(
                      progress == null
                          ? l10n.mobileUpdatePreparing
                          : progress < 1
                              ? l10n.mobileUpdateDownloading
                              : l10n.mobileUpdateVerifying,
                      key: const ValueKey('mobile_update_progress_label'),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      key: const ValueKey('mobile_update_progress'),
                      value: progress,
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  key: const ValueKey('mobile_update_later_button'),
                  onPressed: busy ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.mobileUpdateLater),
                ),
                FilledButton.icon(
                  key: const ValueKey('mobile_update_now_button'),
                  onPressed: busy ? null : viewModel.openUpdate,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(l10n.mobileUpdateNow),
                ),
              ],
            );
          },
        );
      },
    );
    _dialogOpen = false;
  }
}
