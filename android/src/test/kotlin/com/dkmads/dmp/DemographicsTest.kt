package com.dkmads.dmp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

class DemographicsTest {
    private val asOf = LocalDate.of(2026, 6, 18)

    @Test
    fun ageRangeFromDateOfBirth_mapsToCanonicalBucket() {
        assertEquals("25-34", Demographics.ageRangeFromDateOfBirth(LocalDate.of(1992, 3, 15), asOf))
    }

    @Test
    fun ageRangeFromAge_under18_returnsUnknown() {
        assertEquals("unknown", Demographics.ageRangeFromAge(17))
    }

    @Test
    fun ageRangeFromDateOfBirth_string_invalidReturnsNull() {
        assertNull(Demographics.ageRangeFromDateOfBirth("not-a-date", asOf))
    }

    @Test
    fun normalizeAgeRange_rejectsNonCanonical() {
        assertNull(Demographics.normalizeAgeRange("19-26"))
        assertEquals("25-34", Demographics.normalizeAgeRange("25-34"))
    }

    @Test
    fun normalizeGender_lowercasesAndValidates() {
        assertEquals("male", Demographics.normalizeGender("Male"))
        assertNull(Demographics.normalizeGender("nonbinary"))
    }

    @Test
    fun demographicKeys_matchSharedContract() {
        assertEquals("demographic.age_range", Demographics.DEMOGRAPHIC_AGE_RANGE_KEY)
        assertEquals("demographic.gender", Demographics.DEMOGRAPHIC_GENDER_KEY)
    }
}
