//
//  Utils.swift
//  Altertable
//

import Foundation

extension Date {
    private static let iso8601Formatter: ISO8601DateFormatter = .init()

    func ISO8601Format() -> String {
        Date.iso8601Formatter.string(from: self)
    }
}
