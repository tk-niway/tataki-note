import Foundation

/// パネルの下の帯のキーキャップの色。
struct StatusKeycapPalette: Equatable {
    /// 面のグレーの明るさ(0 が黒、1 が白)。
    let faceWhite: Double
    /// 縁の線の濃さ(primary の不透明度)。
    let edgeOpacity: Double
    /// 下の影の濃さ(primary の不透明度)。
    let shadowOpacity: Double

    /// 外観に合わせた色。
    static func palette(isDark: Bool) -> StatusKeycapPalette {
        if isDark {
            StatusKeycapPalette(faceWhite: 0.19, edgeOpacity: 0.10, shadowOpacity: 0.10)
        } else {
            StatusKeycapPalette(faceWhite: 0.96, edgeOpacity: 0.10, shadowOpacity: 0.10)
        }
    }
}
