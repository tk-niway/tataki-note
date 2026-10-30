import Foundation

/// シェアのメニューを出す場所。
enum SharingAnchor: Equatable {
    case titleBarButton
    case pointer
}

/// 文章でシェアのメニューを出す。
@MainActor
protocol TextSharing: AnyObject {
    func share(_ text: String, from anchor: SharingAnchor)
}
