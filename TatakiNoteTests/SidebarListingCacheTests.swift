import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct SidebarListingCacheTests {
    private final class Counter {
        var value = 0
    }

    private func makeCache(counter: Counter) -> SidebarListingCache {
        SidebarListingCache(makeListing: { text in
            counter.value += 1
            return SidebarListingCache.defaultListing(text)
        })
    }

    @Test("AC-13: 見出しと続きは、今の取り出し方(DraftListing)と同じ")
    func listingMatchesDraftListing() {
        var cache = SidebarListingCache()
        let texts = [
            "",
            "   \n\n  ",
            "一行だけ",
            "\n\n  見出し  \n本文1\n\n本文2\n",
            String(repeating: "あ", count: 300) + "\n" + String(repeating: "い", count: 300)
        ]

        for text in texts {
            let listing = cache.listing(id: UUID(), text: text)
            #expect(listing.firstLine == DraftListing.firstLine(of: text))
            #expect(listing.preview == DraftListing.preview(of: text))
        }
    }

    @Test("AC-13: 空の本文は見出しも続きも nil")
    func emptyTextHasNoListing() {
        var cache = SidebarListingCache()

        let listing = cache.listing(id: UUID(), text: "")

        #expect(listing.firstLine == nil)
        #expect(listing.preview == nil)
    }

    @Test("AC-14: 同じ本文で2回呼んでも、作るのは1回")
    func sameTextIsMadeOnce() {
        let counter = Counter()
        var cache = makeCache(counter: counter)
        let id = UUID()

        let first = cache.listing(id: id, text: "見出し\n続き")
        let second = cache.listing(id: id, text: "見出し\n続き")

        #expect(counter.value == 1)
        #expect(first == second)
    }

    @Test("AC-14: 本文を変えた行だけ作り直し、ほかの行は覚えを使う")
    func onlyChangedTextIsRemade() {
        let counter = Counter()
        var cache = makeCache(counter: counter)
        let changed = UUID()
        let unchanged = UUID()
        _ = cache.listing(id: changed, text: "古い見出し")
        _ = cache.listing(id: unchanged, text: "そのまま")
        #expect(counter.value == 2)

        let remade = cache.listing(id: changed, text: "新しい見出し")
        _ = cache.listing(id: unchanged, text: "そのまま")

        #expect(counter.value == 3)
        #expect(remade.firstLine == "新しい見出し")
    }

    @Test("AC-14: keepOnly で捨てた行は、次に呼ぶと作り直す。残した行は作り直さない")
    func keepOnlyDropsOtherRows() {
        let counter = Counter()
        var cache = makeCache(counter: counter)
        let kept = UUID()
        let dropped = UUID()
        _ = cache.listing(id: kept, text: "残す")
        _ = cache.listing(id: dropped, text: "捨てる")

        cache.keepOnly([kept])
        _ = cache.listing(id: kept, text: "残す")
        #expect(counter.value == 2)
        _ = cache.listing(id: dropped, text: "捨てる")

        #expect(counter.value == 3)
    }
}
