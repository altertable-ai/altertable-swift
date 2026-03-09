//
//  Logger.swift
//  Altertable
//

import Foundation
import os

final class Logger {
    private let osLog = OSLog(subsystem: "ai.altertable.sdk", category: "general")
    private let lock = NSLock()
    private var isDebug: Bool
    private var printedWarnings: Set<String> = []

    init(isDebug: Bool = false) {
        self.isDebug = isDebug
    }

    func setDebug(_ enabled: Bool) {
        lock.withLock { isDebug = enabled }
    }

    func log(_ message: String) {
        let shouldLog = lock.withLock { isDebug }
        if shouldLog {
            os_log(.info, log: osLog, "%{public}@", message)
        }
    }

    func error(_ message: String, error: Error? = nil) {
        if let error {
            os_log(.error, log: osLog, "%{public}@ - %{public}@", message, error.localizedDescription)
        } else {
            os_log(.error, log: osLog, "%{public}@", message)
        }
    }

    /// Prints a warning at most once per unique message.
    /// In debug builds it also raises an exception so Xcode's "Break on All Exceptions"
    /// breakpoint will pause at the call site, making the source of the warning easy to find.
    func warn(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldWarn = lock.withLock { () -> Bool in
            guard isDebug else { return false }
            guard !printedWarnings.contains(trimmed) else { return false }
            printedWarnings.insert(trimmed)
            return true
        }

        guard shouldWarn else { return }
        os_log(.default, log: osLog, "WARN: %{public}@", trimmed)

        #if DEBUG
        // Throw-and-catch so "Break on All Exceptions" in Xcode pauses here,
        // letting you inspect the call stack that produced this warning.
        do {
            struct AltertableWarning: Error { let message: String }
            throw AltertableWarning(message: trimmed)
        } catch {}
        #endif
    }
}
