//
//  Logger.swift
//  Altertable
//

import Foundation
#if canImport(os)
import os
#endif

final class Logger {
    #if canImport(os)
    private let osLog = OSLog(subsystem: "ai.altertable.sdk", category: "general")
    #endif
    private let lock = NSLock()
    private var isDebug: Bool
    private var printedWarnings: Set<String> = []

    init(isDebug: Bool = false) {
        self.isDebug = isDebug
    }

    func setDebug(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isDebug = enabled
    }

    func log(_ message: String) {
        lock.lock()
        let shouldLog = isDebug
        lock.unlock()
        if shouldLog {
            #if canImport(os)
            os_log(.info, log: osLog, "%{public}@", message)
            #else
            print("[INFO] \(message)")
            #endif
        }
    }

    func error(_ message: String, error: Error? = nil) {
        #if canImport(os)
        if let error {
            os_log(.error, log: osLog, "%{public}@ - %{public}@", message, error.localizedDescription)
        } else {
            os_log(.error, log: osLog, "%{public}@", message)
        }
        #else
        if let error {
            print("[ERROR] \(message) - \(error.localizedDescription)")
        } else {
            print("[ERROR] \(message)")
        }
        #endif
    }

    /// Prints a warning at most once per unique message.
    /// In debug builds it also raises an exception so Xcode's "Break on All Exceptions"
    /// breakpoint will pause at the call site, making the source of the warning easy to find.
    func warn(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        let shouldWarn: Bool
        if !isDebug {
            shouldWarn = false
        } else if printedWarnings.contains(trimmed) {
            shouldWarn = false
        } else {
            printedWarnings.insert(trimmed)
            shouldWarn = true
        }
        lock.unlock()

        guard shouldWarn else { return }
        
        #if canImport(os)
        os_log(.default, log: osLog, "WARN: %{public}@", trimmed)
        #else
        print("WARN: \(trimmed)")
        #endif

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
