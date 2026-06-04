// ------------------------------------------------------------------
// Validation range constants
// ------------------------------------------------------------------

const int kMinDailyCalories = 800;
const int kMaxDailyCalories = 10000;
const int kMinAgeYears = 18;
const int kMaxAgeYears = 100;
const int kMinHeightCm = 120;
const int kMaxHeightCm = 230;
const int kMinWeightKg = 35;
const int kMaxWeightKg = 250;

/// Input-transfer model for validated wizard profile values.
class ProfileValues {
  const ProfileValues({
    required this.age,
    required this.heightCm,
    required this.weightKg,
  });

  final int age;
  final double heightCm;
  final double weightKg;
}

/// ------------------------------------------------------------------
/// Pure validation helpers (no localisation / no side effects)
/// ------------------------------------------------------------------

bool isValidAge(int age) =>
    age >= kMinAgeYears && age <= kMaxAgeYears;

bool isValidHeightCm(double heightCm) =>
    heightCm >= kMinHeightCm && heightCm <= kMaxHeightCm;

bool isValidWeightKg(double weightKg) =>
    weightKg >= kMinWeightKg && weightKg <= kMaxWeightKg;

bool isValidCalories(int calories) =>
    calories >= kMinDailyCalories && calories <= kMaxDailyCalories;

bool validateProfileValues(ProfileValues values) =>
    isValidAge(values.age) &&
    isValidHeightCm(values.heightCm) &&
    isValidWeightKg(values.weightKg);

/// ------------------------------------------------------------------
/// Birth date helpers (pure, depend on [now])
/// ------------------------------------------------------------------

/// Returns today at midnight (date-only).
DateTime today(DateTime now) => DateTime(now.year, now.month, now.day);

DateTime youngestAllowedBirthDate(DateTime now) {
  final d = today(now);
  return DateTime(d.year - kMinAgeYears, d.month, d.day);
}

DateTime oldestAllowedBirthDate(DateTime now) {
  final d = today(now);
  return DateTime(d.year - kMaxAgeYears, d.month, d.day);
}

DateTime defaultBirthDate(DateTime now) {
  final d = today(now);
  return DateTime(d.year - 30, d.month, d.day);
}

int daysInMonth(int year, int month) =>
    DateTime(year, month + 1, 0).day;

DateTime clampBirthDate(
  DateTime date, {
  required DateTime oldest,
  required DateTime youngest,
}) {
  if (date.isBefore(oldest)) return oldest;
  if (date.isAfter(youngest)) return youngest;
  return date;
}

DateTime safeBirthDate({
  required int year,
  required int month,
  required int day,
  required DateTime oldest,
  required DateTime youngest,
}) {
  final safeDay = day.clamp(1, daysInMonth(year, month)).toInt();
  return clampBirthDate(DateTime(year, month, safeDay), oldest: oldest, youngest: youngest);
}

int ageFromBirthDate(DateTime birthDate, DateTime now) {
  final d = today(now);
  var age = d.year - birthDate.year;
  final hadBirthdayThisYear = d.month > birthDate.month ||
      (d.month == birthDate.month && d.day >= birthDate.day);
  if (!hadBirthdayThisYear) age -= 1;
  return age;
}

List<int> birthYearValues(DateTime now) {
  final oldest = oldestAllowedBirthDate(now).year;
  final youngest = youngestAllowedBirthDate(now).year;
  return List<int>.generate(
    youngest - oldest + 1,
    (index) => oldest + index,
  );
}

/// ------------------------------------------------------------------
/// Conversion helpers (pure)
/// ------------------------------------------------------------------

double? heightInCm(String? feet, String? inches) {
  final ft = double.tryParse(feet?.trim() ?? '');
  final inc = double.tryParse(inches?.trim() ?? '');
  if (ft == null || inc == null) return null;
  return (ft * 12 + inc) * 2.54;
}

double? weightInKg(String? pounds) {
  final lb = double.tryParse(pounds?.trim() ?? '');
  if (lb == null) return null;
  return lb * 0.45359237;
}

String formatCompactNumber(double value) {
  if ((value - value.roundToDouble()).abs() < 0.01) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

String formatFeetAndInches(double value) {
  final totalInches = value.round();
  final feet = totalInches ~/ 12;
  final inches = totalInches % 12;
  return '$feet\'$inches"';
}
