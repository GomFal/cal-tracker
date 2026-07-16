import 'package:cal_tracker_mobile/l10n/generated/app_localizations.dart';
import 'package:cal_tracker_mobile/ui/core/user_visible_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public AI error codes map to precise English and Spanish copy', () {
    final english = lookupAppLocalizations(const Locale('en'));
    final spanish = lookupAppLocalizations(const Locale('es'));

    expect(
      localizedPublicAiErrorMessage(
        english,
        'provider_unavailable',
        fallback: 'ignored server text',
      ),
      'The nutrition assistant is temporarily unavailable. Try again shortly.',
    );
    expect(
      localizedPublicAiErrorMessage(
        spanish,
        'provider_unavailable',
        fallback: 'ignored server text',
      ),
      'El asistente de nutrición no está disponible temporalmente. '
          'Inténtalo de nuevo en breve.',
    );
    expect(
      localizedPublicAiErrorMessage(
        spanish,
        'rate_limit_exceeded',
        fallback: 'ignored server text',
      ),
      'Has alcanzado el límite actual. Espera antes de volver a intentarlo.',
    );
  });
}
