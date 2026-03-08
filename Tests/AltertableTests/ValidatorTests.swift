//
//  ValidatorTests.swift
//  AltertableTests
//

@testable import Altertable
import XCTest

final class ValidatorTests: XCTestCase {
    // MARK: - Valid IDs

    func testValidUserId() {
        XCTAssertNoThrow(try Validator.validateUserId("user_123"))
        XCTAssertNoThrow(try Validator.validateUserId("abc"))
        XCTAssertNoThrow(try Validator.validateUserId(String(repeating: "a", count: 1024)))
    }

    // MARK: - Empty / whitespace

    func testEmptyUserIdThrows() {
        XCTAssertThrowsError(try Validator.validateUserId("")) { error in
            XCTAssertEqual(error as? ValidationError, .emptyUserId)
        }
    }

    func testWhitespaceOnlyUserIdThrows() {
        XCTAssertThrowsError(try Validator.validateUserId("   ")) { error in
            XCTAssertEqual(error as? ValidationError, .emptyUserId)
        }
    }

    // MARK: - Reserved IDs (case-insensitive)

    func testReservedCaseInsensitiveIdThrows() {
        for id in ["anonymous", "Anonymous", "ANONYMOUS", "guest", "user", "visitor", "null"] {
            XCTAssertThrowsError(try Validator.validateUserId(id), "Expected \(id) to be rejected") { error in
                guard case .reservedUserId = error as? ValidationError else {
                    return XCTFail("Expected .reservedUserId for \(id)")
                }
            }
        }
    }

    // MARK: - Reserved IDs (case-sensitive exact match)

    func testReservedExactIdThrows() {
        for id in ["[object Object]", "0", "NaN", "none", "None"] {
            XCTAssertThrowsError(try Validator.validateUserId(id), "Expected \(id) to be rejected") { error in
                guard case .reservedUserId = error as? ValidationError else {
                    return XCTFail("Expected .reservedUserId for \(id)")
                }
            }
        }
    }

    func testCaseSensitiveExactMatchDoesNotRejectVariants() {
        // "NaN" is reserved but "nan" and "NAN" are not exact matches and are not in the case-insensitive list.
        XCTAssertNoThrow(try Validator.validateUserId("nan"))
        XCTAssertNoThrow(try Validator.validateUserId("NAN"))
    }

    // MARK: - Length

    func testTooLongUserIdThrows() {
        XCTAssertThrowsError(try Validator.validateUserId(String(repeating: "a", count: 1025))) { error in
            XCTAssertEqual(error as? ValidationError, .userIdTooLong)
        }
    }

    func testExactMaxLengthIsAccepted() {
        XCTAssertNoThrow(try Validator.validateUserId(String(repeating: "a", count: 1024)))
    }
}
