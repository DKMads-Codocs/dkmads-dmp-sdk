import 'package:flutter_test/flutter_test.dart';
import 'package:dkmads_dmp/demographics.dart';

void main() {
  final asOf = DateTime(2026, 6, 18);

  test('ageRangeFromDateOfBirth maps to canonical bucket', () {
    expect(
      ageRangeFromDateOfBirth(DateTime(1992, 3, 15), asOf),
      '25-34',
    );
  });

  test('ageRangeFromAge under 18 returns unknown', () {
    expect(ageRangeFromAge(17), 'unknown');
  });

  test('normalizeAgeRange rejects non-canonical values', () {
    expect(normalizeAgeRange('19-26'), isNull);
    expect(normalizeAgeRange('25-34'), '25-34');
  });

  test('normalizeGender lowercases and validates', () {
    expect(normalizeGender('Male'), 'male');
    expect(normalizeGender('nonbinary'), isNull);
  });

  test('demographic keys match shared contract', () {
    expect(demographicAgeRangeKey, 'demographic.age_range');
    expect(demographicGenderKey, 'demographic.gender');
  });
}
