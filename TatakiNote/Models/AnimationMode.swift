/// TatakiNote の動き(アニメーション)を使うか。
enum AnimationMode: String, CaseIterable, Sendable {
    case system
    case on
    case off

    static let defaultValue: AnimationMode = .on

    /// 動きを使うか。`system` は macOS の「視差効果を減らす」がオンなら使わない。
    func isEnabled(reduceMotion: Bool) -> Bool {
        switch self {
        case .system: !reduceMotion
        case .on: true
        case .off: false
        }
    }
}
