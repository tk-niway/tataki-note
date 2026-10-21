import Foundation
import Testing

struct DistributionDocsTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func read(_ relativePath: String) throws -> String {
        let url = Self.root.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func section(titled title: String, in markdown: String) throws -> String {
        let lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let start = try #require(lines.firstIndex { $0 == "## \(title)" }, "「\(title)」の節がありません")
        let body = lines[(start + 1)...].prefix { !$0.hasPrefix("## ") }
        return body.joined(separator: "\n")
    }

    @Test("AC-26: README の「入手とインストール」は DMG の手順で、前の版を先に終了する旨があり、zip の手順が無い")
    func readmeInstallSectionDescribesDMG() throws {
        let readme = try read("README.md")
        let install = try section(titled: "入手とインストール", in: readme)

        #expect(install.contains(".dmg"), "DMG の手順がありません")
        #expect(install.contains("「終了」を選びます"), "前の版を先に終了する旨がありません")
        #expect(install.contains("「アプリケーション」フォルダへドラッグ"), "「アプリケーション」フォルダへドラッグする手順がありません")
        #expect(install.contains("移動する"), "外から開いたときの移動の説明がありません")
        #expect(!readme.contains(".zip"), "README に zip の手順が残っています")
    }

    @Test("AC-26: README の「更新」は自動アップデートの手順で、置き換える手順が無い")
    func readmeUpdateSectionDescribesAutomaticUpdates() throws {
        let readme = try read("README.md")
        let update = try section(titled: "更新", in: readme)

        #expect(update.contains("1日に1回"), "1日に1回確かめる旨がありません")
        #expect(update.contains("印"), "印の説明がありません")
        #expect(update.contains("アップデートを確認…"), "「アップデートを確認…」の説明がありません")
        #expect(update.contains("アップデートを自動で確認"), "オフにする場所の説明がありません")
        #expect(!update.contains("置き換えます"), "手で置き換える手順が残っています")
    }

    @Test("AC-26: README のよくある質問に、書いた文章は送られず通信はアップデートの確認だけという説明がある")
    func readmeFAQExplainsNetworkUse() throws {
        let readme = try read("README.md")
        let faq = try section(titled: "よくある質問", in: readme)

        #expect(faq.contains("**通信はしますか?**"), "「通信はしますか?」の質問がありません")
        #expect(faq.contains("書いた文章が外へ送られることはありません"), "書いた文章が送られない旨がありません")
        #expect(faq.contains("通信するのはアップデートの確認だけ"), "通信がアップデートの確認だけである旨がありません")
        #expect(faq.contains("「アップデートを自動で確認」をオフ"), "設定でオフにできる旨がありません")
    }

    @Test("AC-27: 利用者ガイドにアップデートとインストールのページがあり、目次から辿れる")
    func updatesPageExistsAndIsLinkedFromTableOfContents() throws {
        let page = try read("docs/features/updates.md")
        let toc = try read("docs/README.md")

        #expect(toc.contains("](features/updates.md)"), "目次から updates.md にリンクされていません")
        #expect(page.contains("1日に1回"), "自動の確認の説明がありません")
        #expect(page.contains("印"), "印の説明がありません")
        #expect(page.contains("アップデートを確認…"), "「アップデートを確認…」の説明がありません")
        #expect(page.contains("アップデートを自動で確認"), "オフにする場所の説明がありません")
        #expect(page.contains(".dmg"), "DMG からのインストールの説明がありません")
        #expect(page.contains("「アプリケーション」フォルダへ移動"), "移動の説明がありません")
    }

    @Test("AC-27: 設定のページの「情報の項目」にアップデートの2つの項目がある")
    func settingsPageListsUpdateItems() throws {
        let settings = try read("docs/features/settings.md")
        let info = try section(titled: "情報の項目", in: settings)

        #expect(info.contains("「アップデートを自動で確認」"))
        #expect(info.contains("「アップデートを確認…」"))
    }

    @Test("AC-27: パネルのページの「メニューバーのメニュー」の表に、新しい版の項目と「アップデートを確認…」がある")
    func panelPageMenuTableListsUpdateItems() throws {
        let panel = try read("docs/features/panel.md")
        let menu = try section(titled: "メニューバーのメニュー", in: panel)
        let rows = menu.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("|") }

        #expect(rows.contains { $0.contains("「新しい版があります(<版>)」") })
        #expect(rows.contains { $0.contains("「アップデートを確認…」") })
    }

    @Test("AC-27: 下書きと履歴のページに「通信はしません」が無い")
    func draftsPageDoesNotClaimNoNetwork() throws {
        let drafts = try read("docs/features/drafts-and-history.md")

        #expect(!drafts.contains("通信はしません"))
    }
}
