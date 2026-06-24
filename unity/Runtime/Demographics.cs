using System;
using System.Collections.Generic;
using System.Globalization;

namespace DKMads.DMP
{
    /// <summary>Canonical demographic buckets — mirrors @dkmads/shared / packages/sdk-core.</summary>
    public static class Demographics
    {
        public static readonly string[] StandardAgeRanges =
        {
            "18-24", "25-34", "35-44", "45-54", "55-64", "65+", "unknown",
        };

        public static readonly string[] StandardGenderValues =
        {
            "male", "female", "other", "unknown",
        };

        public const string DemographicAgeRangeKey = "demographic.age_range";
        public const string DemographicGenderKey = "demographic.gender";
        public const int MinAdTargetAge = 18;

        public static int AgeFromDateOfBirth(DateTime dob, DateTime? asOf = null)
        {
            var refDate = asOf ?? DateTime.UtcNow;
            var age = refDate.Year - dob.Year;
            if (refDate.Month < dob.Month || (refDate.Month == dob.Month && refDate.Day < dob.Day))
                age -= 1;
            return age;
        }

        public static string AgeRangeFromAge(int age)
        {
            if (age < MinAdTargetAge) return "unknown";
            if (age <= 24) return "18-24";
            if (age <= 34) return "25-34";
            if (age <= 44) return "35-44";
            if (age <= 54) return "45-54";
            if (age <= 64) return "55-64";
            return "65+";
        }

        public static string AgeRangeFromDateOfBirth(DateTime dob, DateTime? asOf = null)
        {
            return AgeRangeFromAge(AgeFromDateOfBirth(dob, asOf));
        }

        public static string AgeRangeFromDateOfBirth(string dobIso, DateTime? asOf = null)
        {
            if (!DateTime.TryParse(dobIso, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var dob))
                return "unknown";
            return AgeRangeFromDateOfBirth(dob, asOf);
        }

        public static string NormalizeAgeRange(string value)
        {
            var v = value?.Trim();
            if (string.IsNullOrEmpty(v)) return null;
            return Array.IndexOf(StandardAgeRanges, v) >= 0 ? v : null;
        }

        public static string NormalizeGender(string value)
        {
            var v = value?.Trim().ToLowerInvariant();
            if (string.IsNullOrEmpty(v)) return null;
            return Array.IndexOf(StandardGenderValues, v) >= 0 ? v : null;
        }
    }
}
