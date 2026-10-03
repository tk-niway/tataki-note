import Foundation
import Observation

/// 設定画面の「アプリ情報」の状態(バージョン・アクセシビリティの許可の状態)。
@Observable final class AppInfoModel {
    let version: String?
    let build: String?
    let permissionStatus: PermissionGuideModel
    private let onOpenTutorial: () -> Void

    init(
        infoDictionary: [String: Any],
        permissionStatus: PermissionGuideModel,
        onOpenTutorial: @escaping () -> Void = {}
    ) {
        self.version = Self.nonEmptyString(infoDictionary["CFBundleShortVersionString"])
        self.build = Self.nonEmptyString(infoDictionary["CFBundleVersion"])
        self.permissionStatus = permissionStatus
        self.onOpenTutorial = onOpenTutorial
    }

    /// チュートリアルの窓を開く。
    func openTutorial() {
        onOpenTutorial()
    }

    /// 「チュートリアル」の行に出す説明文。
    static var tutorialDescription: String {
        String(localized: "練習用のチャットで、パネルで書いて送るまでを試します。")
    }

    var versionText: String {
        let unknown = String(localized: "不明")
        guard version != nil || build != nil else { return unknown }
        let versionPart = version ?? unknown
        let buildPart = build ?? unknown
        return String(localized: "\(versionPart) (\(buildPart))")
    }

    func watchPermission(interval: Duration = .seconds(1)) async {
        while !Task.isCancelled {
            permissionStatus.refresh()
            try? await Task.sleep(for: interval)
        }
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}
