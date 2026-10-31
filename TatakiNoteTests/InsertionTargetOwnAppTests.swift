import AppKit
import Foundation
import Testing
@testable import TatakiNote

@MainActor
struct InsertionTargetOwnAppTests {
    private static let ownPid: pid_t = 4242
    private let own = InsertionTarget(processIdentifier: InsertionTargetOwnAppTests.ownPid, bundleIdentifier: "com.example.TatakiNote")
    private let other = InsertionTarget(processIdentifier: pid_t.max - 1, bundleIdentifier: "com.example.Other")

    @Test("AC-7: isOwnApp は同じプロセスのときだけ真になる")
    func isOwnAppComparesProcessIdentifiers() {
        #expect(own.isOwnApp(Self.ownPid))
        #expect(!other.isOwnApp(Self.ownPid))
        #expect(other.isOwnApp(other.processIdentifier))
    }

    @Test("AC-7: 挿入先は、前面が自分なら最後に前面になった他のアプリ、どちらも自分なら nil")
    func chooseTargetSkipsOwnApp() {
        let previous = InsertionTarget(processIdentifier: 777)

        #expect(FrontmostAppTracker.chooseTarget(frontmost: other, lastActivated: previous, ownProcessIdentifier: Self.ownPid) == other)
        #expect(FrontmostAppTracker.chooseTarget(frontmost: own, lastActivated: previous, ownProcessIdentifier: Self.ownPid) == previous)
        #expect(FrontmostAppTracker.chooseTarget(frontmost: own, lastActivated: own, ownProcessIdentifier: Self.ownPid) == nil)
        #expect(FrontmostAppTracker.chooseTarget(frontmost: nil, lastActivated: nil, ownProcessIdentifier: Self.ownPid) == nil)
    }

    @Test("AC-7: アクセシビリティの問い合わせは、自分以外の挿入先のときだけする")
    func queriesAccessibilityOnlyForOtherTargets() {
        #expect(PanelOpenFrameResolver.shouldQueryAccessibility(of: other, ownProcessIdentifier: Self.ownPid))
        #expect(!PanelOpenFrameResolver.shouldQueryAccessibility(of: own, ownProcessIdentifier: Self.ownPid))
        #expect(!PanelOpenFrameResolver.shouldQueryAccessibility(of: nil, ownProcessIdentifier: Self.ownPid))
    }
}
