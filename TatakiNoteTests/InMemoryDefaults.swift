import Foundation
import Testing
@testable import TatakiNote

/// ディスクに書かない設定の保存先。同じ名前で作ると同じ中身を共有し、`removePersistentDomain` で消える。
final class InMemoryDefaults: SettingsStorage, @unchecked Sendable {
    private final class Domain: @unchecked Sendable {
        var values: [String: Any] = [:]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var domains: [String: Domain] = [:]

    let suiteName: String
    private let domain: Domain

    init?(suiteName: String) {
        guard !suiteName.isEmpty else { return nil }
        self.suiteName = suiteName
        domain = Self.lock.withLock {
            if let existing = Self.domains[suiteName] { return existing }
            let created = Domain()
            Self.domains[suiteName] = created
            return created
        }
    }

    // MARK: - SettingsStorage

    func object(forKey key: String) -> Any? {
        Self.lock.withLock { domain.values[key] }
    }

    func string(forKey key: String) -> String? {
        switch object(forKey: key) {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    func array(forKey key: String) -> [Any]? {
        object(forKey: key) as? [Any]
    }

    func data(forKey key: String) -> Data? {
        object(forKey: key) as? Data
    }

    func set(_ value: Any?, forKey key: String) {
        guard let value else {
            removeObject(forKey: key)
            return
        }
        guard let stored = Self.propertyListValue(value) else {
            Issue.record("UserDefaults に保存できない値: \(type(of: value)) (\(key))")
            return
        }
        Self.lock.withLock { domain.values[key] = stored }
    }

    func removeObject(forKey key: String) {
        _ = Self.lock.withLock { domain.values.removeValue(forKey: key) }
    }

    // MARK: - UserDefaults と同じ読み方

    func stringArray(forKey key: String) -> [String]? {
        guard let array = array(forKey: key) else { return nil }
        let strings = array.compactMap { $0 as? String }
        return strings.count == array.count ? strings : nil
    }

    func bool(forKey key: String) -> Bool {
        switch object(forKey: key) {
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return ["yes", "true"].contains(string.lowercased()) || (Int(string) ?? 0) != 0
        default:
            return false
        }
    }

    func integer(forKey key: String) -> Int {
        switch object(forKey: key) {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string) ?? Int(Double(string) ?? 0)
        default:
            return 0
        }
    }

    func double(forKey key: String) -> Double {
        switch object(forKey: key) {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string) ?? 0
        default:
            return 0
        }
    }

    func dictionaryRepresentation() -> [String: Any] {
        Self.lock.withLock { domain.values }
    }

    func persistentDomain(forName name: String) -> [String: Any]? {
        Self.lock.withLock { Self.domains[name]?.values }
    }

    func removePersistentDomain(forName name: String) {
        Self.lock.withLock {
            Self.domains[name]?.values = [:]
            Self.domains[name] = nil
        }
    }

    // MARK: - 保存できる値

    private static func propertyListValue(_ value: Any) -> Any? {
        switch value {
        case let string as String:
            return string
        case let data as Data:
            return data
        case let date as Date:
            return date
        case let number as NSNumber:
            return number
        case let array as [Any]:
            let converted = array.compactMap(propertyListValue)
            return converted.count == array.count ? converted : nil
        case let dictionary as [String: Any]:
            var converted: [String: Any] = [:]
            for (key, element) in dictionary {
                guard let value = propertyListValue(element) else { return nil }
                converted[key] = value
            }
            return converted
        default:
            return nil
        }
    }
}
