import 'dart:async';

import 'package:cal_tracker_mobile/app/mobile_update_view_model.dart';
import 'package:cal_tracker_mobile/data/services/api_config.dart';
import 'package:cal_tracker_mobile/data/services/mobile_update_service.dart';
import 'package:cal_tracker_mobile/domain/models/mobile_update_models.dart';
import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/core/mobile_update_dialog_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

typedef _DownloadBehavior = Future<void> Function(
  MobileUpdateProgressCallback? onProgress,
  bool requestInstallPermission,
);

class _ControllableUpdateService extends MobileUpdateService {
  _ControllableUpdateService({
    this.failure,
    this.downloadBehavior,
    this.permissionGranted = true,
  }) : super(
          apiConfig: const ApiConfig(
            baseUrl: ApiConfig.developmentBaseUrl,
          ),
        );

  static const manifest = MobileUpdateManifest(
    channel: 'dev',
    packageName: 'app.bettercalories.dev',
    versionName: '0.1.1',
    versionCode: 2,
    apkUrl: 'https://dev-api.bettercalories.app/apk/app-dev.apk',
    sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    sizeBytes: 123,
    publishedAt: '2026-07-16T12:00:00Z',
  );

  MobileUpdateFailureCode? failure;
  _DownloadBehavior? downloadBehavior;
  bool permissionGranted;
  int downloadCount = 0;

  @override
  Future<MobileUpdateCheck> checkForUpdate() async {
    return const MobileUpdateCheck(
      installedVersionName: '0.1.0',
      installedVersionCode: 1,
      manifest: manifest,
    );
  }

  @override
  Future<bool> canInstallPackages() async => permissionGranted;

  @override
  Future<void> downloadAndInstall(
    MobileUpdateManifest manifest, {
    MobileUpdateProgressCallback? onProgress,
    bool requestInstallPermission = true,
  }) async {
    downloadCount += 1;
    final behavior = downloadBehavior;
    if (behavior != null) {
      await behavior(onProgress, requestInstallPermission);
      return;
    }
    final code = failure;
    if (code != null) throw MobileUpdateException(code);
  }
}

Future<MobileUpdateViewModel> _pumpUpdateDialog(
  WidgetTester tester,
  _ControllableUpdateService service, {
  Locale locale = const Locale('es'),
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  final viewModel = MobileUpdateViewModel(updateService: service);
  await viewModel.checkForUpdate();

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: viewModel,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: MobileUpdateDialogHost(
          navigatorKey: navigatorKey,
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return viewModel;
}

void main() {
  testWidgets('shows download progress and blocks duplicate update taps',
      (tester) async {
    final completion = Completer<void>();
    final service = _ControllableUpdateService(
      downloadBehavior: (onProgress, requestPermission) async {
        onProgress?.call(0.4);
        await completion.future;
      },
    );
    await _pumpUpdateDialog(tester, service);

    expect(
      find.text(
        'Hay una nueva versión de BetterCalories. Descárgala e instálala '
        'de forma segura sin salir de la app.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_update_now_button')).hitTestable(),
    );
    await tester.pump();

    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('mobile_update_progress')),
    );
    expect(progress.value, 0.4);
    expect(find.text('Descargando la actualización…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('mobile_update_now_button')),
          )
          .onPressed,
      isNull,
    );
    expect(service.downloadCount, 1);

    completion.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile_update_progress')), findsNothing);
  });

  testWidgets('resumes automatically after install permission is granted',
      (tester) async {
    final service = _ControllableUpdateService(
      permissionGranted: false,
      downloadBehavior: (onProgress, requestPermission) async {
        if (requestPermission) {
          throw const MobileUpdateException(
            MobileUpdateFailureCode.installPermissionRequired,
          );
        }
      },
    );
    final viewModel = await _pumpUpdateDialog(tester, service);

    await tester.tap(
      find.byKey(const ValueKey('mobile_update_now_button')).hitTestable(),
    );
    await tester.pump();
    await tester.pump();

    expect(viewModel.awaitingInstallPermission, isTrue);
    expect(
      find.byKey(const ValueKey('mobile_update_permission_instructions')),
      findsOneWidget,
    );

    service.permissionGranted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(service.downloadCount, 2);
    expect(viewModel.awaitingInstallPermission, isFalse);
    expect(viewModel.error, isNull);
  });

  testWidgets('shows a localized safe error when download trust fails',
      (tester) async {
    final service = _ControllableUpdateService(
      failure: MobileUpdateFailureCode.downloadRejected,
    );
    await _pumpUpdateDialog(tester, service);

    await tester.tap(
      find.byKey(const ValueKey('mobile_update_now_button')).hitTestable(),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_update_error_snack_bar')),
      findsOneWidget,
    );
    expect(
      find.text(
        'No se pudo verificar esta actualización, así que se bloqueó la descarga.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('https://'), findsNothing);
  });

  testWidgets('explains a denied install permission and allows retry',
      (tester) async {
    final service = _ControllableUpdateService(
      permissionGranted: false,
      downloadBehavior: (onProgress, requestPermission) async {
        throw MobileUpdateException(
          requestPermission
              ? MobileUpdateFailureCode.installPermissionRequired
              : MobileUpdateFailureCode.installPermissionDenied,
        );
      },
    );
    final viewModel = await _pumpUpdateDialog(tester, service);

    await tester.tap(
      find.byKey(const ValueKey('mobile_update_now_button')).hitTestable(),
    );
    await tester.pump();
    await tester.pump();
    expect(viewModel.awaitingInstallPermission, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No se activó el permiso para instalar esta actualización. '
        'Pulsa Actualizar ahora para intentarlo de nuevo.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('mobile_update_now_button')),
          )
          .onPressed,
      isNotNull,
    );
  });
}
