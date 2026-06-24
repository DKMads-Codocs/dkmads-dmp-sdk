#if UNITY_INCLUDE_TESTS
using NUnit.Framework;
using DKMads.DMP;

namespace DKMads.DMP.Tests
{
    public class DemographicsTests
    {
        private static readonly System.DateTime AsOf = new System.DateTime(2026, 6, 18, 0, 0, 0, System.DateTimeKind.Utc);

        [Test]
        public void AgeRangeFromDateOfBirth_mapsToCanonicalBucket()
        {
            var dob = new System.DateTime(1992, 3, 15, 0, 0, 0, System.DateTimeKind.Utc);
            Assert.AreEqual("25-34", Demographics.AgeRangeFromDateOfBirth(dob, AsOf));
        }

        [Test]
        public void AgeRangeFromAge_under18_returnsUnknown()
        {
            Assert.AreEqual("unknown", Demographics.AgeRangeFromAge(17));
        }

        [Test]
        public void NormalizeAgeRange_rejectsNonCanonical()
        {
            Assert.IsNull(Demographics.NormalizeAgeRange("19-26"));
            Assert.AreEqual("25-34", Demographics.NormalizeAgeRange("25-34"));
        }

        [Test]
        public void DemographicKeys_matchSharedContract()
        {
            Assert.AreEqual("demographic.age_range", Demographics.DemographicAgeRangeKey);
            Assert.AreEqual("demographic.gender", Demographics.DemographicGenderKey);
        }
    }
}
#endif
