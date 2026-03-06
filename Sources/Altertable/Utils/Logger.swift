//
//  Logger.swift
//  Altertable
//

import Foundation

class Logger {
    private let tag = "[Altertable]"
    private var isDebug: Bool

    init(isDebug: Bool = false) {
        self.isDebug = isDebug
    }

    func setDebug(_ enabled: Bool) {
        isDebug = enabled
    }

    func log(_ message: String) {
        if isDebug {
            print("\(tag) \(message)")
        }
    }

    func error(_ message: String, error: Error? = nil) {
        if let error {
            print("\(tag) ERROR: \(message) - \(error)")
        } else {
            print("\(tag) ERROR: \(message)")
        }
    }

    func warn(_ message: String) {
        guard isDebug else { return }
        print("\(tag) WARN: \(message)")
    }
}
