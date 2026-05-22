import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Better Calories'**
  String get appTitle;

  /// No description provided for @fallbackUserName.
  ///
  /// In en, this message translates to:
  /// **'Cal Tracker'**
  String get fallbackUserName;

  /// No description provided for @routeNotFound.
  ///
  /// In en, this message translates to:
  /// **'Route not found'**
  String get routeNotFound;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get commonCreate;

  /// No description provided for @commonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @commonTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// No description provided for @commonUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get commonUpdate;

  /// No description provided for @commonCalories.
  ///
  /// In en, this message translates to:
  /// **'Calories'**
  String get commonCalories;

  /// No description provided for @commonProtein.
  ///
  /// In en, this message translates to:
  /// **'Protein'**
  String get commonProtein;

  /// No description provided for @commonCarbs.
  ///
  /// In en, this message translates to:
  /// **'Carbs'**
  String get commonCarbs;

  /// No description provided for @commonFat.
  ///
  /// In en, this message translates to:
  /// **'Fat'**
  String get commonFat;

  /// No description provided for @commonIngredient.
  ///
  /// In en, this message translates to:
  /// **'Ingredient'**
  String get commonIngredient;

  /// No description provided for @commonAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get commonAmount;

  /// No description provided for @commonUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get commonUnit;

  /// No description provided for @commonMeal.
  ///
  /// In en, this message translates to:
  /// **'Meal'**
  String get commonMeal;

  /// No description provided for @commonMeals.
  ///
  /// In en, this message translates to:
  /// **'Meals'**
  String get commonMeals;

  /// No description provided for @commonRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get commonRemaining;

  /// No description provided for @commonConsumed.
  ///
  /// In en, this message translates to:
  /// **'Consumed'**
  String get commonConsumed;

  /// No description provided for @commonToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get commonToday;

  /// No description provided for @commonKcal.
  ///
  /// In en, this message translates to:
  /// **'Kcal'**
  String get commonKcal;

  /// No description provided for @commonAddIngredient.
  ///
  /// In en, this message translates to:
  /// **'Add ingredient'**
  String get commonAddIngredient;

  /// No description provided for @commonEditIngredients.
  ///
  /// In en, this message translates to:
  /// **'Edit ingredients'**
  String get commonEditIngredients;

  /// No description provided for @commonSaveEdits.
  ///
  /// In en, this message translates to:
  /// **'Save edits'**
  String get commonSaveEdits;

  /// No description provided for @commonDeleteIngredient.
  ///
  /// In en, this message translates to:
  /// **'Delete ingredient'**
  String get commonDeleteIngredient;

  /// No description provided for @commonCheckIngredientDetails.
  ///
  /// In en, this message translates to:
  /// **'Check ingredient details'**
  String get commonCheckIngredientDetails;

  /// No description provided for @commonIngredientDetailsError.
  ///
  /// In en, this message translates to:
  /// **'Each ingredient needs a name, amount, unit, calories, and non-negative macros.'**
  String get commonIngredientDetailsError;

  /// No description provided for @commonAddAtLeastOneIngredient.
  ///
  /// In en, this message translates to:
  /// **'Add at least one ingredient.'**
  String get commonAddAtLeastOneIngredient;

  /// No description provided for @caloriesValue.
  ///
  /// In en, this message translates to:
  /// **'{calories} Kcal'**
  String caloriesValue(int calories);

  /// No description provided for @macroGramsValue.
  ///
  /// In en, this message translates to:
  /// **'{value} g'**
  String macroGramsValue(String value);

  /// No description provided for @quantityUnitValue.
  ///
  /// In en, this message translates to:
  /// **'{quantity} {unit}'**
  String quantityUnitValue(String quantity, String unit);

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navStats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get navStats;

  /// No description provided for @navLog.
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get navLog;

  /// No description provided for @navUsual.
  ///
  /// In en, this message translates to:
  /// **'Usual'**
  String get navUsual;

  /// No description provided for @navMenu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get navMenu;

  /// No description provided for @authNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get authNameLabel;

  /// No description provided for @authEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailLabel;

  /// No description provided for @authPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// No description provided for @authCreateAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccountButton;

  /// No description provided for @authGetStartedButton.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get authGetStartedButton;

  /// No description provided for @authUseExistingAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Use existing account'**
  String get authUseExistingAccountButton;

  /// No description provided for @authCreateAccountLink.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get authCreateAccountLink;

  /// No description provided for @authContinueWithGoogleButton.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authContinueWithGoogleButton;

  /// No description provided for @authSignInFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in failed'**
  String get authSignInFailedTitle;

  /// No description provided for @authCreateAccountFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Account creation failed'**
  String get authCreateAccountFailedTitle;

  /// No description provided for @authEmailInvalidError.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address, like name@example.com.'**
  String get authEmailInvalidError;

  /// No description provided for @authNameRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Enter your name.'**
  String get authNameRequiredError;

  /// No description provided for @authPasswordRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Enter your password.'**
  String get authPasswordRequiredError;

  /// No description provided for @authPasswordTooShortError.
  ///
  /// In en, this message translates to:
  /// **'Use at least 8 characters.'**
  String get authPasswordTooShortError;

  /// No description provided for @authHeroHeadline.
  ///
  /// In en, this message translates to:
  /// **'Track your\ncalories better.'**
  String get authHeroHeadline;

  /// No description provided for @darkModeSwitchToLight.
  ///
  /// In en, this message translates to:
  /// **'Switch to light mode'**
  String get darkModeSwitchToLight;

  /// No description provided for @darkModeSwitchToDark.
  ///
  /// In en, this message translates to:
  /// **'Switch to dark mode'**
  String get darkModeSwitchToDark;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get settingsTitle;

  /// No description provided for @settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Account and preferences'**
  String get settingsSubtitle;

  /// No description provided for @settingsMoreTooltip.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get settingsMoreTooltip;

  /// No description provided for @settingsCouldNotUpdateGoals.
  ///
  /// In en, this message translates to:
  /// **'Could not update goals'**
  String get settingsCouldNotUpdateGoals;

  /// No description provided for @settingsHydrationGoal.
  ///
  /// In en, this message translates to:
  /// **'Hydration goal'**
  String get settingsHydrationGoal;

  /// No description provided for @settingsHydrationGoalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{liters} L per day'**
  String settingsHydrationGoalSubtitle(String liters);

  /// No description provided for @settingsCalorieTarget.
  ///
  /// In en, this message translates to:
  /// **'Calorie target'**
  String get settingsCalorieTarget;

  /// No description provided for @settingsCalorieTargetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{calories} Kcal daily target'**
  String settingsCalorieTargetSubtitle(int calories);

  /// No description provided for @settingsLitersUnit.
  ///
  /// In en, this message translates to:
  /// **'liters'**
  String get settingsLitersUnit;

  /// No description provided for @settingsOuncesUnit.
  ///
  /// In en, this message translates to:
  /// **'ounces'**
  String get settingsOuncesUnit;

  /// No description provided for @hydrationSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Set your daily water goal'**
  String get hydrationSheetTitle;

  /// No description provided for @hydrationSheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose how much water you want to drink each day.'**
  String get hydrationSheetSubtitle;

  /// No description provided for @hydrationUnitTitle.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get hydrationUnitTitle;

  /// No description provided for @hydrationUnitLiters.
  ///
  /// In en, this message translates to:
  /// **'Liters (L)'**
  String get hydrationUnitLiters;

  /// No description provided for @hydrationUnitOunces.
  ///
  /// In en, this message translates to:
  /// **'Ounces (fl oz)'**
  String get hydrationUnitOunces;

  /// No description provided for @hydrationDailyGoal.
  ///
  /// In en, this message translates to:
  /// **'Daily goal'**
  String get hydrationDailyGoal;

  /// No description provided for @hydrationRecommendedRange.
  ///
  /// In en, this message translates to:
  /// **'Recommended: 2.0 - 3.0 L'**
  String get hydrationRecommendedRange;

  /// No description provided for @hydrationInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Stay hydrated'**
  String get hydrationInfoTitle;

  /// No description provided for @hydrationInfoMessage.
  ///
  /// In en, this message translates to:
  /// **'Drinking enough water helps your body function better and supports your goals.'**
  String get hydrationInfoMessage;

  /// No description provided for @hydrationDecreaseGoalTooltip.
  ///
  /// In en, this message translates to:
  /// **'Decrease water goal'**
  String get hydrationDecreaseGoalTooltip;

  /// No description provided for @hydrationIncreaseGoalTooltip.
  ///
  /// In en, this message translates to:
  /// **'Increase water goal'**
  String get hydrationIncreaseGoalTooltip;

  /// No description provided for @settingsLogOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get settingsLogOut;

  /// No description provided for @settingsGoalRangeError.
  ///
  /// In en, this message translates to:
  /// **'Enter {min}-{max}.'**
  String settingsGoalRangeError(int min, int max);

  /// No description provided for @settingsNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get settingsNotSet;

  /// No description provided for @settingsLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageTitle;

  /// No description provided for @settingsLanguageSubtitleEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageSubtitleEnglish;

  /// No description provided for @settingsLanguageSubtitleSpanish.
  ///
  /// In en, this message translates to:
  /// **'Español'**
  String get settingsLanguageSubtitleSpanish;

  /// No description provided for @settingsLanguageSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get settingsLanguageSheetTitle;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguageSpanish.
  ///
  /// In en, this message translates to:
  /// **'Español'**
  String get settingsLanguageSpanish;

  /// No description provided for @settingsDataSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Data sources'**
  String get settingsDataSourcesTitle;

  /// No description provided for @settingsDataSourcesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Food matches can include public reference data.'**
  String get settingsDataSourcesSubtitle;

  /// No description provided for @settingsDataSourcesOpenFoodFacts.
  ///
  /// In en, this message translates to:
  /// **'Contains information from Open Food Facts, made available under ODbL 1.0. © Open Food Facts contributors.'**
  String get settingsDataSourcesOpenFoodFacts;

  /// No description provided for @settingsDataSourcesUsda.
  ///
  /// In en, this message translates to:
  /// **'USDA FoodData Central data is public domain under CC0 1.0.'**
  String get settingsDataSourcesUsda;

  /// No description provided for @mobileUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Please update'**
  String get mobileUpdateTitle;

  /// No description provided for @mobileUpdateMessage.
  ///
  /// In en, this message translates to:
  /// **'A new BetterCalories version is available. Download the APK from your browser to update.'**
  String get mobileUpdateMessage;

  /// No description provided for @mobileUpdateNow.
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get mobileUpdateNow;

  /// No description provided for @mobileUpdateLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get mobileUpdateLater;

  /// No description provided for @settingsMacroRequiresCaloriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Set calories first'**
  String get settingsMacroRequiresCaloriesTitle;

  /// No description provided for @settingsMacroRequiresCaloriesMessage.
  ///
  /// In en, this message translates to:
  /// **'Configure your daily calories before setting a macro distribution.'**
  String get settingsMacroRequiresCaloriesMessage;

  /// No description provided for @settingsMacroRequiresCaloriesSetNow.
  ///
  /// In en, this message translates to:
  /// **'Set your calories now'**
  String get settingsMacroRequiresCaloriesSetNow;

  /// No description provided for @settingsMacroRequiresCaloriesSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get settingsMacroRequiresCaloriesSkip;

  /// No description provided for @calorieTargetSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Set your daily calories'**
  String get calorieTargetSheetTitle;

  /// No description provided for @calorieTargetSheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the target you want to track each day.'**
  String get calorieTargetSheetSubtitle;

  /// No description provided for @calorieTargetCalculatorLink.
  ///
  /// In en, this message translates to:
  /// **'Don\'t know how many calories you need?'**
  String get calorieTargetCalculatorLink;

  /// No description provided for @calorieTargetRangeValidationError.
  ///
  /// In en, this message translates to:
  /// **'Enter a target from {min} to {max} Kcal.'**
  String calorieTargetRangeValidationError(int min, int max);

  /// No description provided for @calorieTargetIncreaseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Increase'**
  String get calorieTargetIncreaseTooltip;

  /// No description provided for @calorieTargetDecreaseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Decrease'**
  String get calorieTargetDecreaseTooltip;

  /// No description provided for @calorieSetupHeadlinePrefix.
  ///
  /// In en, this message translates to:
  /// **'Set up your'**
  String get calorieSetupHeadlinePrefix;

  /// No description provided for @calorieSetupHeadlineMain.
  ///
  /// In en, this message translates to:
  /// **'daily calories'**
  String get calorieSetupHeadlineMain;

  /// No description provided for @calorieSetupHeadlineBadge.
  ///
  /// In en, this message translates to:
  /// **'Here.'**
  String get calorieSetupHeadlineBadge;

  /// No description provided for @calorieCouldNotSaveCalories.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your calories. Please try again.'**
  String get calorieCouldNotSaveCalories;

  /// No description provided for @calorieCouldNotSaveMacros.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your macros. Please try again.'**
  String get calorieCouldNotSaveMacros;

  /// No description provided for @postCalorieSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Calories saved'**
  String get postCalorieSaveTitle;

  /// No description provided for @postCalorieSaveTarget.
  ///
  /// In en, this message translates to:
  /// **'Your daily target is {calories} Kcal.'**
  String postCalorieSaveTarget(int calories);

  /// No description provided for @postCalorieSaveMacroQuestion.
  ///
  /// In en, this message translates to:
  /// **'Want to track protein, carbs and fats too?'**
  String get postCalorieSaveMacroQuestion;

  /// No description provided for @postCalorieSaveSetMacroDistribution.
  ///
  /// In en, this message translates to:
  /// **'Set macro distribution'**
  String get postCalorieSaveSetMacroDistribution;

  /// No description provided for @postCalorieSaveNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get postCalorieSaveNotNow;

  /// No description provided for @calorieMacroPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Add macros?'**
  String get calorieMacroPromptTitle;

  /// No description provided for @calorieMacroPromptMessage.
  ///
  /// In en, this message translates to:
  /// **'Choose a simple protein, carb and fat split for {calories} Kcal.'**
  String calorieMacroPromptMessage(int calories);

  /// No description provided for @calorieMacroPromptConfigure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get calorieMacroPromptConfigure;

  /// No description provided for @calorieMacroPromptSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get calorieMacroPromptSkip;

  /// No description provided for @calorieCalculatorChooseYourMacrosTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your macros'**
  String get calorieCalculatorChooseYourMacrosTitle;

  /// No description provided for @calorieWizardCheckDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your details'**
  String get calorieWizardCheckDetailsTitle;

  /// No description provided for @calorieWizardContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get calorieWizardContinue;

  /// No description provided for @calorieWizardUseEstimate.
  ///
  /// In en, this message translates to:
  /// **'Use this estimate'**
  String get calorieWizardUseEstimate;

  /// No description provided for @calorieWizardSexTitle.
  ///
  /// In en, this message translates to:
  /// **'What is your biological sex?'**
  String get calorieWizardSexTitle;

  /// No description provided for @calorieWizardSexSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This keeps the calorie estimate aligned with the formula.'**
  String get calorieWizardSexSubtitle;

  /// No description provided for @calorieWizardSexMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get calorieWizardSexMale;

  /// No description provided for @calorieWizardSexMaleMessage.
  ///
  /// In en, this message translates to:
  /// **'Use the male BMR coefficient.'**
  String get calorieWizardSexMaleMessage;

  /// No description provided for @calorieWizardSexFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get calorieWizardSexFemale;

  /// No description provided for @calorieWizardSexFemaleMessage.
  ///
  /// In en, this message translates to:
  /// **'Use the female BMR coefficient.'**
  String get calorieWizardSexFemaleMessage;

  /// No description provided for @calorieWizardBirthdayTitle.
  ///
  /// In en, this message translates to:
  /// **'When\'s your birthday?'**
  String get calorieWizardBirthdayTitle;

  /// No description provided for @calorieWizardBirthdayMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get calorieWizardBirthdayMonth;

  /// No description provided for @calorieWizardBirthdayDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get calorieWizardBirthdayDay;

  /// No description provided for @calorieWizardBirthdayYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get calorieWizardBirthdayYear;

  /// No description provided for @calorieWizardBirthdayValidationError.
  ///
  /// In en, this message translates to:
  /// **'Choose a birthday for ages 18 to 100.'**
  String get calorieWizardBirthdayValidationError;

  /// No description provided for @calorieWizardHeightTitle.
  ///
  /// In en, this message translates to:
  /// **'How tall are you?'**
  String get calorieWizardHeightTitle;

  /// No description provided for @calorieWizardHeightValidationError.
  ///
  /// In en, this message translates to:
  /// **'Enter a height from 120 to 230 cm.'**
  String get calorieWizardHeightValidationError;

  /// No description provided for @calorieWizardWeightTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s your current weight?'**
  String get calorieWizardWeightTitle;

  /// No description provided for @calorieWizardWeightValidationError.
  ///
  /// In en, this message translates to:
  /// **'Enter a weight from 35 to 250 kg.'**
  String get calorieWizardWeightValidationError;

  /// No description provided for @calorieWizardProfileValidationError.
  ///
  /// In en, this message translates to:
  /// **'Enter age, height, and weight in the expected ranges.'**
  String get calorieWizardProfileValidationError;

  /// No description provided for @calorieWizardGoalTitle.
  ///
  /// In en, this message translates to:
  /// **'What is your main goal?'**
  String get calorieWizardGoalTitle;

  /// No description provided for @calorieWizardGoalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the outcome you want your target to support.'**
  String get calorieWizardGoalSubtitle;

  /// No description provided for @calorieWizardGoalLoseWeight.
  ///
  /// In en, this message translates to:
  /// **'Lose Weight'**
  String get calorieWizardGoalLoseWeight;

  /// No description provided for @calorieWizardGoalLoseWeightMessage.
  ///
  /// In en, this message translates to:
  /// **'Estimate a deficit from maintenance.'**
  String get calorieWizardGoalLoseWeightMessage;

  /// No description provided for @calorieWizardGoalGainMuscle.
  ///
  /// In en, this message translates to:
  /// **'Gain Muscle'**
  String get calorieWizardGoalGainMuscle;

  /// No description provided for @calorieWizardGoalGainMuscleMessage.
  ///
  /// In en, this message translates to:
  /// **'Estimate a controlled calorie surplus.'**
  String get calorieWizardGoalGainMuscleMessage;

  /// No description provided for @calorieWizardGoalMaintainWeight.
  ///
  /// In en, this message translates to:
  /// **'Maintain Weight'**
  String get calorieWizardGoalMaintainWeight;

  /// No description provided for @calorieWizardGoalMaintainWeightMessage.
  ///
  /// In en, this message translates to:
  /// **'Track around your estimated maintenance.'**
  String get calorieWizardGoalMaintainWeightMessage;

  /// No description provided for @calorieWizardLossPaceTitle.
  ///
  /// In en, this message translates to:
  /// **'How fast do you want to lose weight?'**
  String get calorieWizardLossPaceTitle;

  /// No description provided for @calorieWizardGainPaceTitle.
  ///
  /// In en, this message translates to:
  /// **'How fast do you want to gain weight?'**
  String get calorieWizardGainPaceTitle;

  /// No description provided for @calorieWizardPaceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A steadier pace is easier to sustain.'**
  String get calorieWizardPaceSubtitle;

  /// No description provided for @calorieWizardPaceSlow.
  ///
  /// In en, this message translates to:
  /// **'Slow'**
  String get calorieWizardPaceSlow;

  /// No description provided for @calorieWizardPaceSlowMessage.
  ///
  /// In en, this message translates to:
  /// **'Easier to maintain and better for performance.'**
  String get calorieWizardPaceSlowMessage;

  /// No description provided for @calorieWizardPaceModerate.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get calorieWizardPaceModerate;

  /// No description provided for @calorieWizardPaceModerateMessage.
  ///
  /// In en, this message translates to:
  /// **'Recommended default for most users.'**
  String get calorieWizardPaceModerateMessage;

  /// No description provided for @calorieWizardPaceAggressive.
  ///
  /// In en, this message translates to:
  /// **'Aggressive'**
  String get calorieWizardPaceAggressive;

  /// No description provided for @calorieWizardLossPaceAggressiveMessage.
  ///
  /// In en, this message translates to:
  /// **'Larger deficit. Use only if you can recover well.'**
  String get calorieWizardLossPaceAggressiveMessage;

  /// No description provided for @calorieWizardPaceLean.
  ///
  /// In en, this message translates to:
  /// **'Lean'**
  String get calorieWizardPaceLean;

  /// No description provided for @calorieWizardPaceLeanMessage.
  ///
  /// In en, this message translates to:
  /// **'Small surplus for minimal fat gain.'**
  String get calorieWizardPaceLeanMessage;

  /// No description provided for @calorieWizardPaceStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get calorieWizardPaceStandard;

  /// No description provided for @calorieWizardPaceStandardMessage.
  ///
  /// In en, this message translates to:
  /// **'Recommended default for most users gaining muscle.'**
  String get calorieWizardPaceStandardMessage;

  /// No description provided for @calorieWizardGainPaceAggressiveMessage.
  ///
  /// In en, this message translates to:
  /// **'Larger surplus with higher fat-gain risk.'**
  String get calorieWizardGainPaceAggressiveMessage;

  /// No description provided for @calorieWizardActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'What is your activity level?'**
  String get calorieWizardActivityTitle;

  /// No description provided for @calorieWizardActivitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick the option that best matches a normal week.'**
  String get calorieWizardActivitySubtitle;

  /// No description provided for @calorieWizardActivitySedentary.
  ///
  /// In en, this message translates to:
  /// **'Sedentary'**
  String get calorieWizardActivitySedentary;

  /// No description provided for @calorieWizardActivitySedentaryMessage.
  ///
  /// In en, this message translates to:
  /// **'Mostly seated, low daily movement, and 0-1 light workouts weekly.'**
  String get calorieWizardActivitySedentaryMessage;

  /// No description provided for @calorieWizardActivityLightlyActive.
  ///
  /// In en, this message translates to:
  /// **'Lightly Active'**
  String get calorieWizardActivityLightlyActive;

  /// No description provided for @calorieWizardActivityLightlyActiveMessage.
  ///
  /// In en, this message translates to:
  /// **'Regular walks or light exercise 1-3 days per week.'**
  String get calorieWizardActivityLightlyActiveMessage;

  /// No description provided for @calorieWizardActivityModeratelyActive.
  ///
  /// In en, this message translates to:
  /// **'Moderately Active'**
  String get calorieWizardActivityModeratelyActive;

  /// No description provided for @calorieWizardActivityModeratelyActiveMessage.
  ///
  /// In en, this message translates to:
  /// **'Training 3-5 days per week or a meaningfully active routine.'**
  String get calorieWizardActivityModeratelyActiveMessage;

  /// No description provided for @calorieWizardActivityVeryActive.
  ///
  /// In en, this message translates to:
  /// **'Very Active'**
  String get calorieWizardActivityVeryActive;

  /// No description provided for @calorieWizardActivityVeryActiveMessage.
  ///
  /// In en, this message translates to:
  /// **'Hard exercise most days or active work plus regular training.'**
  String get calorieWizardActivityVeryActiveMessage;

  /// No description provided for @calorieWizardActivitySuperActive.
  ///
  /// In en, this message translates to:
  /// **'Super Active'**
  String get calorieWizardActivitySuperActive;

  /// No description provided for @calorieWizardActivitySuperActiveMessage.
  ///
  /// In en, this message translates to:
  /// **'Athlete-level workload, two-a-days, or demanding physical work.'**
  String get calorieWizardActivitySuperActiveMessage;

  /// No description provided for @calorieWizardBackTooltip.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get calorieWizardBackTooltip;

  /// No description provided for @calorieWizardCloseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get calorieWizardCloseTooltip;

  /// No description provided for @calorieWizardLoadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Personalizing your calorie plan...'**
  String get calorieWizardLoadingTitle;

  /// No description provided for @calorieWizardLoadingMessage.
  ///
  /// In en, this message translates to:
  /// **'Building a target from your profile and activity.'**
  String get calorieWizardLoadingMessage;

  /// No description provided for @calorieWizardResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Your personalized calorie plan is ready!'**
  String get calorieWizardResultTitle;

  /// No description provided for @calorieWizardResultBmr.
  ///
  /// In en, this message translates to:
  /// **'BMR estimate'**
  String get calorieWizardResultBmr;

  /// No description provided for @calorieWizardResultMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get calorieWizardResultMaintenance;

  /// No description provided for @calorieWizardResultTargetRange.
  ///
  /// In en, this message translates to:
  /// **'Target range'**
  String get calorieWizardResultTargetRange;

  /// No description provided for @calorieWizardResultAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Adjustment'**
  String get calorieWizardResultAdjustment;

  /// No description provided for @calorieWizardTargetRangeValue.
  ///
  /// In en, this message translates to:
  /// **'{min}-{max} Kcal'**
  String calorieWizardTargetRangeValue(int min, int max);

  /// No description provided for @calorieWizardEstimateNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Estimate note'**
  String get calorieWizardEstimateNoteTitle;

  /// No description provided for @macroSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Set your macros'**
  String get macroSheetTitle;

  /// No description provided for @macroDailyTarget.
  ///
  /// In en, this message translates to:
  /// **'Daily target: {calories} Kcal'**
  String macroDailyTarget(int calories);

  /// No description provided for @macroSaveMacros.
  ///
  /// In en, this message translates to:
  /// **'Save macros'**
  String get macroSaveMacros;

  /// No description provided for @macroPersonalizedTitle.
  ///
  /// In en, this message translates to:
  /// **'Personalized macros'**
  String get macroPersonalizedTitle;

  /// No description provided for @macroSavePersonalized.
  ///
  /// In en, this message translates to:
  /// **'Save personalized macros'**
  String get macroSavePersonalized;

  /// No description provided for @macroPercentagesTab.
  ///
  /// In en, this message translates to:
  /// **'Percentages'**
  String get macroPercentagesTab;

  /// No description provided for @macroGramsTab.
  ///
  /// In en, this message translates to:
  /// **'Grams'**
  String get macroGramsTab;

  /// No description provided for @macroPresetBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get macroPresetBalanced;

  /// No description provided for @macroPresetHighProtein.
  ///
  /// In en, this message translates to:
  /// **'High protein'**
  String get macroPresetHighProtein;

  /// No description provided for @macroPresetLowerCarb.
  ///
  /// In en, this message translates to:
  /// **'Lower carb'**
  String get macroPresetLowerCarb;

  /// No description provided for @macroPersonalized.
  ///
  /// In en, this message translates to:
  /// **'Personalized'**
  String get macroPersonalized;

  /// No description provided for @macroCreateOwnSplit.
  ///
  /// In en, this message translates to:
  /// **'Create your own split'**
  String get macroCreateOwnSplit;

  /// No description provided for @macroPercentagesOrGrams.
  ///
  /// In en, this message translates to:
  /// **'Percentages or grams'**
  String get macroPercentagesOrGrams;

  /// No description provided for @macroPersonalizedPercentages.
  ///
  /// In en, this message translates to:
  /// **'Personalized percentages'**
  String get macroPersonalizedPercentages;

  /// No description provided for @macroPersonalizedGrams.
  ///
  /// In en, this message translates to:
  /// **'Personalized grams'**
  String get macroPersonalizedGrams;

  /// No description provided for @macroProteinPercentSummary.
  ///
  /// In en, this message translates to:
  /// **'{percent}% protein'**
  String macroProteinPercentSummary(int percent);

  /// No description provided for @macroCarbsPercentSummary.
  ///
  /// In en, this message translates to:
  /// **'{percent}% carbs'**
  String macroCarbsPercentSummary(int percent);

  /// No description provided for @macroFatPercentSummary.
  ///
  /// In en, this message translates to:
  /// **'{percent}% fat'**
  String macroFatPercentSummary(int percent);

  /// No description provided for @macroProteinGramsSummary.
  ///
  /// In en, this message translates to:
  /// **'{grams}g protein'**
  String macroProteinGramsSummary(String grams);

  /// No description provided for @macroCarbsGramsSummary.
  ///
  /// In en, this message translates to:
  /// **'{grams}g carbs'**
  String macroCarbsGramsSummary(String grams);

  /// No description provided for @macroFatGramsSummary.
  ///
  /// In en, this message translates to:
  /// **'{grams}g fat'**
  String macroFatGramsSummary(String grams);

  /// No description provided for @macroGramTriplet.
  ///
  /// In en, this message translates to:
  /// **'{protein}g · {carbs}g · {fat}g'**
  String macroGramTriplet(String protein, String carbs, String fat);

  /// No description provided for @macroPercentagesWithGramsSummary.
  ///
  /// In en, this message translates to:
  /// **'{percentages} ({grams})'**
  String macroPercentagesWithGramsSummary(String percentages, String grams);

  /// No description provided for @macroPercentagesMustTotal.
  ///
  /// In en, this message translates to:
  /// **'Percentages must total 100%'**
  String get macroPercentagesMustTotal;

  /// No description provided for @macroPercentagesTotalMessage.
  ///
  /// In en, this message translates to:
  /// **'These add up to {total}%. Adjust one macro or reset to balanced before saving.'**
  String macroPercentagesTotalMessage(int total);

  /// No description provided for @macroAdjustProtein.
  ///
  /// In en, this message translates to:
  /// **'Adjust protein'**
  String get macroAdjustProtein;

  /// No description provided for @macroAdjustCarbs.
  ///
  /// In en, this message translates to:
  /// **'Adjust carbs'**
  String get macroAdjustCarbs;

  /// No description provided for @macroAdjustFat.
  ///
  /// In en, this message translates to:
  /// **'Adjust fat'**
  String get macroAdjustFat;

  /// No description provided for @macroResetBalanced.
  ///
  /// In en, this message translates to:
  /// **'Reset balanced'**
  String get macroResetBalanced;

  /// No description provided for @macroGramsTooHigh.
  ///
  /// In en, this message translates to:
  /// **'Macro grams are too high'**
  String get macroGramsTooHigh;

  /// No description provided for @macroGramsTooHighMessage.
  ///
  /// In en, this message translates to:
  /// **'Each macro target must be 2000 g or less.'**
  String get macroGramsTooHighMessage;

  /// No description provided for @macroSmallCalorieMismatch.
  ///
  /// In en, this message translates to:
  /// **'Small calorie mismatch'**
  String get macroSmallCalorieMismatch;

  /// No description provided for @macroCaloriesDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Macros do not match calories'**
  String get macroCaloriesDoNotMatch;

  /// No description provided for @macroGramMismatchOverMessage.
  ///
  /// In en, this message translates to:
  /// **'These grams add up to {macroCalories} Kcal, {delta} Kcal over your target.'**
  String macroGramMismatchOverMessage(int macroCalories, int delta);

  /// No description provided for @macroGramMismatchUnderMessage.
  ///
  /// In en, this message translates to:
  /// **'These grams add up to {macroCalories} Kcal, {delta} Kcal under your target.'**
  String macroGramMismatchUnderMessage(int macroCalories, int delta);

  /// No description provided for @macroUsePercentages.
  ///
  /// In en, this message translates to:
  /// **'Use percentages'**
  String get macroUsePercentages;

  /// No description provided for @dashboardCouldNotLoadToday.
  ///
  /// In en, this message translates to:
  /// **'Could not load today'**
  String get dashboardCouldNotLoadToday;

  /// No description provided for @dashboardGreetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning!'**
  String get dashboardGreetingMorning;

  /// No description provided for @dashboardGreetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon!'**
  String get dashboardGreetingAfternoon;

  /// No description provided for @dashboardGreetingNight.
  ///
  /// In en, this message translates to:
  /// **'Good night!'**
  String get dashboardGreetingNight;

  /// No description provided for @dashboardDailyProgress.
  ///
  /// In en, this message translates to:
  /// **'Your Daily\nProgress'**
  String get dashboardDailyProgress;

  /// No description provided for @dashboardTodayCalories.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Calories'**
  String get dashboardTodayCalories;

  /// No description provided for @dashboardCaloriesLeft.
  ///
  /// In en, this message translates to:
  /// **'left'**
  String get dashboardCaloriesLeft;

  /// No description provided for @dashboardGoalLine.
  ///
  /// In en, this message translates to:
  /// **'Target {calories} Kcal, {liters} L'**
  String dashboardGoalLine(int calories, String liters);

  /// No description provided for @dashboardWaterIntake.
  ///
  /// In en, this message translates to:
  /// **'Water Intake'**
  String get dashboardWaterIntake;

  /// No description provided for @dashboardWaterProgress.
  ///
  /// In en, this message translates to:
  /// **'{consumed} / {goal} L'**
  String dashboardWaterProgress(String consumed, String goal);

  /// No description provided for @dashboardWaterDecreaseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Decrease water intake'**
  String get dashboardWaterDecreaseTooltip;

  /// No description provided for @dashboardWaterIncreaseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Increase water intake'**
  String get dashboardWaterIncreaseTooltip;

  /// No description provided for @dashboardTodayLower.
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get dashboardTodayLower;

  /// No description provided for @dashboardNoMealsLoggedToday.
  ///
  /// In en, this message translates to:
  /// **'No meals logged today'**
  String get dashboardNoMealsLoggedToday;

  /// No description provided for @dashboardNoMealsMessage.
  ///
  /// In en, this message translates to:
  /// **'Logged meals will appear here.'**
  String get dashboardNoMealsMessage;

  /// No description provided for @dashboardEditIngredientsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit ingredients'**
  String get dashboardEditIngredientsTooltip;

  /// No description provided for @dashboardDeleteMealTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete meal'**
  String get dashboardDeleteMealTooltip;

  /// No description provided for @dashboardCouldNotDeleteMeal.
  ///
  /// In en, this message translates to:
  /// **'Could not delete meal.'**
  String get dashboardCouldNotDeleteMeal;

  /// No description provided for @monthJan.
  ///
  /// In en, this message translates to:
  /// **'Jan'**
  String get monthJan;

  /// No description provided for @monthFeb.
  ///
  /// In en, this message translates to:
  /// **'Feb'**
  String get monthFeb;

  /// No description provided for @monthMar.
  ///
  /// In en, this message translates to:
  /// **'Mar'**
  String get monthMar;

  /// No description provided for @monthApr.
  ///
  /// In en, this message translates to:
  /// **'Apr'**
  String get monthApr;

  /// No description provided for @monthMay.
  ///
  /// In en, this message translates to:
  /// **'May'**
  String get monthMay;

  /// No description provided for @monthJun.
  ///
  /// In en, this message translates to:
  /// **'Jun'**
  String get monthJun;

  /// No description provided for @monthJul.
  ///
  /// In en, this message translates to:
  /// **'Jul'**
  String get monthJul;

  /// No description provided for @monthAug.
  ///
  /// In en, this message translates to:
  /// **'Aug'**
  String get monthAug;

  /// No description provided for @monthSep.
  ///
  /// In en, this message translates to:
  /// **'Sep'**
  String get monthSep;

  /// No description provided for @monthOct.
  ///
  /// In en, this message translates to:
  /// **'Oct'**
  String get monthOct;

  /// No description provided for @monthNov.
  ///
  /// In en, this message translates to:
  /// **'Nov'**
  String get monthNov;

  /// No description provided for @monthDec.
  ///
  /// In en, this message translates to:
  /// **'Dec'**
  String get monthDec;

  /// No description provided for @dayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get dayMon;

  /// No description provided for @dayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get dayTue;

  /// No description provided for @dayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get dayWed;

  /// No description provided for @dayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get dayThu;

  /// No description provided for @dayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get dayFri;

  /// No description provided for @daySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get daySat;

  /// No description provided for @daySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get daySun;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get historyTitle;

  /// No description provided for @historySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Calories and meal history'**
  String get historySubtitle;

  /// No description provided for @historyCouldNotLoadHistory.
  ///
  /// In en, this message translates to:
  /// **'Could not load history'**
  String get historyCouldNotLoadHistory;

  /// No description provided for @historyLoggedMeals.
  ///
  /// In en, this message translates to:
  /// **'Logged meals'**
  String get historyLoggedMeals;

  /// No description provided for @historyMealCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 meals} =1{1 meal} other{{count} meals}}'**
  String historyMealCount(int count);

  /// No description provided for @historyNoMealsLogged.
  ///
  /// In en, this message translates to:
  /// **'No meals logged'**
  String get historyNoMealsLogged;

  /// No description provided for @historyNoMealsMessage.
  ///
  /// In en, this message translates to:
  /// **'Meal details will appear after logging.'**
  String get historyNoMealsMessage;

  /// No description provided for @historyDeleteMealTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete meal?'**
  String get historyDeleteMealTitle;

  /// No description provided for @historyTargetCalories.
  ///
  /// In en, this message translates to:
  /// **'Target: {calories} Kcal'**
  String historyTargetCalories(int calories);

  /// No description provided for @historySelectDaySemantics.
  ///
  /// In en, this message translates to:
  /// **'Select {label}'**
  String historySelectDaySemantics(String label);

  /// No description provided for @templatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Usual meals'**
  String get templatesTitle;

  /// No description provided for @templatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Safe familiar templates'**
  String get templatesSubtitle;

  /// No description provided for @templatesAddTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add usual meal'**
  String get templatesAddTooltip;

  /// No description provided for @templatesExplainer.
  ///
  /// In en, this message translates to:
  /// **'Usual meals are trusted meals you can log quickly.'**
  String get templatesExplainer;

  /// No description provided for @templatesCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load usual meals'**
  String get templatesCouldNotLoad;

  /// No description provided for @templatesNoUsualMealsYet.
  ///
  /// In en, this message translates to:
  /// **'No usual meals yet'**
  String get templatesNoUsualMealsYet;

  /// No description provided for @templatesNoUsualMealsMessage.
  ///
  /// In en, this message translates to:
  /// **'Saved meals will appear here.'**
  String get templatesNoUsualMealsMessage;

  /// No description provided for @templatesDeleteUsualMealTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete usual meal?'**
  String get templatesDeleteUsualMealTitle;

  /// No description provided for @templatesNewUsualMealTitle.
  ///
  /// In en, this message translates to:
  /// **'New usual meal'**
  String get templatesNewUsualMealTitle;

  /// No description provided for @templatesTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get templatesTitleLabel;

  /// No description provided for @templatesAliasesLabel.
  ///
  /// In en, this message translates to:
  /// **'Aliases, separated by commas'**
  String get templatesAliasesLabel;

  /// No description provided for @templatesNoAliasesYet.
  ///
  /// In en, this message translates to:
  /// **'No aliases yet'**
  String get templatesNoAliasesYet;

  /// No description provided for @voiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Log meal'**
  String get voiceTitle;

  /// No description provided for @voiceStartOver.
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get voiceStartOver;

  /// No description provided for @voiceTranscribingTitle.
  ///
  /// In en, this message translates to:
  /// **'Transcribing...'**
  String get voiceTranscribingTitle;

  /// No description provided for @voiceTranscribingMessage.
  ///
  /// In en, this message translates to:
  /// **'Listening back and preparing the text.'**
  String get voiceTranscribingMessage;

  /// No description provided for @voiceClarificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Needs a little more detail'**
  String get voiceClarificationTitle;

  /// No description provided for @voiceClarificationDefault.
  ///
  /// In en, this message translates to:
  /// **'Add a bit more detail and submit again.'**
  String get voiceClarificationDefault;

  /// No description provided for @voiceFoodMatches.
  ///
  /// In en, this message translates to:
  /// **'Food matches'**
  String get voiceFoodMatches;

  /// No description provided for @voiceNoConfidentMatchYet.
  ///
  /// In en, this message translates to:
  /// **'No confident match yet'**
  String get voiceNoConfidentMatchYet;

  /// No description provided for @voiceNoDatabaseMatch.
  ///
  /// In en, this message translates to:
  /// **'No database match for this ingredient. Please repeat or rephrase it.'**
  String get voiceNoDatabaseMatch;

  /// No description provided for @voiceRecordingTitle.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get voiceRecordingTitle;

  /// No description provided for @voiceIntakeTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice intake'**
  String get voiceIntakeTitle;

  /// No description provided for @voiceTapStopWhenDone.
  ///
  /// In en, this message translates to:
  /// **'Tap stop when you are done.'**
  String get voiceTapStopWhenDone;

  /// No description provided for @voiceSayMealNaturally.
  ///
  /// In en, this message translates to:
  /// **'Say your meal naturally.'**
  String get voiceSayMealNaturally;

  /// No description provided for @voiceMealFilledWithVoice.
  ///
  /// In en, this message translates to:
  /// **'The meal will be filled with your voice.'**
  String get voiceMealFilledWithVoice;

  /// No description provided for @voiceStopRecordingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get voiceStopRecordingTooltip;

  /// No description provided for @voiceRecordVoiceTooltip.
  ///
  /// In en, this message translates to:
  /// **'Record voice'**
  String get voiceRecordVoiceTooltip;

  /// No description provided for @voiceRecordingIndicator.
  ///
  /// In en, this message translates to:
  /// **'Recording. Tap stop when you finish.'**
  String get voiceRecordingIndicator;

  /// No description provided for @voiceErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get voiceErrorTitle;

  /// No description provided for @voiceLoggedMessage.
  ///
  /// In en, this message translates to:
  /// **'Logged. You can correct it from history.'**
  String get voiceLoggedMessage;

  /// No description provided for @voiceMessageMealLogged.
  ///
  /// In en, this message translates to:
  /// **'Meal logged.'**
  String get voiceMessageMealLogged;

  /// No description provided for @voiceMessageProposalUpdated.
  ///
  /// In en, this message translates to:
  /// **'Proposal updated.'**
  String get voiceMessageProposalUpdated;

  /// No description provided for @voiceMessageMealProposalCreated.
  ///
  /// In en, this message translates to:
  /// **'Meal proposal created.'**
  String get voiceMessageMealProposalCreated;

  /// No description provided for @voiceChangesApplied.
  ///
  /// In en, this message translates to:
  /// **'Changes applied'**
  String get voiceChangesApplied;

  /// No description provided for @voiceTodaySection.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get voiceTodaySection;

  /// No description provided for @voiceMealsSection.
  ///
  /// In en, this message translates to:
  /// **'Meals'**
  String get voiceMealsSection;

  /// No description provided for @voiceNutritionMatchesSection.
  ///
  /// In en, this message translates to:
  /// **'Nutrition matches'**
  String get voiceNutritionMatchesSection;

  /// No description provided for @voiceUsualMealsSection.
  ///
  /// In en, this message translates to:
  /// **'Usual meals'**
  String get voiceUsualMealsSection;

  /// No description provided for @voiceNoMealsYet.
  ///
  /// In en, this message translates to:
  /// **'No meals yet'**
  String get voiceNoMealsYet;

  /// No description provided for @voiceNoMealsMessage.
  ///
  /// In en, this message translates to:
  /// **'Logged meals will appear here.'**
  String get voiceNoMealsMessage;

  /// No description provided for @voiceItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 items} =1{1 item} other{{count} items}}'**
  String voiceItemCount(int count);

  /// No description provided for @voiceStateListening.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get voiceStateListening;

  /// No description provided for @voiceStateSavingAudio.
  ///
  /// In en, this message translates to:
  /// **'Saving audio'**
  String get voiceStateSavingAudio;

  /// No description provided for @voiceStateWhisperTranscription.
  ///
  /// In en, this message translates to:
  /// **'Whisper transcription'**
  String get voiceStateWhisperTranscription;

  /// No description provided for @voiceStateTranscriptReady.
  ///
  /// In en, this message translates to:
  /// **'Transcript ready'**
  String get voiceStateTranscriptReady;

  /// No description provided for @voiceStateBuildingProposal.
  ///
  /// In en, this message translates to:
  /// **'Building proposal'**
  String get voiceStateBuildingProposal;

  /// No description provided for @voiceStateReviewMeal.
  ///
  /// In en, this message translates to:
  /// **'Review meal'**
  String get voiceStateReviewMeal;

  /// No description provided for @voiceStateLogged.
  ///
  /// In en, this message translates to:
  /// **'Logged'**
  String get voiceStateLogged;

  /// No description provided for @voiceStateResultReady.
  ///
  /// In en, this message translates to:
  /// **'Result ready'**
  String get voiceStateResultReady;

  /// No description provided for @voiceStateClarification.
  ///
  /// In en, this message translates to:
  /// **'Clarification'**
  String get voiceStateClarification;

  /// No description provided for @voiceStateNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get voiceStateNeedsAttention;

  /// No description provided for @voiceStateInput.
  ///
  /// In en, this message translates to:
  /// **'Voice or text input'**
  String get voiceStateInput;

  /// No description provided for @mealLabelQuestion.
  ///
  /// In en, this message translates to:
  /// **'Which type of meal is this?'**
  String get mealLabelQuestion;

  /// No description provided for @mealLabelHelper.
  ///
  /// In en, this message translates to:
  /// **'This helps organize your day.'**
  String get mealLabelHelper;

  /// No description provided for @mealLabelBreakfast.
  ///
  /// In en, this message translates to:
  /// **'Breakfast'**
  String get mealLabelBreakfast;

  /// No description provided for @mealLabelLunch.
  ///
  /// In en, this message translates to:
  /// **'Lunch'**
  String get mealLabelLunch;

  /// No description provided for @mealLabelDinner.
  ///
  /// In en, this message translates to:
  /// **'Dinner'**
  String get mealLabelDinner;

  /// No description provided for @mealLabelSnack.
  ///
  /// In en, this message translates to:
  /// **'Snack'**
  String get mealLabelSnack;

  /// No description provided for @mealLabelPreWorkout.
  ///
  /// In en, this message translates to:
  /// **'Pre-workout'**
  String get mealLabelPreWorkout;

  /// No description provided for @mealLabelPostWorkout.
  ///
  /// In en, this message translates to:
  /// **'Post-workout'**
  String get mealLabelPostWorkout;

  /// No description provided for @mealLabelOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get mealLabelOther;

  /// No description provided for @mealLabelNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get mealLabelNone;

  /// No description provided for @mealLabelCustomType.
  ///
  /// In en, this message translates to:
  /// **'Custom meal type'**
  String get mealLabelCustomType;

  /// No description provided for @mealLabelOtherPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Brunch'**
  String get mealLabelOtherPlaceholder;

  /// No description provided for @mealLabelSave.
  ///
  /// In en, this message translates to:
  /// **'Save label'**
  String get mealLabelSave;

  /// No description provided for @mealLabelSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get mealLabelSkip;

  /// No description provided for @mealProposalReadyToLog.
  ///
  /// In en, this message translates to:
  /// **'Ready to log'**
  String get mealProposalReadyToLog;

  /// No description provided for @mealProposalConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get mealProposalConfirm;

  /// No description provided for @mealConfirmationEmbedded.
  ///
  /// In en, this message translates to:
  /// **'Meal confirmation is embedded in the logging flow.'**
  String get mealConfirmationEmbedded;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
