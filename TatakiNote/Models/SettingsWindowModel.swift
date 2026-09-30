import Observation

/// @note p0-463
@Observable final class SettingsWindowModel {
    var selectedSection: SettingsSection = .general

    /// @note p0-464
    func prepareForOpen() {
        selectedSection = .general
    }
}
