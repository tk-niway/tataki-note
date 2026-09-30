import Foundation
import Observation

/// @note p0-150
@Observable final class AppInfoModel {
    /// @note p0-151
    let version: String?
    /// @note p0-152
    let build: String?
    /// @note p0-153
    let permissionStatus: PermissionGuideModel

    init(infoDictionary: [String: Any], permissionStatus: PermissionGuideModel) {
        self.version = Self.nonEmptyString(infoDictionary["CFBundleShortVersionString"])
        self.build = Self.nonEmptyString(infoDictionary["CFBundleVersion"])
        self.permissionStatus = permissionStatus
    }

    /// @note p0-154
    var versionText: String {
        let unknown = String(localized: "不明")
        guard version != nil || build != nil else { return unknown }
        let versionPart = version ?? unknown
        let buildPart = build ?? unknown
        return String(localized: "\(versionPart) (\(buildPart))")
    }

    /// @note p0-155
    func watchPermission(interval: Duration = .seconds(1)) async {
        while !Task.isCancelled {
            permissionStatus.refresh()
            // @note p0-156
            try? await Task.sleep(for: interval)
        }
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}
