import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct TutorialModelOwnAppTests {
    private static let ownPid: pid_t = 4242
    private let own = InsertionTarget(processIdentifier: TutorialModelOwnAppTests.ownPid, bundleIdentifier: "com.example.TatakiNote")
    private let other = InsertionTarget(processIdentifier: pid_t.max - 1, bundleIdentifier: "com.example.Other")

    private func makeTutorialModel(_ temp: TemporaryDefaults) -> TutorialModel {
        TutorialModel(ownProcessIdentifier: Self.ownPid, settings: temp.makeSettings(), hotkey: { nil })
    }

    @Test("AC-7: 練習用の入力欄への挿入の要求は、自分のアプリのときだけ受ける")
    func tutorialAcceptsInsertionRequestOnlyFromOwnApp() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }

        let accepted = makeTutorialModel(temp)
        accepted.insertionRequested(text: "hello", target: own, sendsAfterInsert: true)
        accepted.sendPracticeMessage("hello")
        #expect(accepted.chat.messages.last?.kind == .reply(.commitAndSend))

        let ignored = makeTutorialModel(temp)
        ignored.insertionRequested(text: "hello", target: other, sendsAfterInsert: true)
        ignored.sendPracticeMessage("hello")
        #expect(ignored.chat.messages.last?.kind == .reply(.direct))
    }

    @Test("AC-7: チュートリアルの手順は、パネルの挿入先が自分のアプリのときだけ進む")
    func tutorialAdvancesOnlyForOwnTarget() throws {
        let temp = try TemporaryDefaults()
        defer { temp.remove() }

        let model = makeTutorialModel(temp)
        model.panelDidChange(isPresented: true, target: other, text: "")
        #expect(model.currentStep == .openPanel)
        #expect(model.isShowingOtherTargetWarning)

        model.panelDidChange(isPresented: true, target: own, text: "")
        #expect(model.currentStep == .writeWithNewline)
        #expect(!model.isShowingOtherTargetWarning)
    }
}
