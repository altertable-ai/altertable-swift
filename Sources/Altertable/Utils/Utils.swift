//
//  Utils.swift
//  Altertable
//

import Foundation

extension Date {
    func ISO8601Format() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}
