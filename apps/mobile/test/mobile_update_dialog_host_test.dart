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

class _RejectedDownloadService extends MobileUpdateService {
  _RejectedDownloadService()
      : super(
          apiConfig: const ApiConfig(baseUrl: ApiConfig.developmentBaseUrl),
        );

  static const manifest = MobileUpdateManifest(
    channel: 'dev',
    packageName: 'app.bettercalories.dev',
    versionName: '0.1.1',
    versionCode: 2,
    apkUrl: 'https://dev-api.bettercalories.app/apk/app-dev.apk',
    publishedAt: '2026-07-16T12:00:00Z',
  );

  @override
  Future<MobileUpdateCheck> checkForUpdate() async {
    return const MobileUpdateCheck(
      installedVersionName: '0.1.0',
      installedVersionCode: 1,
      manifest: manifest,
    );
  }

  @override
  Future<void> openDownload(MobileUpdateManifest manifest) async {
    throw const MobileUpdateException(
      MobileUpdateFailureCode.downloadRejected,
    );
  }
}

void main() {
  testWidgets('shows a localized safe error when download trust fails',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final viewModel = MobileUpdateViewModel(
      updateService: _RejectedDownloadService(),
    );
    await viewModel.checkForUpdate();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('es'),
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

    expect(find.byKey(const ValueKey('mobile_update_dialog')), findsOneWidget);
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
}
