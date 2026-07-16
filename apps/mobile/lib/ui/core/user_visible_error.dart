import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../generated/api/cal_tracker_api.dart';
import '../../l10n/generated/app_localizations.dart';

const publicAiErrorCodes = <String>{
  'validation_error',
  'authentication_required',
  'rate_limit_exceeded',
  'provider_unavailable',
  'internal_error',
};

String? publicAiErrorCode(Object error) {
  if (error is! ApiException) return null;
  return publicAiErrorCodes.contains(error.code) ? error.code : null;
}

String localizedPublicAiErrorMessage(
  AppLocalizations l10n,
  String? code, {
  required String fallback,
}) {
  switch (code) {
    case 'validation_error':
      return l10n.aiErrorValidation;
    case 'authentication_required':
      return l10n.aiErrorAuthentication;
    case 'rate_limit_exceeded':
      return l10n.aiErrorRateLimit;
    case 'provider_unavailable':
      return l10n.aiErrorProviderUnavailable;
    case 'internal_error':
      return l10n.aiErrorInternal;
    default:
      return fallback;
  }
}

enum UserErrorContext {
  authLogin,
  authRegister,
  authGoogle,
  authEmailConfirmation,
  sessionRestore,
  dashboardLoad,
  dashboardSave,
  settingsLoad,
  settingsSave,
  mealHistoryLoad,
  mealHistorySave,
  mealTemplatesLoad,
  mealTemplatesSave,
  calorieEstimate,
  voiceRecording,
  voiceTranscription,
  voiceMeal,
  voiceAgent,
  voiceCommit,
  voiceProposalEdit,
  voiceCandidateSelection,
  usualFoodScanCamera,
  usualFoodScanOcr,
  usualFoodScanDraft,
  generic,
}

String userVisibleErrorMessage(
  Object error, {
  UserErrorContext context = UserErrorContext.generic,
}) {
  if (_isNetworkError(error)) {
    return 'We could not reach Better Calories. Check your connection and try again.';
  }

  if (error is ApiException) {
    final code = error.code;
    if (context == UserErrorContext.authLogin &&
        code == 'invalid_credentials') {
      return 'Email or password does not match.';
    }
    if (code == 'email_not_verified') {
      return 'Check your email and confirm your account before signing in.';
    }
    if (code == 'invalid_email_confirmation_token') {
      return 'That confirmation link is invalid or expired. Create your account again to get a new link.';
    }
    if (context == UserErrorContext.authGoogle ||
        code == 'invalid_google_token') {
      return 'Google sign-in did not finish. Try again.';
    }
    if (code == 'authentication_required' ||
        error.statusCode == 401 ||
        code == 'token_expired' ||
        code == 'authentication_required') {
      return 'Your session expired. Sign in again.';
    }
    if (error.statusCode == 403 || code == 'permission_denied') {
      return 'You do not have permission to do that.';
    }
    if (error.statusCode == 404 || code == 'not_found') {
      return _notFoundMessage(context);
    }
    if (error.statusCode == 413) {
      return 'That file is too large. Try a shorter recording.';
    }
    if (error.statusCode == 415) {
      return 'That file type is not supported.';
    }
    if (code == 'rate_limit_exceeded' || error.statusCode == 429) {
      return 'Too many tries. Wait a moment and try again.';
    }
    if (code == 'provider_unavailable' ||
        code == 'agent_provider_unavailable') {
      if (context == UserErrorContext.voiceAgent) {
        return 'We could not understand that meal yet. Try adding a little more detail.';
      }
      return 'The nutrition assistant is taking longer than expected. Try again or use a shorter description.';
    }
    if (code == 'validation_error' || error.statusCode == 400) {
      return _validationMessage(context);
    }
    if (error.statusCode >= 500) {
      return 'Something went wrong on our side. Try again.';
    }
  }

  return _fallbackMessage(context);
}

bool _isNetworkError(Object error) {
  return error is SocketException ||
      error is TimeoutException ||
      error is http.ClientException;
}

String _validationMessage(UserErrorContext context) {
  switch (context) {
    case UserErrorContext.authLogin:
      return 'Enter a valid email address and password.';
    case UserErrorContext.authRegister:
      return 'Check your name, email, and password, then try again.';
    case UserErrorContext.authEmailConfirmation:
      return 'Open the latest confirmation link from your email.';
    case UserErrorContext.calorieEstimate:
      return 'Check the details and try again.';
    case UserErrorContext.voiceTranscription:
    case UserErrorContext.voiceMeal:
      return 'Try a new recording and speak clearly after the recording starts.';
    default:
      return 'Check the details and try again.';
  }
}

String _notFoundMessage(UserErrorContext context) {
  switch (context) {
    case UserErrorContext.mealHistorySave:
    case UserErrorContext.voiceCommit:
    case UserErrorContext.voiceProposalEdit:
      return 'We could not find that meal. Refresh and try again.';
    case UserErrorContext.mealTemplatesSave:
      return 'We could not find that usual meal. Refresh and try again.';
    default:
      return 'We could not find that item. Refresh and try again.';
  }
}

String _fallbackMessage(UserErrorContext context) {
  switch (context) {
    case UserErrorContext.authLogin:
      return 'We could not sign you in. Try again.';
    case UserErrorContext.authRegister:
      return 'We could not create your account. Try again.';
    case UserErrorContext.authGoogle:
      return 'Google sign-in did not finish. Try again.';
    case UserErrorContext.authEmailConfirmation:
      return 'We could not confirm your email. Try the latest link again.';
    case UserErrorContext.sessionRestore:
      return 'Your session expired. Sign in again.';
    case UserErrorContext.dashboardLoad:
      return 'We could not load today. Try again.';
    case UserErrorContext.dashboardSave:
      return 'We could not save that change. Try again.';
    case UserErrorContext.settingsLoad:
      return 'We could not load settings. Try again.';
    case UserErrorContext.settingsSave:
      return 'We could not save settings. Try again.';
    case UserErrorContext.mealHistoryLoad:
      return 'We could not load meal history. Try again.';
    case UserErrorContext.mealHistorySave:
      return 'We could not update that meal. Try again.';
    case UserErrorContext.mealTemplatesLoad:
      return 'We could not load usual meals. Try again.';
    case UserErrorContext.mealTemplatesSave:
      return 'We could not update that usual meal. Try again.';
    case UserErrorContext.calorieEstimate:
      return 'We could not estimate calories. Check the details and try again.';
    case UserErrorContext.voiceRecording:
      return 'Recording failed. Try again.';
    case UserErrorContext.voiceTranscription:
      return 'We could not transcribe that audio. Try again.';
    case UserErrorContext.voiceMeal:
      return 'We could not turn that recording into a meal. Try again.';
    case UserErrorContext.voiceAgent:
      return 'We could not understand that meal yet. Try adding a little more detail.';
    case UserErrorContext.voiceCommit:
      return 'We could not log that meal. Try again.';
    case UserErrorContext.voiceProposalEdit:
      return 'We could not update that meal. Try again.';
    case UserErrorContext.voiceCandidateSelection:
      return 'We could not apply that food match. Try again.';
    case UserErrorContext.usualFoodScanCamera:
      return 'We could not start the camera. Try again or use a different device.';
    case UserErrorContext.usualFoodScanOcr:
      return 'We could not read the text on that label. Try again with a sharper photo.';
    case UserErrorContext.usualFoodScanDraft:
      return 'We could not turn that photo into a draft. Try again or fill the fields manually.';
    case UserErrorContext.generic:
      return 'We could not complete that request. Try again.';
  }
}
