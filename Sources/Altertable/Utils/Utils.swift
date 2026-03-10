//
//  Utils.swift
//  Altertable
//

import Foundation

extension Date {
    private static let iso8601Formatter: ISO8601DateFormatter = .init()

    func iso8601String() -> String {
        Date.iso8601Formatter.string(from: self)
    }
}
