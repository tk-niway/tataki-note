import SwiftUI

/// メニューバーに出すアイコン。新しい版があるときは印が付く。
struct MenuBarIconLabel: View {
    let updates: UpdateModel

    var body: some View {
        Image(nsImage: MenuBarIcon.image(isUpdatePending: updates.isUpdatePending))
            .accessibilityLabel("TatakiNote")
    }
}
