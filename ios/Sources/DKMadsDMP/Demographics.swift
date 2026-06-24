import Foundation

/// Canonical demographic buckets — mirrors `@dkmads/shared` / `packages/sdk-core`.
public enum DMPDemographics {
    public static let standardAgeRanges = [
        "18-24", "25-34", "35-44", "45-54", "55-64", "65+", "unknown",
    ]
    public static let standardGenderValues = ["male", "female", "other", "unknown"]
    public static let demographicAgeRangeKey = "demographic.age_range"
    public static let demographicGenderKey = "demographic.gender"
    public static let minAdTargetAge = 18

    public static func ageFromDateOfBirth(_ dob: Date, asOf: Date = Date()) -> Int {
        let cal = Calendar.current
        var age = cal.component(.year, from: asOf) - cal.component(.year, from: dob)
        let monthDiff = cal.component(.month, from: asOf) - cal.component(.month, from: dob)
        if monthDiff < 0 || (monthDiff == 0 && cal.component(.day, from: asOf) < cal.component(.day, from: dob)) {
            age -= 1
        }
        return age
    }

    public static func ageRangeFromAge(_ age: Int) -> String {
        if age < minAdTargetAge { return "unknown" }
        if age <= 24 { return "18-24" }
        if age <= 34 { return "25-34" }
        if age <= 44 { return "35-44" }
        if age <= 54 { return "45-54" }
        if age <= 64 { return "55-64" }
        return "65+"
    }

    public static func ageRangeFromDateOfBirth(_ dob: Date, asOf: Date = Date()) -> String {
        let age = ageFromDateOfBirth(dob, asOf: asOf)
        if age < 0 { return "unknown" }
        return ageRangeFromAge(age)
    }

    public static func normalizeAgeRange(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return standardAgeRanges.contains(v) ? v : nil
    }

    public static func normalizeGender(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return standardGenderValues.contains(v) ? v : nil
    }
}
