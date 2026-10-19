import Foundation

/// 設定の値を読み書きする保存先。アプリでは `UserDefaults` を使う。
nonisolated protocol SettingsStorage: AnyObject {
    func object(forKey key: String) -> Any?
    func string(forKey key: String) -> String?
    func array(forKey key: String) -> [Any]?
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: SettingsStorage {}
