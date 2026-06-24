/// Canonical demographic buckets — mirrors `@dkmads/shared` / `packages/sdk-core`.

const standardAgeRanges = [
  '18-24',
  '25-34',
  '35-44',
  '45-54',
  '55-64',
  '65+',
  'unknown',
];

const standardGenderValues = ['male', 'female', 'other', 'unknown'];

const demographicAgeRangeKey = 'demographic.age_range';
const demographicGenderKey = 'demographic.gender';
const minAdTargetAge = 18;

int ageFromDateOfBirth(DateTime dob, [DateTime? asOf]) {
  final ref = asOf ?? DateTime.now();
  var age = ref.year - dob.year;
  if (ref.month < dob.month || (ref.month == dob.month && ref.day < dob.day)) {
    age -= 1;
  }
  return age;
}

String ageRangeFromAge(int age) {
  if (age < minAdTargetAge) return 'unknown';
  if (age <= 24) return '18-24';
  if (age <= 34) return '25-34';
  if (age <= 44) return '35-44';
  if (age <= 54) return '45-54';
  if (age <= 64) return '55-64';
  return '65+';
}

String ageRangeFromDateOfBirth(DateTime dob, [DateTime? asOf]) {
  return ageRangeFromAge(ageFromDateOfBirth(dob, asOf));
}

String? normalizeAgeRange(String? value) {
  final v = value?.trim();
  if (v == null || v.isEmpty) return null;
  return standardAgeRanges.contains(v) ? v : null;
}

String? normalizeGender(String? value) {
  final v = value?.trim().toLowerCase();
  if (v == null || v.isEmpty) return null;
  return standardGenderValues.contains(v) ? v : null;
}
