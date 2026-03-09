//
//  Altertable+ScreenViews.swift
//  Altertable
//

import Foundation

public extension Altertable {
    /// Tracks a screen view.
    ///
    /// - Parameters:
    ///   - name: The screen name.
    ///   - properties: Additional properties.
    ///
    /// - Example:
    /// ```swift
    /// altertable.screen(name: "HomeScreen", properties: [
    ///     "section": "main"
    /// ])
    /// ```
    func screen(name: String, properties: [String: JSONValue] = [:]) {
        var screenProperties = [SDKConstants.propertyScreenName: JSONValue(name)]
        screenProperties.merge(properties) { _, new in new }
        track(event: SDKConstants.eventScreenView, properties: screenProperties)
    }
}
