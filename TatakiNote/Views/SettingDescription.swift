import SwiftUI

/// @note p0-693
struct SettingDescription: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
