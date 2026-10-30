import Foundation

/// 一覧の行の見出しと続き。
struct SidebarListing: Equatable {
    let firstLine: String?
    let preview: String?
}

/// 行の見出しと続きを、本文が変わったものだけ作り直して覚える。
struct SidebarListingCache {
    private var entries: [UUID: (text: String, listing: SidebarListing)] = [:]
    private let makeListing: (String) -> SidebarListing

    init(makeListing: @escaping (String) -> SidebarListing = SidebarListingCache.defaultListing) {
        self.makeListing = makeListing
    }

    /// `id` の行の見出しと続き。覚えている本文と同じなら覚えを返す。
    mutating func listing(id: UUID, text: String) -> SidebarListing {
        if let entry = entries[id], entry.text == text {
            return entry.listing
        }
        let listing = makeListing(text)
        entries[id] = (text: text, listing: listing)
        return listing
    }

    /// `ids` に無い行の覚えを捨てる。
    mutating func keepOnly(_ ids: Set<UUID>) {
        entries = entries.filter { ids.contains($0.key) }
    }

    /// 本文から見出しと続きを取り出す。
    static func defaultListing(_ text: String) -> SidebarListing {
        SidebarListing(
            firstLine: DraftListing.firstLine(of: text),
            preview: DraftListing.preview(of: text)
        )
    }
}
