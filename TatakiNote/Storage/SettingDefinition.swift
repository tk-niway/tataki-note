import Foundation

/// 保存する値1つの決まり(保存のキー・読み方・書き方・書く前に値を直す処理)。
struct SettingDefinition<Value: Equatable> {
    /// 保存のキー。
    let key: String
    let read: (any SettingsStorage) -> Value
    let write: (Value, any SettingsStorage) -> Void
    let normalize: (Value) -> Value

    init(
        key: String,
        read: @escaping (any SettingsStorage) -> Value,
        write: @escaping (Value, any SettingsStorage) -> Void,
        normalize: @escaping (Value) -> Value = { $0 }
    ) {
        self.key = key
        self.read = read
        self.write = write
        self.normalize = normalize
    }

    /// 値を範囲に収めるなど、保存する前の形に直す。
    func normalized(_ value: Value) -> Value { normalize(value) }
}

/// 保存先から値を型ごとに読む部品。
enum StoredValue {
    /// 真偽値でない数を読む。
    static func number(in storage: any SettingsStorage, forKey key: String) -> NSNumber? {
        guard let value = storage.object(forKey: key) as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID()
        else { return nil }
        return value
    }

    /// 真偽値だけを読む。
    static func boolean(in storage: any SettingsStorage, forKey key: String) -> Bool? {
        guard let value = storage.object(forKey: key) as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID()
        else { return nil }
        return value.boolValue
    }
}

extension SettingDefinition where Value == Bool {
    /// 真偽値の定義。真偽値でない値は初期値になる。
    static func boolean(_ key: String, default defaultValue: Bool) -> SettingDefinition<Bool> {
        SettingDefinition(
            key: key,
            read: { StoredValue.boolean(in: $0, forKey: key) ?? defaultValue },
            write: { value, storage in storage.set(value, forKey: key) }
        )
    }

    /// 保存では逆の値になる真偽値の定義。
    static func invertedBoolean(_ key: String, default defaultValue: Bool) -> SettingDefinition<Bool> {
        SettingDefinition(
            key: key,
            read: { StoredValue.boolean(in: $0, forKey: key).map { !$0 } ?? defaultValue },
            write: { value, storage in storage.set(!value, forKey: key) }
        )
    }
}

extension SettingDefinition where Value: RawRepresentable, Value.RawValue == String {
    /// rawValue の文字列で保存する列挙の定義。知らない値は初期値になる。
    static func stringEnum(_ key: String, default defaultValue: Value) -> SettingDefinition<Value> {
        SettingDefinition(
            key: key,
            read: { $0.string(forKey: key).flatMap(Value.init(rawValue:)) ?? defaultValue },
            write: { value, storage in storage.set(value.rawValue, forKey: key) }
        )
    }
}

extension SettingDefinition where Value == String? {
    /// 空でない文字列の定義。空・文字列でない値は `nil`。`nil`・空文字を書くとキーを消す。
    static func nonEmptyString(_ key: String, emptyBecomesNil: Bool) -> SettingDefinition<String?> {
        SettingDefinition(
            key: key,
            read: { storage in
                guard let value = storage.object(forKey: key) as? String, !value.isEmpty else { return nil }
                return value
            },
            write: { value, storage in
                if let value, !value.isEmpty {
                    storage.set(value, forKey: key)
                } else {
                    storage.removeObject(forKey: key)
                }
            },
            normalize: { value in
                emptyBecomesNil ? value.flatMap { $0.isEmpty ? nil : $0 } : value
            }
        )
    }
}

extension SettingDefinition where Value == Double {
    /// 範囲に丸めて読む数の定義。数でない値は初期値になる。
    static func clampedNumber(
        _ key: String,
        default defaultValue: Double,
        clamp: @escaping (Double) -> Double
    ) -> SettingDefinition<Double> {
        SettingDefinition(
            key: key,
            read: { storage in
                guard let stored = StoredValue.number(in: storage, forKey: key) else { return defaultValue }
                return clamp(stored.doubleValue)
            },
            write: { value, storage in storage.set(value, forKey: key) },
            normalize: clamp
        )
    }

    /// 範囲に入っている数だけを読む定義。範囲外・数でない値は初期値になる。
    static func numberInRange(
        _ key: String,
        range: ClosedRange<Double>,
        default defaultValue: Double,
        clamp: @escaping (Double) -> Double
    ) -> SettingDefinition<Double> {
        SettingDefinition(
            key: key,
            read: { storage in
                guard let value = StoredValue.number(in: storage, forKey: key)?.doubleValue,
                      range.contains(value)
                else { return defaultValue }
                return value
            },
            write: { value, storage in storage.set(value, forKey: key) },
            normalize: clamp
        )
    }
}
