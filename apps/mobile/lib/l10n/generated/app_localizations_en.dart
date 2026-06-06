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
  String get commonClose => 'Close';

  @override
  String get commonBack => 'Back';

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
  String get mealEditorMealTotal => 'Meal total';

  @override
  String get mealEditorIngredientsSection => 'Ingredients';

  @override
  String get mealEditorEditDetails => 'Edit details';

  @override
  String get mealEditorNutritionDetails => 'Nutrition details';

  @override
  String get mealEditorApplySuggestion => 'Apply suggestion';

  @override
  String mealEditorCalculatedFromMacros(int calories) {
    return 'Calculated from macros: $calories kcal';
  }

  @override
  String mealEditorMacroCaloriesShort(int calories) {
    return '$calories kcal from macros';
  }

  @override
  String get mealEditorCaloriesMismatchTitle => 'Calories differ from macros';

  @override
  String mealEditorCaloriesMismatchMessage(int calories) {
    return 'Calculated from macros: $calories kcal';
  }

  @override
  String get mealTitleListSeparator => ', ';

  @override
  String get mealTitleListFinalSeparator => ' and ';

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
  String get authCreateAccountFailedTitle => 'Account creation failed';

  @override
  String get authEmailInvalidError =>
      'Enter a valid email address, like name@example.com.';

  @override
  String get authNameRequiredError => 'Enter your name.';

  @override
  String get authPasswordRequiredError => 'Enter your password.';

  @override
  String get authPasswordTooShortError => 'Use at least 8 characters.';

  @override
  String get authHeroHeadline => 'Track your\ncalories, better.';

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
  String settingsHydrationGoalSubtitle(String liters) {
    return '$liters L per day';
  }

  @override
  String get settingsCalorieTarget => 'Calorie target';

  @override
  String settingsCalorieTargetSubtitle(int calories) {
    return '$calories Kcal daily target';
  }

  @override
  String get settingsLitersUnit => 'liters';

  @override
  String get settingsOuncesUnit => 'ounces';

  @override
  String get hydrationSheetTitle => 'Set your daily water goal';

  @override
  String get hydrationSheetSubtitle =>
      'Choose how much water you want to drink each day.';

  @override
  String get hydrationUnitTitle => 'Unit';

  @override
  String get hydrationUnitLiters => 'Liters (L)';

  @override
  String get hydrationUnitOunces => 'Ounces (fl oz)';

  @override
  String get hydrationDailyGoal => 'Daily goal';

  @override
  String get hydrationRecommendedRange => 'Recommended: 2.0 - 3.0 L';

  @override
  String get hydrationInfoTitle => 'Stay hydrated';

  @override
  String get hydrationInfoMessage =>
      'Drinking enough water helps your body function better and supports your goals.';

  @override
  String get hydrationDecreaseGoalTooltip => 'Decrease water goal';

  @override
  String get hydrationIncreaseGoalTooltip => 'Increase water goal';

  @override
  String get settingsLogOut => 'Log out';

  @override
  String settingsGoalRangeError(int min, int max) {
    return 'Enter $min-$max.';
  }

  @override
  String get settingsNotSet => 'Not set';

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
  String get settingsThemeTitle => 'Appearance';

  @override
  String get settingsThemeSheetTitle => 'Choose appearance';

  @override
  String get settingsThemeSystem => 'Device default';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

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
  String get mobileUpdateTitle => 'Please update';

  @override
  String get mobileUpdateMessage =>
      'A new BetterCalories version is available. Download the APK from your browser to update.';

  @override
  String get mobileUpdateNow => 'Update now';

  @override
  String get mobileUpdateLater => 'Later';

  @override
  String get settingsMacroRequiresCaloriesTitle => 'Set calories first';

  @override
  String get settingsMacroRequiresCaloriesMessage =>
      'Configure your daily calories before setting a macro distribution.';

  @override
  String get settingsMacroRequiresCaloriesSetNow => 'Set your calories now';

  @override
  String get settingsMacroRequiresCaloriesSkip => 'Skip for now';

  @override
  String get calorieTargetSheetTitle => 'Set your daily calories';

  @override
  String get calorieTargetSheetSubtitle =>
      'Choose the target you want to track each day.';

  @override
  String get calorieTargetCalculatorLink =>
      'Don\'t know how many calories you need?';

  @override
  String calorieTargetRangeValidationError(int min, int max) {
    return 'Enter a target from $min to $max Kcal.';
  }

  @override
  String get calorieTargetIncreaseTooltip => 'Increase';

  @override
  String get calorieTargetDecreaseTooltip => 'Decrease';

  @override
  String get calorieSetupHeadlinePrefix => 'Set up your';

  @override
  String get calorieSetupHeadlineMain => 'daily calories';

  @override
  String get calorieSetupHeadlineBadge => 'Here.';

  @override
  String get calorieCouldNotSaveCalories =>
      'Couldn\'t save your calories. Please try again.';

  @override
  String get calorieCouldNotSaveMacros =>
      'Couldn\'t save your macros. Please try again.';

  @override
  String get postCalorieSaveTitle => 'Calories saved';

  @override
  String postCalorieSaveTarget(int calories) {
    return 'Your daily target is $calories Kcal.';
  }

  @override
  String get postCalorieSaveMacroQuestion =>
      'Want to track protein, carbs and fats too?';

  @override
  String get postCalorieSaveSetMacroDistribution => 'Set macro distribution';

  @override
  String get postCalorieSaveNotNow => 'Not now';

  @override
  String get calorieMacroPromptTitle => 'Add macros?';

  @override
  String calorieMacroPromptMessage(int calories) {
    return 'Choose a simple protein, carb and fat split for $calories Kcal.';
  }

  @override
  String get calorieMacroPromptConfigure => 'Configure';

  @override
  String get calorieMacroPromptSkip => 'Skip for now';

  @override
  String get calorieCalculatorChooseYourMacrosTitle => 'Choose your macros';

  @override
  String get calorieWizardCheckDetailsTitle => 'Check your details';

  @override
  String get calorieWizardContinue => 'Continue';

  @override
  String get calorieWizardUseEstimate => 'Use this estimate';

  @override
  String get calorieWizardSexTitle => 'What is your biological sex?';

  @override
  String get calorieWizardSexSubtitle =>
      'This keeps the calorie estimate aligned with the formula.';

  @override
  String get calorieWizardSexMale => 'Male';

  @override
  String get calorieWizardSexMaleMessage => 'Use the male BMR coefficient.';

  @override
  String get calorieWizardSexFemale => 'Female';

  @override
  String get calorieWizardSexFemaleMessage => 'Use the female BMR coefficient.';

  @override
  String get calorieWizardBirthdayTitle => 'When\'s your birthday?';

  @override
  String get calorieWizardBirthdayMonth => 'Month';

  @override
  String get calorieWizardBirthdayDay => 'Day';

  @override
  String get calorieWizardBirthdayYear => 'Year';

  @override
  String get calorieWizardBirthdayValidationError =>
      'Choose a birthday for ages 18 to 100.';

  @override
  String get calorieWizardHeightTitle => 'How tall are you?';

  @override
  String get calorieWizardHeightValidationError =>
      'Enter a height from 120 to 230 cm.';

  @override
  String get calorieWizardWeightTitle => 'What\'s your current weight?';

  @override
  String get calorieWizardWeightValidationError =>
      'Enter a weight from 35 to 250 kg.';

  @override
  String get calorieWizardProfileValidationError =>
      'Enter age, height, and weight in the expected ranges.';

  @override
  String get calorieWizardGoalTitle => 'What is your main goal?';

  @override
  String get calorieWizardGoalSubtitle =>
      'Choose the outcome you want your target to support.';

  @override
  String get calorieWizardGoalLoseWeight => 'Lose Weight';

  @override
  String get calorieWizardGoalLoseWeightMessage =>
      'Estimate a deficit from maintenance.';

  @override
  String get calorieWizardGoalGainMuscle => 'Gain Muscle';

  @override
  String get calorieWizardGoalGainMuscleMessage =>
      'Estimate a controlled calorie surplus.';

  @override
  String get calorieWizardGoalMaintainWeight => 'Maintain Weight';

  @override
  String get calorieWizardGoalMaintainWeightMessage =>
      'Track around your estimated maintenance.';

  @override
  String get calorieWizardLossPaceTitle =>
      'How fast do you want to lose weight?';

  @override
  String get calorieWizardGainPaceTitle =>
      'How fast do you want to gain weight?';

  @override
  String get calorieWizardPaceSubtitle =>
      'A steadier pace is easier to sustain.';

  @override
  String get calorieWizardPaceSlow => 'Slow';

  @override
  String get calorieWizardPaceSlowMessage =>
      'Easier to maintain and better for performance.';

  @override
  String get calorieWizardPaceModerate => 'Moderate';

  @override
  String get calorieWizardPaceModerateMessage =>
      'Recommended default for most users.';

  @override
  String get calorieWizardPaceAggressive => 'Aggressive';

  @override
  String get calorieWizardLossPaceAggressiveMessage =>
      'Larger deficit. Use only if you can recover well.';

  @override
  String get calorieWizardPaceLean => 'Lean';

  @override
  String get calorieWizardPaceLeanMessage =>
      'Small surplus for minimal fat gain.';

  @override
  String get calorieWizardPaceStandard => 'Standard';

  @override
  String get calorieWizardPaceStandardMessage =>
      'Recommended default for most users gaining muscle.';

  @override
  String get calorieWizardGainPaceAggressiveMessage =>
      'Larger surplus with higher fat-gain risk.';

  @override
  String get calorieWizardActivityTitle => 'What is your activity level?';

  @override
  String get calorieWizardActivitySubtitle =>
      'Pick the option that best matches a normal week.';

  @override
  String get calorieWizardActivitySedentary => 'Sedentary';

  @override
  String get calorieWizardActivitySedentaryMessage =>
      'Mostly seated, low daily movement, and 0-1 light workouts weekly.';

  @override
  String get calorieWizardActivityLightlyActive => 'Lightly Active';

  @override
  String get calorieWizardActivityLightlyActiveMessage =>
      'Regular walks or light exercise 1-3 days per week.';

  @override
  String get calorieWizardActivityModeratelyActive => 'Moderately Active';

  @override
  String get calorieWizardActivityModeratelyActiveMessage =>
      'Training 3-5 days per week or a meaningfully active routine.';

  @override
  String get calorieWizardActivityVeryActive => 'Very Active';

  @override
  String get calorieWizardActivityVeryActiveMessage =>
      'Hard exercise most days or active work plus regular training.';

  @override
  String get calorieWizardActivitySuperActive => 'Super Active';

  @override
  String get calorieWizardActivitySuperActiveMessage =>
      'Athlete-level workload, two-a-days, or demanding physical work.';

  @override
  String get calorieWizardBackTooltip => 'Back';

  @override
  String get calorieWizardCloseTooltip => 'Close';

  @override
  String get calorieWizardLoadingTitle => 'Personalizing your calorie plan...';

  @override
  String get calorieWizardLoadingMessage =>
      'Building a target from your profile and activity.';

  @override
  String get calorieWizardResultTitle =>
      'Your personalized calorie plan is ready!';

  @override
  String get calorieWizardResultBmr => 'BMR estimate';

  @override
  String get calorieWizardResultMaintenance => 'Maintenance';

  @override
  String get calorieWizardResultTargetRange => 'Target range';

  @override
  String get calorieWizardResultAdjustment => 'Adjustment';

  @override
  String calorieWizardTargetRangeValue(int min, int max) {
    return '$min-$max Kcal';
  }

  @override
  String get calorieWizardEstimateNoteTitle => 'Estimate note';

  @override
  String get macroSheetTitle => 'Set your macros';

  @override
  String macroDailyTarget(int calories) {
    return 'Daily target: $calories Kcal';
  }

  @override
  String get macroSaveMacros => 'Save macros';

  @override
  String get macroPersonalizedTitle => 'Personalized macros';

  @override
  String get macroSavePersonalized => 'Save personalized macros';

  @override
  String get macroPercentagesTab => 'Percentages';

  @override
  String get macroGramsTab => 'Grams';

  @override
  String get macroPresetBalanced => 'Balanced';

  @override
  String get macroPresetHighProtein => 'High protein';

  @override
  String get macroPresetLowerCarb => 'Lower carb';

  @override
  String get macroPersonalized => 'Personalized';

  @override
  String get macroCreateOwnSplit => 'Create your own split';

  @override
  String get macroPercentagesOrGrams => 'Percentages or grams';

  @override
  String get macroPersonalizedPercentages => 'Personalized percentages';

  @override
  String get macroPersonalizedGrams => 'Personalized grams';

  @override
  String macroProteinPercentSummary(int percent) {
    return '$percent% protein';
  }

  @override
  String macroCarbsPercentSummary(int percent) {
    return '$percent% carbs';
  }

  @override
  String macroFatPercentSummary(int percent) {
    return '$percent% fat';
  }

  @override
  String macroProteinGramsSummary(String grams) {
    return '${grams}g protein';
  }

  @override
  String macroCarbsGramsSummary(String grams) {
    return '${grams}g carbs';
  }

  @override
  String macroFatGramsSummary(String grams) {
    return '${grams}g fat';
  }

  @override
  String macroGramTriplet(String protein, String carbs, String fat) {
    return '${protein}g · ${carbs}g · ${fat}g';
  }

  @override
  String macroPercentagesWithGramsSummary(String percentages, String grams) {
    return '$percentages ($grams)';
  }

  @override
  String get macroPercentagesMustTotal => 'Percentages must total 100%';

  @override
  String macroPercentagesTotalMessage(int total) {
    return 'These add up to $total%. Adjust one macro or reset to balanced before saving.';
  }

  @override
  String get macroAdjustProtein => 'Adjust protein';

  @override
  String get macroAdjustCarbs => 'Adjust carbs';

  @override
  String get macroAdjustFat => 'Adjust fat';

  @override
  String get macroResetBalanced => 'Reset balanced';

  @override
  String get macroGramsTooHigh => 'Macro grams are too high';

  @override
  String get macroGramsTooHighMessage =>
      'Each macro target must be 2000 g or less.';

  @override
  String get macroSmallCalorieMismatch => 'Small calorie mismatch';

  @override
  String get macroCaloriesDoNotMatch => 'Macros do not match calories';

  @override
  String macroGramMismatchOverMessage(int macroCalories, int delta) {
    return 'These grams add up to $macroCalories Kcal, $delta Kcal over your target.';
  }

  @override
  String macroGramMismatchUnderMessage(int macroCalories, int delta) {
    return 'These grams add up to $macroCalories Kcal, $delta Kcal under your target.';
  }

  @override
  String get macroUsePercentages => 'Use percentages';

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
  String dashboardGoalLine(int calories, String liters) {
    return 'Target $calories Kcal, $liters L';
  }

  @override
  String get dashboardWaterIntake => 'Water Intake';

  @override
  String dashboardWaterProgress(String consumed, String goal) {
    return '$consumed / $goal L';
  }

  @override
  String get dashboardWaterDecreaseTooltip => 'Decrease water intake';

  @override
  String get dashboardWaterIncreaseTooltip => 'Increase water intake';

  @override
  String get dashboardTodayLower => 'today';

  @override
  String get dashboardNoMealsLoggedToday => 'No meals logged today';

  @override
  String get dashboardNoMealsMessage => 'Logged meals will appear here.';

  @override
  String get dashboardEditIngredientsTooltip => 'Edit ingredients';

  @override
  String get dashboardDeleteMealTooltip => 'Delete meal';

  @override
  String get dashboardCouldNotDeleteMeal => 'Could not delete meal.';

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
  String get templatesTitle => 'Habituals';

  @override
  String get templatesSubtitle => 'Usual meals and ingredients';

  @override
  String get templatesAddTooltip => 'Add usual meal';

  @override
  String get templatesExplainer =>
      'Usual meals are trusted meals you can log quickly.';

  @override
  String get templatesNoUsualMealsYet => 'No usual meals yet';

  @override
  String get templatesNoUsualMealsMessage => 'Saved meals will appear here.';

  @override
  String get templatesDeleteUsualMealTitle => 'Delete usual meal?';

  @override
  String get templatesNoAliasesYet => 'No aliases yet';

  @override
  String get templatesCreateUnavailableTitle =>
      'Meal templates need ingredients';

  @override
  String get templatesCreateUnavailableMessage =>
      'Create usual meals from selected ingredients or a reviewed draft. Placeholder meal templates are disabled.';

  @override
  String get mealTemplateEditorCreateTitle => 'Create usual meal';

  @override
  String get mealTemplateEditorEditTitle => 'Edit usual meal';

  @override
  String get mealTemplateEditorSubtitle =>
      'Build a reviewed reusable meal. Nothing is logged to today.';

  @override
  String get mealTemplateEditorMissingTemplateTitle => 'Usual meal not found';

  @override
  String get mealTemplateEditorMissingTemplateMessage =>
      'Refresh habituals and try opening this meal again.';

  @override
  String get mealTemplateEditorDetailsSection => 'Meal details';

  @override
  String get mealTemplateEditorTitleLabel => 'Meal title';

  @override
  String get mealTemplateEditorTitleHint => 'Gym lunch';

  @override
  String get mealTemplateEditorAliasesLabel => 'Aliases';

  @override
  String get mealTemplateEditorAliasesHint =>
      'Comma-separated phrases you use by voice';

  @override
  String get bottomMicFillEditorHint => 'Use this mic to fill this screen';

  @override
  String get mealTemplateEditorCandidatesSection => 'Food matches';

  @override
  String get mealTemplateEditorCandidatesHelper =>
      'Choose a candidate when the draft needs a database match.';

  @override
  String get mealTemplateEditorNoCandidates =>
      'No candidates returned for this ingredient.';

  @override
  String get mealTemplateEditorAddFromSearch => 'Add from food search';

  @override
  String get mealTemplateEditorSaveButton => 'Save usual meal';

  @override
  String get mealTemplateEditorTitleRequired =>
      'Add a meal title before saving.';

  @override
  String get mealTemplateEditorSaveFailedTitle => 'Could not save usual meal';

  @override
  String get mealTemplateEditorSaveFailedMessage => 'Please try again.';

  @override
  String get usualsMealsTab => 'Meals';

  @override
  String get usualsIngredientsTab => 'Ingredients';

  @override
  String get usualsCouldNotLoad => 'Could not load habituals';

  @override
  String get usualFoodsAddTooltip => 'Add usual ingredient';

  @override
  String get usualFoodsExplainer =>
      'Usual ingredients are foods you enter manually so they appear first in search and meal logging.';

  @override
  String get usualFoodsEmptyTitle => 'No usual ingredients yet';

  @override
  String get usualFoodsEmptyMessage =>
      'Add foods you use often so they appear first in search and meal logging.';

  @override
  String get usualFoodsCreateTitle => 'New usual ingredient';

  @override
  String get usualFoodsEditTitle => 'Edit usual ingredient';

  @override
  String get usualFoodsDraftLabel => 'Fill from text with AI (optional)';

  @override
  String get usualFoodsDraftHint =>
      'Example: My rice per 100 g has 360 kcal, 79 g carbs, 7 g protein, 1 g fat and 0.01 g salt.';

  @override
  String get usualFoodsDraftButton => 'Fill fields';

  @override
  String get usualFoodsDraftEmptyError =>
      'Enter label text before filling fields.';

  @override
  String get usualFoodsEditorSubtitle =>
      'Review the label values before saving.';

  @override
  String get usualFoodsIdentitySectionTitle => 'Identity';

  @override
  String get usualFoodsServingSectionTitle => 'Serving';

  @override
  String get usualFoodsMacrosSectionTitle => 'Macros';

  @override
  String get usualFoodsOptionalSectionTitle => 'Optional nutrients';

  @override
  String get usualFoodsOptionalSectionSubtitle =>
      'Add label details only when you have them.';

  @override
  String get usualFoodsSaveFailedTitle => 'Could not save ingredient';

  @override
  String get usualFoodsNotFoundTitle => 'Ingredient not found';

  @override
  String get usualFoodsNotFoundMessage =>
      'This usual ingredient is no longer available.';

  @override
  String get usualFoodsNameLabel => 'Name';

  @override
  String get usualFoodsBrandLabel => 'Brand (optional)';

  @override
  String get usualFoodsCanonicalNameLabel => 'Canonical name (optional)';

  @override
  String get usualFoodsBarcodeLabel => 'Barcode (optional)';

  @override
  String get usualFoodsAliasesLabel =>
      'Aliases, separated by commas (optional)';

  @override
  String get usualFoodsServingGramsLabel => 'Serving grams';

  @override
  String get usualFoodsCaloriesLabel => 'Calories';

  @override
  String get usualFoodsProteinLabel => 'Protein grams';

  @override
  String get usualFoodsCarbsLabel => 'Carbs grams';

  @override
  String get usualFoodsFatLabel => 'Fat grams';

  @override
  String get usualFoodsSaltLabel => 'Salt grams (optional)';

  @override
  String get usualFoodsSodiumLabel => 'Sodium milligrams (optional)';

  @override
  String get usualFoodsFiberLabel => 'Fiber grams (optional)';

  @override
  String get usualFoodsSugarsLabel => 'Sugars grams (optional)';

  @override
  String get usualFoodsServingDescriptionLabel =>
      'Serving description (optional)';

  @override
  String get usualFoodsRequiredFieldError => 'Enter a value.';

  @override
  String get usualFoodsPositiveNumberError => 'Enter a number greater than 0.';

  @override
  String get usualFoodsNonNegativeNumberError => 'Enter 0 or a greater number.';

  @override
  String usualFoodsPerServing(String grams) {
    return 'per $grams g';
  }

  @override
  String get usualFoodsManualSource => 'Manual';

  @override
  String get usualFoodsEditTooltip => 'Edit usual ingredient';

  @override
  String get usualFoodsDeleteTooltip => 'Delete usual ingredient';

  @override
  String get usualFoodsDeleteTitle => 'Delete usual ingredient?';

  @override
  String usualFoodsDeleteMessage(String name) {
    return 'Delete $name from your usual ingredients?';
  }

  @override
  String get voiceTitle => 'Log meal';

  @override
  String get voiceStartOver => 'Start over';

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
  String get voiceNoDatabaseMatch =>
      'No database match for this ingredient. Please repeat or rephrase it.';

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
  String get voiceChangesApplied => 'Changes applied';

  @override
  String get voiceTranscriptHeardLabel => 'I heard:';

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
  String get foodSearchTitle => 'Add food';

  @override
  String get foodSearchHint => 'Search foods';

  @override
  String get foodSearchAddAction => 'Add';

  @override
  String get foodSearchUseAction => 'Use';

  @override
  String get foodSearchReplaceAction => 'Replace';

  @override
  String get foodSearchSearchInstead => 'Search instead';

  @override
  String get foodSearchHideSearch => 'Hide search';

  @override
  String get foodSearchReplaceSearch => 'Search replacement';

  @override
  String get foodSearchSelectedFoods => 'Selected foods';

  @override
  String get foodSearchReviewMeal => 'Review meal';

  @override
  String get foodSearchName => 'Food';

  @override
  String get foodSearchQuantity => 'Quantity';

  @override
  String get foodSearchUnit => 'Unit';

  @override
  String get foodSearchNutrition => 'Nutrition';

  @override
  String get foodSearchRemoveDraft => 'Remove food';

  @override
  String get foodSearchClear => 'Clear search';

  @override
  String get foodSearchRetry => 'Retry';

  @override
  String get foodSearchEmpty => 'No foods found';

  @override
  String get foodSearchError => 'Could not search foods.';

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

  @override
  String get localToolkitToolButtonTooltip => 'Open local toolkit';

  @override
  String get localToolkitPanelTitle => 'Local toolkit';

  @override
  String get localToolkitPanelSubtitle =>
      'Jump routes, apply scenarios, and mutate local state.';

  @override
  String get localToolkitRouteSectionTitle => 'Routes';

  @override
  String get localToolkitScenarioSectionTitle => 'Scenarios';

  @override
  String get localToolkitQuickMutatorsSectionTitle => 'Quick mutators';

  @override
  String get localToolkitRouteAuth => 'Auth';

  @override
  String get localToolkitRouteDashboard => 'Dashboard';

  @override
  String get localToolkitRouteLogMeal => 'Log Meal';

  @override
  String get localToolkitRouteHistory => 'History';

  @override
  String get localToolkitRouteTemplates => 'Templates';

  @override
  String get localToolkitRouteSettings => 'Settings';

  @override
  String get localToolkitScenarioUnauthenticated => 'Unauthenticated';

  @override
  String get localToolkitScenarioEmptyDay => 'Empty day';

  @override
  String get localToolkitScenarioNormalDay => 'Normal day';

  @override
  String get localToolkitScenarioOverTarget => 'Over target';

  @override
  String get localToolkitScenarioGoalsNotConfigured => 'Goals not configured';

  @override
  String get localToolkitScenarioProposalReady => 'Proposal ready';

  @override
  String get localToolkitScenarioClarificationRequired =>
      'Clarification required';

  @override
  String get localToolkitScenarioAutoCommittedMeal => 'Auto-committed meal';

  @override
  String get localToolkitScenarioTemplateHeavyAccount =>
      'Template-heavy account';

  @override
  String get localToolkitQuickResetScenario => 'Reset scenario';

  @override
  String get localToolkitQuickAddSampleMeal => 'Add sample meal';

  @override
  String get localToolkitQuickClearMeals => 'Clear meals';

  @override
  String get localToolkitQuickToggleTrustedMode => 'Toggle trusted mode';

  @override
  String get localToolkitQuickSwitchLocale => 'Switch locale';

  @override
  String get localToolkitQuickSwitchTheme => 'Switch light/dark theme';

  @override
  String get localToolkitTrustedModeOn => 'Trusted on';

  @override
  String get localToolkitTrustedModeOff => 'Trusted off';

  @override
  String get localToolkitCloseTooltip => 'Close toolkit';
}
