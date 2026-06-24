import XCTest
@testable import DKMadsDMP

final class DemographicsTests: XCTestCase {
    private var calendar: Calendar!
    private var asOf: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        asOf = calendar.date(from: DateComponents(year: 2026, month: 6, day: 18))!
    }

    func testAgeRangeFromDateOfBirth_mapsToCanonicalBucket() {
        let dob = calendar.date(from: DateComponents(year: 1992, month: 3, day: 15))!
        XCTAssertEqual(DMPDemographics.ageRangeFromDateOfBirth(dob, asOf: asOf), "25-34")
    }

    func testAgeRangeFromAge_under18_returnsUnknown() {
        XCTAssertEqual(DMPDemographics.ageRangeFromAge(17), "unknown")
    }

    func testNormalizeAgeRange_rejectsNonCanonical() {
        XCTAssertNil(DMPDemographics.normalizeAgeRange("19-26"))
        XCTAssertEqual(DMPDemographics.normalizeAgeRange("25-34"), "25-34")
    }

    func testNormalizeGender_lowercasesAndValidates() {
        XCTAssertEqual(DMPDemographics.normalizeGender("Male"), "male")
        XCTAssertNil(DMPDemographics.normalizeGender("nonbinary"))
    }

    func testDemographicKeys_matchSharedContract() {
        XCTAssertEqual(DMPDemographics.demographicAgeRangeKey, "demographic.age_range")
        XCTAssertEqual(DMPDemographics.demographicGenderKey, "demographic.gender")
    }
}
