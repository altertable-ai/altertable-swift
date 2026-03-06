//
//  StorageTests.swift
//  AltertableTests
//

@testable import Altertable
import XCTest

final class StorageTests: XCTestCase {
    private var storage: UserDefaultsStorage!
    private let testKey = "atbl.test.storage_key"

    override func setUp() {
        super.setUp()
        storage = UserDefaultsStorage()
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        storage = nil
        super.tearDown()
    }

    func testSetAndGet() {
        storage.set("hello", forKey: testKey)
        XCTAssertEqual(storage.string(forKey: testKey), "hello")
    }

    func testMissingKeyReturnsNil() {
        XCTAssertNil(storage.string(forKey: testKey))
    }

    func testRemoveObject() {
        storage.set("value", forKey: testKey)
        storage.removeObject(forKey: testKey)
        XCTAssertNil(storage.string(forKey: testKey))
    }

    func testOverwriteValue() {
        storage.set("first", forKey: testKey)
        storage.set("second", forKey: testKey)
        XCTAssertEqual(storage.string(forKey: testKey), "second")
    }
}
