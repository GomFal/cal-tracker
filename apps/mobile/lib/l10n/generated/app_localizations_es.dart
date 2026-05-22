// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Better Calories';

  @override
  String get fallbackUserName => 'Cal Tracker';

  @override
  String get routeNotFound => 'Ruta no encontrada';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonDelete => 'Eliminar';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonCreate => 'Crear';

  @override
  String get commonRefresh => 'Actualizar';

  @override
  String get commonTryAgain => 'Intentar de nuevo';

  @override
  String get commonUpdate => 'Actualizar';

  @override
  String get commonCalories => 'Calorías';

  @override
  String get commonProtein => 'Proteína';

  @override
  String get commonCarbs => 'Carbohidratos';

  @override
  String get commonFat => 'Grasa';

  @override
  String get commonIngredient => 'Ingrediente';

  @override
  String get commonAmount => 'Cantidad';

  @override
  String get commonUnit => 'Unidad';

  @override
  String get commonMeal => 'Comida';

  @override
  String get commonMeals => 'Comidas';

  @override
  String get commonRemaining => 'Restante';

  @override
  String get commonConsumed => 'Consumido';

  @override
  String get commonToday => 'Hoy';

  @override
  String get commonKcal => 'Kcal';

  @override
  String get commonAddIngredient => 'Añadir ingrediente';

  @override
  String get commonEditIngredients => 'Editar ingredientes';

  @override
  String get commonSaveEdits => 'Guardar cambios';

  @override
  String get commonDeleteIngredient => 'Eliminar ingrediente';

  @override
  String get commonCheckIngredientDetails => 'Revisa los ingredientes';

  @override
  String get commonIngredientDetailsError =>
      'Cada ingrediente necesita nombre, cantidad, unidad, calorías y macros no negativos.';

  @override
  String get commonAddAtLeastOneIngredient => 'Añade al menos un ingrediente.';

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
  String get navHome => 'Inicio';

  @override
  String get navStats => 'Estadísticas';

  @override
  String get navLog => 'Registrar';

  @override
  String get navUsual => 'Habituales';

  @override
  String get navMenu => 'Menú';

  @override
  String get authNameLabel => 'Nombre';

  @override
  String get authEmailLabel => 'Correo';

  @override
  String get authPasswordLabel => 'Contraseña';

  @override
  String get authCreateAccountButton => 'Crear cuenta';

  @override
  String get authGetStartedButton => 'Empezar';

  @override
  String get authUseExistingAccountButton => 'Usar cuenta existente';

  @override
  String get authCreateAccountLink => 'Crear una cuenta';

  @override
  String get authContinueWithGoogleButton => 'Continuar con Google';

  @override
  String get authSignInFailedTitle => 'No se pudo iniciar sesión';

  @override
  String get authCreateAccountFailedTitle => 'No se pudo crear la cuenta';

  @override
  String get authEmailInvalidError =>
      'Introduce un correo válido, como nombre@example.com.';

  @override
  String get authNameRequiredError => 'Introduce tu nombre.';

  @override
  String get authPasswordRequiredError => 'Introduce tu contraseña.';

  @override
  String get authPasswordTooShortError => 'Usa al menos 8 caracteres.';

  @override
  String get authHeroHeadline => 'Controla mejor\ntus calorías.';

  @override
  String get darkModeSwitchToLight => 'Cambiar a modo claro';

  @override
  String get darkModeSwitchToDark => 'Cambiar a modo oscuro';

  @override
  String get settingsTitle => 'Menú';

  @override
  String get settingsSubtitle => 'Cuenta y preferencias';

  @override
  String get settingsMoreTooltip => 'Más';

  @override
  String get settingsCouldNotUpdateGoals =>
      'No se pudieron actualizar los objetivos';

  @override
  String get settingsHydrationGoal => 'Objetivo de hidratación';

  @override
  String settingsHydrationGoalSubtitle(int glasses) {
    return '$glasses vasos al día';
  }

  @override
  String get settingsCalorieTarget => 'Objetivo de calorías';

  @override
  String settingsCalorieTargetSubtitle(int calories) {
    return '$calories Kcal de objetivo diario';
  }

  @override
  String get settingsGlassesUnit => 'vasos';

  @override
  String get settingsLogOut => 'Cerrar sesión';

  @override
  String settingsGoalRangeError(int min, int max) {
    return 'Introduce $min-$max.';
  }

  @override
  String get settingsNotSet => 'Sin configurar';

  @override
  String get settingsLanguageTitle => 'Idioma';

  @override
  String get settingsLanguageSubtitleEnglish => 'English';

  @override
  String get settingsLanguageSubtitleSpanish => 'Español';

  @override
  String get settingsLanguageSheetTitle => 'Elige idioma';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageSpanish => 'Español';

  @override
  String get settingsMacroRequiresCaloriesTitle =>
      'Configura primero tus calorías';

  @override
  String get settingsMacroRequiresCaloriesMessage =>
      'Configura tus calorías diarias antes de definir una distribución de macros.';

  @override
  String get settingsMacroRequiresCaloriesSetNow => 'Configurar calorías ahora';

  @override
  String get settingsMacroRequiresCaloriesSkip => 'Omitir por ahora';

  @override
  String get calorieTargetSheetTitle => 'Configura tus calorías diarias';

  @override
  String get calorieTargetSheetSubtitle =>
      'Elige el objetivo que quieres controlar cada día.';

  @override
  String get calorieTargetCalculatorLink =>
      '¿No sabes cuántas calorías necesitas?';

  @override
  String calorieTargetRangeValidationError(int min, int max) {
    return 'Introduce un objetivo de $min a $max Kcal.';
  }

  @override
  String get calorieTargetIncreaseTooltip => 'Aumentar';

  @override
  String get calorieTargetDecreaseTooltip => 'Disminuir';

  @override
  String get calorieSetupHeadlinePrefix => 'Configura tus';

  @override
  String get calorieSetupHeadlineMain => 'calorías diarias';

  @override
  String get calorieSetupHeadlineBadge => 'Aquí.';

  @override
  String get calorieCouldNotSaveCalories =>
      'No se pudieron guardar tus calorías. Inténtalo de nuevo.';

  @override
  String get calorieCouldNotSaveMacros =>
      'No se pudieron guardar tus macros. Inténtalo de nuevo.';

  @override
  String get postCalorieSaveTitle => 'Calorías guardadas';

  @override
  String postCalorieSaveTarget(int calories) {
    return 'Tu objetivo diario es $calories Kcal.';
  }

  @override
  String get postCalorieSaveMacroQuestion =>
      '¿Quieres controlar también proteína, carbohidratos y grasa?';

  @override
  String get postCalorieSaveSetMacroDistribution =>
      'Configurar distribución de macros';

  @override
  String get postCalorieSaveNotNow => 'Ahora no';

  @override
  String get calorieMacroPromptTitle => '¿Añadir macros?';

  @override
  String calorieMacroPromptMessage(int calories) {
    return 'Elige un reparto simple de proteína, carbohidratos y grasa para $calories Kcal.';
  }

  @override
  String get calorieMacroPromptConfigure => 'Configurar';

  @override
  String get calorieMacroPromptSkip => 'Omitir por ahora';

  @override
  String get calorieCalculatorChooseYourMacrosTitle => 'Elige tus macros';

  @override
  String get calorieWizardCheckDetailsTitle => 'Revisa tus datos';

  @override
  String get calorieWizardContinue => 'Continuar';

  @override
  String get calorieWizardUseEstimate => 'Usar esta estimación';

  @override
  String get calorieWizardSexTitle => '¿Cuál es tu sexo biológico?';

  @override
  String get calorieWizardSexSubtitle =>
      'Esto mantiene la estimación de calorías alineada con la fórmula.';

  @override
  String get calorieWizardSexMale => 'Hombre';

  @override
  String get calorieWizardSexMaleMessage => 'Usa el coeficiente BMR masculino.';

  @override
  String get calorieWizardSexFemale => 'Mujer';

  @override
  String get calorieWizardSexFemaleMessage =>
      'Usa el coeficiente BMR femenino.';

  @override
  String get calorieWizardBirthdayTitle => '¿Cuándo es tu cumpleaños?';

  @override
  String get calorieWizardBirthdayMonth => 'Mes';

  @override
  String get calorieWizardBirthdayDay => 'Día';

  @override
  String get calorieWizardBirthdayYear => 'Año';

  @override
  String get calorieWizardBirthdayValidationError =>
      'Elige un cumpleaños para edades de 18 a 100 años.';

  @override
  String get calorieWizardHeightTitle => '¿Cuánto mides?';

  @override
  String get calorieWizardHeightValidationError =>
      'Introduce una altura de 120 a 230 cm.';

  @override
  String get calorieWizardWeightTitle => '¿Cuál es tu peso actual?';

  @override
  String get calorieWizardWeightValidationError =>
      'Introduce un peso de 35 a 250 kg.';

  @override
  String get calorieWizardProfileValidationError =>
      'Introduce edad, altura y peso dentro de los rangos esperados.';

  @override
  String get calorieWizardGoalTitle => '¿Cuál es tu objetivo principal?';

  @override
  String get calorieWizardGoalSubtitle =>
      'Elige el resultado que quieres que apoye tu objetivo.';

  @override
  String get calorieWizardGoalLoseWeight => 'Perder peso';

  @override
  String get calorieWizardGoalLoseWeightMessage =>
      'Estima un déficit desde mantenimiento.';

  @override
  String get calorieWizardGoalGainMuscle => 'Ganar músculo';

  @override
  String get calorieWizardGoalGainMuscleMessage =>
      'Estima un superávit calórico controlado.';

  @override
  String get calorieWizardGoalMaintainWeight => 'Mantener peso';

  @override
  String get calorieWizardGoalMaintainWeightMessage =>
      'Controla cerca de tu mantenimiento estimado.';

  @override
  String get calorieWizardLossPaceTitle =>
      '¿Qué tan rápido quieres perder peso?';

  @override
  String get calorieWizardGainPaceTitle =>
      '¿Qué tan rápido quieres ganar peso?';

  @override
  String get calorieWizardPaceSubtitle =>
      'Un ritmo más estable es más fácil de sostener.';

  @override
  String get calorieWizardPaceSlow => 'Lento';

  @override
  String get calorieWizardPaceSlowMessage =>
      'Más fácil de mantener y mejor para el rendimiento.';

  @override
  String get calorieWizardPaceModerate => 'Moderado';

  @override
  String get calorieWizardPaceModerateMessage =>
      'Opción recomendada para la mayoría.';

  @override
  String get calorieWizardPaceAggressive => 'Agresivo';

  @override
  String get calorieWizardLossPaceAggressiveMessage =>
      'Déficit mayor. Úsalo solo si puedes recuperarte bien.';

  @override
  String get calorieWizardPaceLean => 'Ligero';

  @override
  String get calorieWizardPaceLeanMessage =>
      'Superávit pequeño para minimizar la ganancia de grasa.';

  @override
  String get calorieWizardPaceStandard => 'Estándar';

  @override
  String get calorieWizardPaceStandardMessage =>
      'Opción recomendada para la mayoría al ganar músculo.';

  @override
  String get calorieWizardGainPaceAggressiveMessage =>
      'Superávit mayor con más riesgo de ganar grasa.';

  @override
  String get calorieWizardActivityTitle => '¿Cuál es tu nivel de actividad?';

  @override
  String get calorieWizardActivitySubtitle =>
      'Elige la opción que mejor encaje con una semana normal.';

  @override
  String get calorieWizardActivitySedentary => 'Sedentario';

  @override
  String get calorieWizardActivitySedentaryMessage =>
      'Mayormente sentado, poco movimiento diario y 0-1 entrenamientos ligeros por semana.';

  @override
  String get calorieWizardActivityLightlyActive => 'Actividad ligera';

  @override
  String get calorieWizardActivityLightlyActiveMessage =>
      'Paseos habituales o ejercicio ligero 1-3 días por semana.';

  @override
  String get calorieWizardActivityModeratelyActive => 'Actividad moderada';

  @override
  String get calorieWizardActivityModeratelyActiveMessage =>
      'Entrenas 3-5 días por semana o tienes una rutina bastante activa.';

  @override
  String get calorieWizardActivityVeryActive => 'Muy activo';

  @override
  String get calorieWizardActivityVeryActiveMessage =>
      'Ejercicio intenso casi todos los días o trabajo activo con entrenamiento regular.';

  @override
  String get calorieWizardActivitySuperActive => 'Súper activo';

  @override
  String get calorieWizardActivitySuperActiveMessage =>
      'Carga de atleta, dobles sesiones o trabajo físico exigente.';

  @override
  String get calorieWizardBackTooltip => 'Atrás';

  @override
  String get calorieWizardCloseTooltip => 'Cerrar';

  @override
  String get calorieWizardLoadingTitle =>
      'Personalizando tu plan de calorías...';

  @override
  String get calorieWizardLoadingMessage =>
      'Creando un objetivo a partir de tu perfil y actividad.';

  @override
  String get calorieWizardResultTitle =>
      'Tu plan personalizado de calorías está listo.';

  @override
  String get calorieWizardResultBmr => 'Metabolismo basal';

  @override
  String get calorieWizardResultMaintenance => 'Mantenimiento';

  @override
  String get calorieWizardResultTargetRange => 'Rango objetivo';

  @override
  String get calorieWizardResultAdjustment => 'Ajuste';

  @override
  String calorieWizardTargetRangeValue(int min, int max) {
    return '$min-$max Kcal';
  }

  @override
  String get calorieWizardEstimateNoteTitle => 'Nota de la estimación';

  @override
  String get macroSheetTitle => 'Configura tus macros';

  @override
  String macroDailyTarget(int calories) {
    return 'Objetivo diario: $calories Kcal';
  }

  @override
  String get macroSaveMacros => 'Guardar macros';

  @override
  String get macroPersonalizedTitle => 'Macros personalizados';

  @override
  String get macroSavePersonalized => 'Guardar macros personalizados';

  @override
  String get macroPercentagesTab => 'Porcentajes';

  @override
  String get macroGramsTab => 'Gramos';

  @override
  String get macroPresetBalanced => 'Equilibrado';

  @override
  String get macroPresetHighProtein => 'Alta proteína';

  @override
  String get macroPresetLowerCarb => 'Bajo en carbohidratos';

  @override
  String get macroPersonalized => 'Personalizados';

  @override
  String get macroCreateOwnSplit => 'Crea tu propio reparto';

  @override
  String get macroPercentagesOrGrams => 'Porcentajes o gramos';

  @override
  String get macroPersonalizedPercentages => 'Porcentajes personalizados';

  @override
  String get macroPersonalizedGrams => 'Gramos personalizados';

  @override
  String macroProteinPercentSummary(int percent) {
    return '$percent % proteína';
  }

  @override
  String macroCarbsPercentSummary(int percent) {
    return '$percent % carbohidratos';
  }

  @override
  String macroFatPercentSummary(int percent) {
    return '$percent % grasa';
  }

  @override
  String macroProteinGramsSummary(String grams) {
    return '$grams g proteína';
  }

  @override
  String macroCarbsGramsSummary(String grams) {
    return '$grams g carbohidratos';
  }

  @override
  String macroFatGramsSummary(String grams) {
    return '$grams g grasa';
  }

  @override
  String macroGramTriplet(String protein, String carbs, String fat) {
    return '$protein g · $carbs g · $fat g';
  }

  @override
  String macroPercentagesWithGramsSummary(String percentages, String grams) {
    return '$percentages ($grams)';
  }

  @override
  String get macroPercentagesMustTotal => 'Los porcentajes deben sumar 100 %';

  @override
  String macroPercentagesTotalMessage(int total) {
    return 'Suman $total %. Ajusta un macro o restablece el equilibrado antes de guardar.';
  }

  @override
  String get macroAdjustProtein => 'Ajustar proteína';

  @override
  String get macroAdjustCarbs => 'Ajustar carbohidratos';

  @override
  String get macroAdjustFat => 'Ajustar grasa';

  @override
  String get macroResetBalanced => 'Restablecer equilibrado';

  @override
  String get macroGramsTooHigh => 'Los gramos de macros son demasiado altos';

  @override
  String get macroGramsTooHighMessage =>
      'Cada macro debe ser de 2000 g o menos.';

  @override
  String get macroSmallCalorieMismatch => 'Pequeño desajuste de calorías';

  @override
  String get macroCaloriesDoNotMatch =>
      'Los macros no coinciden con las calorías';

  @override
  String macroGramMismatchOverMessage(int macroCalories, int delta) {
    return 'Estos gramos suman $macroCalories Kcal, $delta Kcal por encima de tu objetivo.';
  }

  @override
  String macroGramMismatchUnderMessage(int macroCalories, int delta) {
    return 'Estos gramos suman $macroCalories Kcal, $delta Kcal por debajo de tu objetivo.';
  }

  @override
  String get macroUsePercentages => 'Usar porcentajes';

  @override
  String get dashboardCouldNotLoadToday => 'No se pudo cargar el día';

  @override
  String get dashboardGreetingMorning => '¡Buenos días!';

  @override
  String get dashboardGreetingAfternoon => '¡Buenas tardes!';

  @override
  String get dashboardGreetingNight => '¡Buenas noches!';

  @override
  String get dashboardDailyProgress => 'Tu progreso\ndiario';

  @override
  String get dashboardTodayCalories => 'Calorías de hoy';

  @override
  String get dashboardCaloriesLeft => 'restantes';

  @override
  String dashboardGoalLine(int calories, int glasses) {
    return 'Objetivo $calories Kcal, $glasses vasos';
  }

  @override
  String get dashboardTodayLower => 'hoy';

  @override
  String get dashboardNoMealsLoggedToday => 'No hay comidas registradas hoy';

  @override
  String get dashboardNoMealsMessage =>
      'Tus comidas registradas aparecerán aquí.';

  @override
  String get dashboardEditIngredientsTooltip => 'Editar ingredientes';

  @override
  String get dashboardDeleteMealTooltip => 'Eliminar comida';

  @override
  String get dashboardCouldNotDeleteMeal => 'No se pudo eliminar la comida.';

  @override
  String get monthJan => 'ene';

  @override
  String get monthFeb => 'feb';

  @override
  String get monthMar => 'mar';

  @override
  String get monthApr => 'abr';

  @override
  String get monthMay => 'may';

  @override
  String get monthJun => 'jun';

  @override
  String get monthJul => 'jul';

  @override
  String get monthAug => 'ago';

  @override
  String get monthSep => 'sept';

  @override
  String get monthOct => 'oct';

  @override
  String get monthNov => 'nov';

  @override
  String get monthDec => 'dic';

  @override
  String get dayMon => 'Lun';

  @override
  String get dayTue => 'Mar';

  @override
  String get dayWed => 'Mié';

  @override
  String get dayThu => 'Jue';

  @override
  String get dayFri => 'Vie';

  @override
  String get daySat => 'Sáb';

  @override
  String get daySun => 'Dom';

  @override
  String get historyTitle => 'Estadísticas';

  @override
  String get historySubtitle => 'Calorías e historial de comidas';

  @override
  String get historyCouldNotLoadHistory => 'No se pudo cargar el historial';

  @override
  String get historyLoggedMeals => 'Comidas registradas';

  @override
  String historyMealCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comidas',
      one: '1 comida',
      zero: '0 comidas',
    );
    return '$_temp0';
  }

  @override
  String get historyNoMealsLogged => 'No hay comidas registradas';

  @override
  String get historyNoMealsMessage =>
      'Los detalles aparecerán después de registrar comidas.';

  @override
  String get historyDeleteMealTitle => '¿Eliminar comida?';

  @override
  String historyTargetCalories(int calories) {
    return 'Objetivo: $calories Kcal';
  }

  @override
  String historySelectDaySemantics(String label) {
    return 'Seleccionar $label';
  }

  @override
  String get templatesTitle => 'Comidas habituales';

  @override
  String get templatesSubtitle => 'Plantillas familiares seguras';

  @override
  String get templatesAddTooltip => 'Añadir comida habitual';

  @override
  String get templatesExplainer =>
      'Las comidas habituales son comidas de confianza que puedes registrar rápido.';

  @override
  String get templatesCouldNotLoad =>
      'No se pudieron cargar las comidas habituales';

  @override
  String get templatesNoUsualMealsYet => 'Aún no hay comidas habituales';

  @override
  String get templatesNoUsualMealsMessage =>
      'Tus comidas guardadas aparecerán aquí.';

  @override
  String get templatesDeleteUsualMealTitle => '¿Eliminar comida habitual?';

  @override
  String get templatesNewUsualMealTitle => 'Nueva comida habitual';

  @override
  String get templatesTitleLabel => 'Título';

  @override
  String get templatesAliasesLabel => 'Alias, separados por comas';

  @override
  String get templatesNoAliasesYet => 'Sin alias todavía';

  @override
  String get voiceTitle => 'Registrar comida';

  @override
  String get voiceStartOver => 'Empezar de nuevo';

  @override
  String get voiceTranscribingTitle => 'Transcribiendo...';

  @override
  String get voiceTranscribingMessage => 'Escuchando y preparando el texto.';

  @override
  String get voiceClarificationTitle => 'Necesita un poco más de detalle';

  @override
  String get voiceClarificationDefault =>
      'Añade un poco más de detalle y envíalo otra vez.';

  @override
  String get voiceFoodMatches => 'Coincidencias de alimentos';

  @override
  String get voiceNoConfidentMatchYet => 'Aún no hay una coincidencia clara';

  @override
  String get voiceNoDatabaseMatch =>
      'No hay coincidencias en la base de datos para este ingrediente. Repítelo o reformúlalo.';

  @override
  String get voiceRecordingTitle => 'Grabando';

  @override
  String get voiceIntakeTitle => 'Entrada por voz';

  @override
  String get voiceTapStopWhenDone => 'Toca detener cuando termines.';

  @override
  String get voiceSayMealNaturally => 'Di tu comida con naturalidad.';

  @override
  String get voiceMealFilledWithVoice => 'La comida se rellenará con tu voz.';

  @override
  String get voiceStopRecordingTooltip => 'Detener grabación';

  @override
  String get voiceRecordVoiceTooltip => 'Grabar voz';

  @override
  String get voiceRecordingIndicator =>
      'Grabando. Toca detener cuando termines.';

  @override
  String get voiceErrorTitle => 'Algo salió mal';

  @override
  String get voiceLoggedMessage =>
      'Registrado. Puedes corregirlo desde el historial.';

  @override
  String get voiceMessageMealLogged => 'Comida registrada.';

  @override
  String get voiceMessageProposalUpdated => 'Propuesta actualizada.';

  @override
  String get voiceMessageMealProposalCreated => 'Propuesta de comida creada.';

  @override
  String get voiceChangesApplied => 'Cambios aplicados';

  @override
  String get voiceTodaySection => 'Hoy';

  @override
  String get voiceMealsSection => 'Comidas';

  @override
  String get voiceNutritionMatchesSection => 'Coincidencias nutricionales';

  @override
  String get voiceUsualMealsSection => 'Comidas habituales';

  @override
  String get voiceNoMealsYet => 'Aún no hay comidas';

  @override
  String get voiceNoMealsMessage => 'Tus comidas registradas aparecerán aquí.';

  @override
  String voiceItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '1 elemento',
      zero: '0 elementos',
    );
    return '$_temp0';
  }

  @override
  String get voiceStateListening => 'Escuchando';

  @override
  String get voiceStateSavingAudio => 'Guardando audio';

  @override
  String get voiceStateWhisperTranscription => 'Transcripción de Whisper';

  @override
  String get voiceStateTranscriptReady => 'Transcripción lista';

  @override
  String get voiceStateBuildingProposal => 'Preparando propuesta';

  @override
  String get voiceStateReviewMeal => 'Revisar comida';

  @override
  String get voiceStateLogged => 'Registrado';

  @override
  String get voiceStateResultReady => 'Resultado listo';

  @override
  String get voiceStateClarification => 'Aclaración';

  @override
  String get voiceStateNeedsAttention => 'Necesita atención';

  @override
  String get voiceStateInput => 'Entrada por voz o texto';

  @override
  String get mealLabelQuestion => '¿Qué tipo de comida es?';

  @override
  String get mealLabelHelper => 'Esto ayuda a organizar tu día.';

  @override
  String get mealLabelBreakfast => 'Desayuno';

  @override
  String get mealLabelLunch => 'Almuerzo';

  @override
  String get mealLabelDinner => 'Cena';

  @override
  String get mealLabelSnack => 'Snack';

  @override
  String get mealLabelPreWorkout => 'Pre-entreno';

  @override
  String get mealLabelPostWorkout => 'Post-entreno';

  @override
  String get mealLabelOther => 'Otro';

  @override
  String get mealLabelNone => 'Ninguno';

  @override
  String get mealLabelCustomType => 'Tipo personalizado';

  @override
  String get mealLabelOtherPlaceholder => 'Brunch';

  @override
  String get mealLabelSave => 'Guardar etiqueta';

  @override
  String get mealLabelSkip => 'Omitir';

  @override
  String get mealProposalReadyToLog => 'Listo para registrar';

  @override
  String get mealProposalConfirm => 'Confirmar';

  @override
  String get mealConfirmationEmbedded =>
      'La confirmación de comida está integrada en el flujo de registro.';
}
