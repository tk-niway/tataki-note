import SwiftUI

/// ノートモードで押せない項目に添える、理由の一文(印つき・11pt・secondary)。
struct NoteModeReason: View {
    let restriction: NoteModeRestriction
    let identifier: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "info.circle")
            Text(restriction.reason)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
