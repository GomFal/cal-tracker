// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Better Calories';

  @override
  String get fallbackUserName => 'Cal Tracker';

  @override
  String get routeNotFound => 'Route not found';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonSave => 'Save';

  @override
  String get commonCreate => 'Create';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get commonUpdate => 'Update';

  @override
  String get commonCalories => 'Calories';

  @override
  String get commonProtein => 'Protein';

  @override
  String get commonCarbs => 'Carbs';

  @override
  String get commonFat => 'Fat';

  @override
  String get commonIngredient => 'Ingredient';

  @override
  String get commonAmount => 'Amount';

  @override
  String get commonUnit => 'Unit';

  @override
  String get commonMeal => 'Meal';

  @override
  String get commonMeals => 'Meals';

  @override
  String get commonRemaining => 'Remaining';

  @override
  String get commonConsumed => 'Consumed';

  @override
  String get commonToday => 'Today';

  @override
  String get commonKcal => 'Kcal';

  @override
  String get commonAddIngredient => 'Add ingredient';

  @override
  String get commonEditIngredients => 'Edit ingredients';

  @override
  String get commonSaveEdits => 'Save edits';

  @override
  String get commonDeleteIngredient => 'Delete ingredient';

  @override
  String get commonCheckIngredientDetails => 'Check ingredient details';

  @override
  String get commonIngredientDetailsError =>
      'Each ingredient needs a name, amount, unit, calories, and non-negative macros.';

  @override
  String get commonAddAtLeastOneIngredient => 'Add at least one ingredient.';

  @override
  String caloriesValue(int calories) {
    return '$calories Kcal';
  }

  @override
  String macroGramsValue(String value) {
    return '$value g';
  }

  @override
  String quantityUnitValue(String quantity, String unit) {
    return '$quantity $unit';
  }

  @override
  String get navHome => 'Home';

  @override
  String get navStats => 'Stats';

  @override
  String get navLog => 'Log';

  @override
  String get navUsual => 'Usual';

  @override
  String get navMenu => 'Menu';

  @override
  String get authNameLabel => 'Name';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authCreateAccountButton => 'Create account';

  @override
  String get authGetStartedButton => 'Get Started';

  @override
  String get authUseExistingAccountButton => 'Use existing account';

  @override
  String get authCreateAccountLink => 'Create an account';

  @override
  String get authContinueWithGoogleButton => 'Continue with Google';

  @override
  String get authSignInFailedTitle => 'Sign in failed';

  @override
  String get authHeroHeadline => 'Track your\ncalories better.';

  @override
  String get darkModeSwitchToLight => 'Switch to light mode';

  @override
  String get darkModeSwitchToDark => 'Switch to dark mode';

  @override
  String get settingsTitle => 'Menu';

  @override
  String get settingsSubtitle => 'Account and preferences';

  @override
  String get settingsMoreTooltip => 'More';

  @override
  String get settingsCouldNotUpdateGoals => 'Could not update goals';

  @override
  String get settingsHydrationGoal => 'Hydration goal';

  @override
  String settingsHydrationGoalSubtitle(int glasses) {
    return '$glasses glasses per day';
  }

  @override
  String get settingsCalorieTarget => 'Calorie target';

  @override
  String settingsCalorieTargetSubtitle(int calories) {
    return '$calories Kcal daily target';
  }

  @override
  String get settingsGlassesUnit => 'glasses';

  @override
  String get settingsLogOut => 'Log out';

  @override
  String settingsGoalRangeError(int min, int max) {
    return 'Enter $min-$max.';
  }

  @override
  String get settingsLanguageTitle => 'Language';

  @override
  String get settingsLanguageSubtitleEnglish => 'English';

  @override
  String get settingsLanguageSubtitleSpanish => 'Español';

  @override
  String get settingsLanguageSheetTitle => 'Choose language';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageSpanish => 'Español';

  @override
  String get settingsDataSourcesTitle => 'Data sources';

  @override
  String get settingsDataSourcesSubtitle =>
      'Food matches can include public reference data.';

  @override
  String get settingsDataSourcesOpenFoodFacts =>
      'Contains information from Open Food Facts, made available under ODbL 1.0. © Open Food Facts contributors.';

  @override
  String get settingsDataSourcesUsda =>
      'USDA FoodData Central data is public domain under CC0 1.0.';

  @override
  String get dashboardCouldNotLoadToday => 'Could not load today';

  @override
  String get dashboardGreetingMorning => 'Good morning!';

  @override
  String get dashboardGreetingAfternoon => 'Good afternoon!';

  @override
  String get dashboardGreetingNight => 'Good night!';

  @override
  String get dashboardDailyProgress => 'Your Daily\nProgress';

  @override
  String get dashboardTodayCalories => 'Today\'s Calories';

  @override
  String get dashboardCaloriesLeft => 'left';

  @override
  String dashboardGoalLine(int calories, int glasses) {
    return 'Target $calories Kcal, $glasses glasses';
  }

  @override
  String get dashboardTodayLower => 'today';

  @override
  String get dashboardNoMealsLoggedToday => 'No meals logged today';

  @override
  String get dashboardNoMealsMessage => 'Logged meals will appear here.';

  @override
  String get dashboardEditIngredientsTooltip => 'Edit ingredients';

  @override
  String get monthJan => 'Jan';

  @override
  String get monthFeb => 'Feb';

  @override
  String get monthMar => 'Mar';

  @override
  String get monthApr => 'Apr';

  @override
  String get monthMay => 'May';

  @override
  String get monthJun => 'Jun';

  @override
  String get monthJul => 'Jul';

  @override
  String get monthAug => 'Aug';

  @override
  String get monthSep => 'Sep';

  @override
  String get monthOct => 'Oct';

  @override
  String get monthNov => 'Nov';

  @override
  String get monthDec => 'Dec';

  @override
  String get dayMon => 'Mon';

  @override
  String get dayTue => 'Tue';

  @override
  String get dayWed => 'Wed';

  @override
  String get dayThu => 'Thu';

  @override
  String get dayFri => 'Fri';

  @override
  String get daySat => 'Sat';

  @override
  String get daySun => 'Sun';

  @override
  String get historyTitle => 'Stats';

  @override
  String get historySubtitle => 'Calories and meal history';

  @override
  String get historyCouldNotLoadHistory => 'Could not load history';

  @override
  String get historyLoggedMeals => 'Logged meals';

  @override
  String historyMealCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count meals',
      one: '1 meal',
      zero: '0 meals',
    );
    return '$_temp0';
  }

  @override
  String get historyNoMealsLogged => 'No meals logged';

  @override
  String get historyNoMealsMessage => 'Meal details will appear after logging.';

  @override
  String get historyDeleteMealTitle => 'Delete meal?';

  @override
  String historyTargetCalories(int calories) {
    return 'Target: $calories Kcal';
  }

  @override
  String historySelectDaySemantics(String label) {
    return 'Select $label';
  }

  @override
  String get templatesTitle => 'Usual meals';

  @override
  String get templatesSubtitle => 'Safe familiar templates';

  @override
  String get templatesAddTooltip => 'Add usual meal';

  @override
  String get templatesExplainer =>
      'Usual meals are trusted meals you can log quickly.';

  @override
  String get templatesCouldNotLoad => 'Could not load usual meals';

  @override
  String get templatesNoUsualMealsYet => 'No usual meals yet';

  @override
  String get templatesNoUsualMealsMessage => 'Saved meals will appear here.';

  @override
  String get templatesDeleteUsualMealTitle => 'Delete usual meal?';

  @override
  String get templatesNewUsualMealTitle => 'New usual meal';

  @override
  String get templatesTitleLabel => 'Title';

  @override
  String get templatesAliasesLabel => 'Aliases, separated by commas';

  @override
  String get templatesNoAliasesYet => 'No aliases yet';

  @override
  String get voiceTitle => 'Log meal';

  @override
  String get voiceStartOver => 'Start over';

  @override
  String get voiceMealFieldLabel => 'Meal';

  @override
  String get voiceMealFieldHint => 'Tell me what you ate';

  @override
  String get voiceSubmitMeal => 'Submit meal';

  @override
  String get voiceTranscribingTitle => 'Transcribing...';

  @override
  String get voiceTranscribingMessage =>
      'Listening back and preparing the text.';

  @override
  String get voiceClarificationTitle => 'Needs a little more detail';

  @override
  String get voiceClarificationDefault =>
      'Add a bit more detail and submit again.';

  @override
  String get voiceFoodMatches => 'Food matches';

  @override
  String get voiceNoConfidentMatchYet => 'No confident match yet';

  @override
  String get voiceRecordingTitle => 'Recording';

  @override
  String get voiceIntakeTitle => 'Voice intake';

  @override
  String get voiceTapStopWhenDone => 'Tap stop when you are done.';

  @override
  String get voiceSayMealNaturally => 'Say your meal naturally.';

  @override
  String get voiceMealFilledWithVoice =>
      'The meal will be filled with your voice.';

  @override
  String get voiceStopRecordingTooltip => 'Stop recording';

  @override
  String get voiceRecordVoiceTooltip => 'Record voice';

  @override
  String get voiceRecordingIndicator => 'Recording. Tap stop when you finish.';

  @override
  String get voiceErrorTitle => 'Something went wrong';

  @override
  String get voiceLoggedMessage => 'Logged. You can correct it from history.';

  @override
  String get voiceMessageMealLogged => 'Meal logged.';

  @override
  String get voiceMessageProposalUpdated => 'Proposal updated.';

  @override
  String get voiceMessageMealProposalCreated => 'Meal proposal created.';

  @override
  String get voiceTodaySection => 'Today';

  @override
  String get voiceMealsSection => 'Meals';

  @override
  String get voiceNutritionMatchesSection => 'Nutrition matches';

  @override
  String get voiceUsualMealsSection => 'Usual meals';

  @override
  String get voiceNoMealsYet => 'No meals yet';

  @override
  String get voiceNoMealsMessage => 'Logged meals will appear here.';

  @override
  String voiceItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: '0 items',
    );
    return '$_temp0';
  }

  @override
  String get voiceStateListening => 'Listening';

  @override
  String get voiceStateSavingAudio => 'Saving audio';

  @override
  String get voiceStateWhisperTranscription => 'Whisper transcription';

  @override
  String get voiceStateTranscriptReady => 'Transcript ready';

  @override
  String get voiceStateBuildingProposal => 'Building proposal';

  @override
  String get voiceStateReviewMeal => 'Review meal';

  @override
  String get voiceStateLogged => 'Logged';

  @override
  String get voiceStateResultReady => 'Result ready';

  @override
  String get voiceStateClarification => 'Clarification';

  @override
  String get voiceStateNeedsAttention => 'Needs attention';

  @override
  String get voiceStateInput => 'Voice or text input';

  @override
  String get mealLabelQuestion => 'Which type of meal is this?';

  @override
  String get mealLabelHelper => 'This helps organize your day.';

  @override
  String get mealLabelBreakfast => 'Breakfast';

  @override
  String get mealLabelLunch => 'Lunch';

  @override
  String get mealLabelDinner => 'Dinner';

  @override
  String get mealLabelSnack => 'Snack';

  @override
  String get mealLabelPreWorkout => 'Pre-workout';

  @override
  String get mealLabelPostWorkout => 'Post-workout';

  @override
  String get mealLabelOther => 'Other';

  @override
  String get mealLabelNone => 'None';

  @override
  String get mealLabelCustomType => 'Custom meal type';

  @override
  String get mealLabelOtherPlaceholder => 'Brunch';

  @override
  String get mealLabelSave => 'Save label';

  @override
  String get mealLabelSkip => 'Skip';

  @override
  String get mealProposalReadyToLog => 'Ready to log';

  @override
  String get mealProposalConfirm => 'Confirm';

  @override
  String get mealConfirmationEmbedded =>
      'Meal confirmation is embedded in the logging flow.';
}
