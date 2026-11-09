import Foundation

/// Applied after caller properties are merged, including screen event properties.
enum Audience {
    static func prepareProperties(_ properties: [String: JSONValue]) -> [String: JSONValue] {
        var result = properties
        result["$url"] = sanitizeURL(properties["$url"])
        result["$referer"] = sanitizeURL(properties["$referer"], originOnly: true)
        result.removeValue(forKey: SDKConstants.propertyViewport)
        return result
    }

    private static func sanitizeURL(_ value: JSONValue?, originOnly: Bool = false) -> JSONValue {
        guard case let .string(raw) = value,
              var url = URLComponents(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty
        else { return .null }
        url.scheme = scheme
        url.host = host.lowercased()
        url.user = nil
        url.password = nil
        url.query = nil
        url.fragment = nil
        if (scheme == "https" && url.port == 443) || (scheme == "http" && url.port == 80) {
            url.port = nil
        }
        url.percentEncodedPath = originOnly ? "" : (url.percentEncodedPath.isEmpty ? "/" : url.percentEncodedPath)
        return url.string.map(JSONValue.string) ?? .null
    }
}
