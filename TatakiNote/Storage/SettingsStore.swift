import Foundation

/// 利用者の設定の保存と読み込み。
struct SettingsStore {
    let defaults: any SettingsStorage

    // MARK: - 定義による読み書き

    /// 定義に従って値を読む。無い・読めない値は定義の初期値。
    func value<Value>(_ definition: SettingDefinition<Value>) -> Value { definition.read(defaults) }

    /// 定義に従って、値を直してから保存する。
    func set<Value>(_ value: Value, for definition: SettingDefinition<Value>) {
        definition.write(definition.normalized(value), defaults)
    }

    /// オブジェクトのプロパティを定義に従って直し、直した値が違えば書き戻してから保存する。
    func persist<Root: AnyObject, Value>(
        _ keyPath: ReferenceWritableKeyPath<Root, Value>, of object: Root, as definition: SettingDefinition<Value>
    ) {
        let normalized = definition.normalized(object[keyPath: keyPath])
        if normalized != object[keyPath: keyPath] {
            object[keyPath: keyPath] = normalized
        }
        set(object[keyPath: keyPath], for: definition)
    }
}
