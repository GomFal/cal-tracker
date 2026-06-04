import 'package:cal_tracker_mobile/ui/features/dashboard/models/calorie_target_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validation constants', () {
    test('calorie limits are reasonable', () {
      expect(kMinDailyCalories, lessThan(kMaxDailyCalories));
      expect(kMinDailyCalories, 800);
      expect(kMaxDailyCalories, 10000);
    });

    test('age limits are reasonable', () {
      expect(kMinAgeYears, lessThan(kMaxAgeYears));
      expect(kMinAgeYears, 18);
      expect(kMaxAgeYears, 100);
    });

    test('height limits are reasonable', () {
      expect(kMinHeightCm, lessThan(kMaxHeightCm));
      expect(kMinHeightCm, 120);
      expect(kMaxHeightCm, 230);
    });

    test('weight limits are reasonable', () {
      expect(kMinWeightKg, lessThan(kMaxWeightKg));
      expect(kMinWeightKg, 35);
      expect(kMaxWeightKg, 250);
    });
  });

  group('isValidAge', () {
    test('returns true for valid ages', () {
      expect(isValidAge(18), isTrue);
      expect(isValidAge(30), isTrue);
      expect(isValidAge(50), isTrue);
      expect(isValidAge(100), isTrue);
    });

    test('returns false for invalid ages', () {
      expect(isValidAge(0), isFalse);
      expect(isValidAge(17), isFalse);
      expect(isValidAge(101), isFalse);
    });
  });

  group('isValidHeightCm', () {
    test('returns true for valid heights', () {
      expect(isValidHeightCm(120), isTrue);
      expect(isValidHeightCm(170), isTrue);
      expect(isValidHeightCm(230), isTrue);
    });

    test('returns false for invalid heights', () {
      expect(isValidHeightCm(0), isFalse);
      expect(isValidHeightCm(119), isFalse);
      expect(isValidHeightCm(231), isFalse);
    });
  });

  group('isValidWeightKg', () {
    test('returns true for valid weights', () {
      expect(isValidWeightKg(35), isTrue);
      expect(isValidWeightKg(70), isTrue);
      expect(isValidWeightKg(250), isTrue);
    });

    test('returns false for invalid weights', () {
      expect(isValidWeightKg(0), isFalse);
      expect(isValidWeightKg(34), isFalse);
      expect(isValidWeightKg(251), isFalse);
    });
  });

  group('isValidCalories', () {
    test('returns true for valid calorie targets', () {
      expect(isValidCalories(800), isTrue);
      expect(isValidCalories(2000), isTrue);
      expect(isValidCalories(10000), isTrue);
    });

    test('returns false for invalid calorie targets', () {
      expect(isValidCalories(0), isFalse);
      expect(isValidCalories(799), isFalse);
      expect(isValidCalories(10001), isFalse);
    });
  });

  group('validateProfileValues', () {
    test('returns true when all values are valid', () {
      expect(
        validateProfileValues(
          const ProfileValues(age: 30, heightCm: 170, weightKg: 70),
        ),
        isTrue,
      );
    });

    test('returns false when age is invalid', () {
      expect(
        validateProfileValues(
          const ProfileValues(age: 15, heightCm: 170, weightKg: 70),
        ),
        isFalse,
      );
    });

    test('returns false when height is invalid', () {
      expect(
        validateProfileValues(
          const ProfileValues(age: 30, heightCm: 50, weightKg: 70),
        ),
        isFalse,
      );
    });

    test('returns false when weight is invalid', () {
      expect(
        validateProfileValues(
          const ProfileValues(age: 30, heightCm: 170, weightKg: 500),
        ),
        isFalse,
      );
    });
  });

  group('today', () {
    test('returns date at midnight', () {
      final now = DateTime(2026, 6, 4, 15, 30, 0);
      final d = today(now);
      expect(d.year, 2026);
      expect(d.month, 6);
      expect(d.day, 4);
      expect(d.hour, 0);
      expect(d.minute, 0);
      expect(d.second, 0);
    });
  });

  group('youngestAllowedBirthDate', () {
    test('returns date kMinAgeYears ago', () {
      final now = DateTime(2026, 6, 4);
      final d = youngestAllowedBirthDate(now);
      expect(d.year, 2026 - kMinAgeYears);
      expect(d.month, 6);
      expect(d.day, 4);
    });
  });

  group('oldestAllowedBirthDate', () {
    test('returns date kMaxAgeYears ago', () {
      final now = DateTime(2026, 6, 4);
      final d = oldestAllowedBirthDate(now);
      expect(d.year, 2026 - kMaxAgeYears);
      expect(d.month, 6);
      expect(d.day, 4);
    });
  });

  group('defaultBirthDate', () {
    test('returns date 30 years ago from now', () {
      final now = DateTime(2026, 6, 4);
      final d = defaultBirthDate(now);
      expect(d.year, 1996);
      expect(d.month, 6);
      expect(d.day, 4);
    });
  });

  group('daysInMonth', () {
    test('returns correct days for January', () {
      expect(daysInMonth(2026, 1), 31);
    });

    test('returns correct days for February non-leap', () {
      expect(daysInMonth(2025, 2), 28);
    });

    test('returns correct days for February leap', () {
      expect(daysInMonth(2024, 2), 29);
    });
  });

  group('clampBirthDate', () {
    final oldest = DateTime(1926, 6, 4);
    final youngest = DateTime(2008, 6, 4);

    test('returns date as-is when within range', () {
      final date = DateTime(1970, 1, 1);
      expect(clampBirthDate(date, oldest: oldest, youngest: youngest), date);
    });

    test('returns oldest when date is before oldest', () {
      final date = DateTime(1900, 1, 1);
      expect(clampBirthDate(date, oldest: oldest, youngest: youngest), oldest);
    });

    test('returns youngest when date is after youngest', () {
      final date = DateTime(2020, 1, 1);
      expect(clampBirthDate(date, oldest: oldest, youngest: youngest), youngest);
    });
  });

  group('safeBirthDate', () {
    final oldest = DateTime(1926, 6, 4);
    final youngest = DateTime(2008, 6, 4);

    test('returns valid date for normal inputs', () {
      final date = safeBirthDate(
        year: 1980,
        month: 6,
        day: 15,
        oldest: oldest,
        youngest: youngest,
      );
      expect(date.year, 1980);
      expect(date.month, 6);
      expect(date.day, 15);
    });

    test('clamps day to month max within range', () {
      final date = safeBirthDate(
        year: 1996,
        month: 2,
        day: 31,
        oldest: oldest,
        youngest: youngest,
      );
      // 1996 is a leap year, so February has 29 days.
      // Day is clamped from 31 to 29.
      expect(date.year, 1996);
      expect(date.month, 2);
      expect(date.day, 29);
    });
  });

  group('ageFromBirthDate', () {
    test('returns correct age before birthday this year', () {
      final birthDate = DateTime(1990, 12, 31);
      final now = DateTime(2026, 6, 4);
      expect(ageFromBirthDate(birthDate, now), 35);
    });

    test('returns correct age after birthday this year', () {
      final birthDate = DateTime(1990, 1, 1);
      final now = DateTime(2026, 6, 4);
      expect(ageFromBirthDate(birthDate, now), 36);
    });

    test('returns correct age on birthday', () {
      final birthDate = DateTime(1990, 6, 4);
      final now = DateTime(2026, 6, 4);
      expect(ageFromBirthDate(birthDate, now), 36);
    });
  });

  group('birthYearValues', () {
    test('returns correct range of years', () {
      // With kMinAgeYears=18, kMaxAgeYears=100, and now=2026:
      // oldest = 2026-100 = 1926
      // youngest = 2026-18 = 2008
      // years = 1926..2008 inclusive = 83 values
      final now = DateTime(2026, 6, 4);
      final years = birthYearValues(now);
      expect(years.length, 83);
      expect(years.first, 1926);
      expect(years.last, 2008);
    });
  });

  group('heightInCm', () {
    test('converts feet and inches to cm', () {
      final cm = heightInCm('5', '7');
      expect(cm, closeTo(170.18, 0.01));
    });

    test('returns null when feet is null', () {
      expect(heightInCm(null, '7'), isNull);
    });

    test('returns null when inches is null', () {
      expect(heightInCm('5', null), isNull);
    });

    test('returns null when feet is not a number', () {
      expect(heightInCm('abc', '7'), isNull);
    });
  });

  group('weightInKg', () {
    test('converts pounds to kg', () {
      final kg = weightInKg('154');
      expect(kg, closeTo(69.85, 0.01));
    });

    test('returns null when pounds is null', () {
      expect(weightInKg(null), isNull);
    });

    test('returns null when pounds is not a number', () {
      expect(weightInKg('abc'), isNull);
    });
  });

  group('formatCompactNumber', () {
    test('formats whole numbers as integers', () {
      expect(formatCompactNumber(70.0), '70');
    });

    test('formats fractional numbers with one decimal', () {
      expect(formatCompactNumber(69.5), '69.5');
    });
  });

  group('formatFeetAndInches', () {
    test('formats feet and inches correctly', () {
      expect(formatFeetAndInches(67), "5'7\"");
    });

    test('formats exactly 0 inches', () {
      expect(formatFeetAndInches(60), "5'0\"");
    });
  });
}
