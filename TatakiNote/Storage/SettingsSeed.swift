// @note p0-549

import Foundation

/// @note p0-550
enum SettingsSeed {
    static let environmentKey = "TATAKINOTE_SETTINGS_SEED"

    enum SeedError: Error, Equatable {
        /// @note p0-551
        case notJSONObject
        /// @note p0-552
        case unsupportedValue(key: String)
    }

    /// @note p0-553
    static func values(environment: [String: String]) throws -> [String: Any] {
        #if DEBUG
        guard let json = environment[environmentKey], !json.isEmpty else { return [:] }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        } catch {
            throw SeedError.notJSONObject
        }
        guard let dictionary = object as? [String: Any] else { throw SeedError.notJSONObject }
        // @note p0-554
        for key in dictionary.keys.sorted() {
            guard let value = dictionary[key], isSupported(value) else {
                throw SeedError.unsupportedValue(key: key)
            }
        }
        return dictionary
        #else
        return [:]
        #endif
    }

    /// @note p0-555
    static func apply(environment: [String: String], to defaults: UserDefaults) throws {
        for (key, value) in try values(environment: environment) {
            defaults.set(value, forKey: key)
        }
    }

    /// @note p0-556
    private static func isSupported(_ value: Any) -> Bool {
        if isScalar(value) {
            return true
        }
        guard let array = value as? [Any] else { return false }
        return array.allSatisfy { isScalar($0) }
    }

    private static func isScalar(_ value: Any) -> Bool {
        value is NSString || value is NSNumber
    }
}
