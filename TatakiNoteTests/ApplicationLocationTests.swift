import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct ApplicationLocationTests {
    private static let home = "/home/a"

    private func source(_ path: String, readOnly: Bool = false) -> ApplicationMoveSource? {
        ApplicationLocation.moveSource(bundlePath: path, homeDirectory: Self.home, isOnReadOnlyVolume: readOnly)
    }

    // MARK: - 置き場所の判定

    @Test("AC-18: 「アプリケーション」フォルダとその下、ホームの Applications にあれば移動の対象にならない")
    func insideApplicationsFolderIsNotMoved() {
        #expect(source("/Applications/TatakiNote.app") == nil)
        #expect(source("/Applications/Utilities/TatakiNote.app") == nil)
        #expect(source("/Applications/TatakiNote.app/") == nil)
        #expect(source("/home/a/Applications/TatakiNote.app") == nil)
        #expect(source("/Applications/TatakiNote.app", readOnly: true) == nil)
    }

    @Test("AC-18: 外から起動したら、ダウンロードなど書ける場所は元を消して移す")
    func outsideApplicationsFolderIsRemovable() {
        #expect(source("/ApplicationsOld/TatakiNote.app") == .removable)
        #expect(source("/home/a/Downloads/TatakiNote.app") == .removable)
        #expect(source("/home/b/Applications/TatakiNote.app") == .removable)
    }

    @Test("AC-18: DMG(読み取り専用のボリューム)と隔離された場所は、元を残して写す")
    func readOnlyAndTranslocatedAreCopiedOnly() {
        #expect(source("/Volumes/TatakiNote/TatakiNote.app", readOnly: true) == .readOnly)
        #expect(source("/var/x/AppTranslocation/U/d/TatakiNote.app", readOnly: true) == .readOnly)
        #expect(source("/var/x/AppTranslocation/U/d/TatakiNote.app", readOnly: false) == .readOnly)
    }

    @Test("AC-18: ホームのフォルダが空でも、判定は落ちない")
    func emptyHomeDirectoryDoesNotMatchEverything() {
        let result = ApplicationLocation.moveSource(
            bundlePath: "/home/a/Downloads/TatakiNote.app",
            homeDirectory: "",
            isOnReadOnlyVolume: false
        )
        #expect(result == .removable)
    }

    @Test("AC-18: 移動を聞くのは、外から起動していて「今後は聞かない」を選んでいないときだけ")
    func asksOnlyWhenOutsideAndNotSuppressed() {
        #expect(ApplicationLocation.shouldAsk(source: .removable, isSuppressed: false))
        #expect(ApplicationLocation.shouldAsk(source: .readOnly, isSuppressed: false))
        #expect(!ApplicationLocation.shouldAsk(source: .removable, isSuppressed: true))
        #expect(!ApplicationLocation.shouldAsk(source: .readOnly, isSuppressed: true))
        #expect(!ApplicationLocation.shouldAsk(source: nil, isSuppressed: false))
        #expect(!ApplicationLocation.shouldAsk(source: nil, isSuppressed: true))
    }

    // MARK: - 確認の選び方

    @Test("AC-20: 「移動する」は、チェックに関係なく移動になる")
    func moveButtonAlwaysMoves() {
        #expect(MoveToApplicationsPrompt.choice(isMoveButton: true, isSuppressionChecked: false) == .move)
        #expect(MoveToApplicationsPrompt.choice(isMoveButton: true, isSuppressionChecked: true) == .move)
    }

    @Test("AC-20: 「移動しない」は、チェックの有無をそのまま持つ")
    func stayCarriesSuppressionChoice() {
        #expect(MoveToApplicationsPrompt.choice(isMoveButton: false, isSuppressionChecked: false) == .stay(suppressesFuturePrompts: false))
        #expect(MoveToApplicationsPrompt.choice(isMoveButton: false, isSuppressionChecked: true) == .stay(suppressesFuturePrompts: true))
    }

    @Test("AC-20: 「移動しない」の手順は、「今後は聞かない」のチェックの有無をそのまま保存の指示として持つ")
    func stayStepSavesOnlyWhenChecked() {
        #expect(
            MoveToApplicationsPrompt.step(choice: .stay(suppressesFuturePrompts: false), otherInstanceIsRunning: false)
                == .stay(suppressesFuturePrompts: false)
        )
        #expect(
            MoveToApplicationsPrompt.step(choice: .stay(suppressesFuturePrompts: true), otherInstanceIsRunning: false)
                == .stay(suppressesFuturePrompts: true)
        )
    }

    // MARK: - ほかの TatakiNote が動いているとき

    @Test("AC-28: 自分以外のプロセスだけを、重複なく、並びを変えずに返す")
    func otherInstanceIdentifiers() {
        #expect(MoveToApplicationsPrompt.otherInstanceIdentifiers(running: [], own: 10) == [])
        #expect(MoveToApplicationsPrompt.otherInstanceIdentifiers(running: [10], own: 10) == [])
        #expect(MoveToApplicationsPrompt.otherInstanceIdentifiers(running: [10, 20], own: 10) == [20])
        #expect(MoveToApplicationsPrompt.otherInstanceIdentifiers(running: [20, 20, 30], own: 10) == [20, 30])
        #expect(MoveToApplicationsPrompt.otherInstanceIdentifiers(running: [30, 10, 20, 30], own: 10) == [30, 20])
    }

    @Test("AC-28: 「移動する」は、ほかが動いていれば先に終了を頼み、動いていなければそのまま移す")
    func moveTerminatesOthersOnlyWhenRunning() {
        #expect(MoveToApplicationsPrompt.step(choice: .move, otherInstanceIsRunning: true) == .terminateOthersThenMove)
        #expect(MoveToApplicationsPrompt.step(choice: .move, otherInstanceIsRunning: false) == .move)
    }

    @Test("AC-28: 「移動しない」は、ほかが動いていても終了を頼まない")
    func stayNeverTerminatesOthers() {
        for isRunning in [true, false] {
            for suppresses in [true, false] {
                #expect(
                    MoveToApplicationsPrompt.step(
                        choice: .stay(suppressesFuturePrompts: suppresses),
                        otherInstanceIsRunning: isRunning
                    ) == .stay(suppressesFuturePrompts: suppresses)
                )
            }
        }
    }

    @Test("AC-28: ほかが動いているときだけ、確認の本文に終了の予告が入る")
    func informativeTextMentionsTerminationOnlyWhenRunning() {
        let notice = "動いている TatakiNote は、移動の前に終了します。"
        let base = MoveToApplicationsPrompt.informativeText(otherInstanceIsRunning: false)
        let withOthers = MoveToApplicationsPrompt.informativeText(otherInstanceIsRunning: true)

        #expect(base == "「アプリケーション」フォルダに置くと、アップデートを入れられます。")
        #expect(!base.contains(notice))
        #expect(withOthers.hasPrefix(base))
        #expect(withOthers.contains(notice))
    }
}
