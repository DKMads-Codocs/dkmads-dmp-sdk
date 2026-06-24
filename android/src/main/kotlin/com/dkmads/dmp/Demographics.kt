package com.dkmads.dmp

import java.time.LocalDate
import java.time.Period
import java.time.format.DateTimeParseException

/** Canonical demographic buckets — mirrors `@dkmads/shared` / `packages/sdk-core`. */
object Demographics {
    val STANDARD_AGE_RANGES = listOf(
        "18-24", "25-34", "35-44", "45-54", "55-64", "65+", "unknown",
    )
    val STANDARD_GENDER_VALUES = listOf("male", "female", "other", "unknown")
    const val DEMOGRAPHIC_AGE_RANGE_KEY = "demographic.age_range"
    const val DEMOGRAPHIC_GENDER_KEY = "demographic.gender"
    const val MIN_AD_TARGET_AGE = 18

    fun ageFromDateOfBirth(dob: LocalDate, asOf: LocalDate = LocalDate.now()): Int {
        return Period.between(dob, asOf).years
    }

    fun ageRangeFromAge(age: Int): String {
        if (age < MIN_AD_TARGET_AGE) return "unknown"
        if (age <= 24) return "18-24"
        if (age <= 34) return "25-34"
        if (age <= 44) return "35-44"
        if (age <= 54) return "45-54"
        if (age <= 64) return "55-64"
        return "65+"
    }

    fun ageRangeFromDateOfBirth(dob: LocalDate, asOf: LocalDate = LocalDate.now()): String {
        return ageRangeFromAge(ageFromDateOfBirth(dob, asOf))
    }

    fun ageRangeFromDateOfBirth(dob: String, asOf: LocalDate = LocalDate.now()): String? {
        return try {
            ageRangeFromDateOfBirth(LocalDate.parse(dob), asOf)
        } catch (_: DateTimeParseException) {
            null
        }
    }

    fun normalizeAgeRange(value: String?): String? {
        val v = value?.trim() ?: return null
        return if (STANDARD_AGE_RANGES.contains(v)) v else null
    }

    fun normalizeGender(value: String?): String? {
        val v = value?.trim()?.lowercase() ?: return null
        return if (STANDARD_GENDER_VALUES.contains(v)) v else null
    }
}
