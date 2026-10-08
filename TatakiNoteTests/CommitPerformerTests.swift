import Testing
@testable import TatakiNote

@MainActor
final class InserterStub: TextInserting {
    var result: InsertionResult
    var onInsert: (() -> Void)?
    var readiness: InsertionReadiness = .ready
    private(set) var readinessChecks: [InsertionTarget] = []
    private(set) var calls: [(text: String, target: InsertionTarget, shouldSendAfterInsert: Bool)] = []

    init(result: InsertionResult) {
        self.result = result
    }

    func checkReadiness(of target: InsertionTarget) async -> InsertionReadiness {
        readinessChecks.append(target)
        return readiness
    }

    func insert(_ text: String, into target: InsertionTarget, shouldSendAfterInsert: Bool) async -> InsertionResult {
        calls.append((text, target, shouldSendAfterInsert))
        onInsert?()
        return result
    }
}

@MainActor
struct CommitPerformerTests {
    private let textEdit = InsertionTarget(processIdentifier: 101, bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")

    private func makePerformer(
        model: PanelModel,
        permission: PermissionStub,
        inserter: InserterStub
    ) -> CommitPerformer {
        CommitPerformer(model: model, permission: permission, inserter: inserter)
    }

    @Test("AC-5: 文章・権限・挿入先があれば、その文章と挿入先で挿入が1回行われる")
    func insertsOnce() async {
        let model = PanelModel()
        model.present(target: textEdit)
        model.text = "hello\nworld"
        let permission = PermissionStub(isTrusted: true)
        let inserter = InserterStub(result: .inserted)
        let performer = makePerformer(model: model, permission: permission, inserter: inserter)

        let plan = model.prepareCommit(isAccessibilityTrusted: permission.isTrusted)
        await performer.perform(plan)

        #expect(model.isPresented == false)
        #expect(inserter.calls.count == 1)
        #expect(inserter.calls.first?.text == "hello\nworld")
        #expect(inserter.calls.first?.target == textEdit)
        #expect(permission.promptRequestCount == 0)
        #expect(model.text.isEmpty)
    }

    @Test("AC-6: 文章が空なら、挿入・許可の要求のどちらも起きない")
    func emptyTextDoesNothing() async {
        let model = PanelModel()
        model.present(target: textEdit)
        let permission = PermissionStub(isTrusted: true)
        let inserter = InserterStub(result: .inserted)
        let performer = makePerformer(model: model, permission: permission, inserter: inserter)

        await performer.perform(model.prepareCommit(isAccessibilityTrusted: permission.isTrusted))

        #expect(model.isPresented == false)
        #expect(inserter.calls.isEmpty)
        #expect(permission.promptRequestCount == 0)
    }

    @Test("AC-7: 権限が無ければ、挿入せず、許可の要求が1回で、文章は下書きに残る")
    func permissionDeniedRequestsPromptOnce() async {
        let model = PanelModel()
        model.present(target: textEdit)
        model.text = "draft"
        let permission = PermissionStub(isTrusted: false)
        let inserter = InserterStub(result: .inserted)
        let performer = makePerformer(model: model, permission: permission, inserter: inserter)

        await performer.perform(model.prepareCommit(isAccessibilityTrusted: permission.isTrusted))

        #expect(model.isPresented == false)
        #expect(permission.promptRequestCount == 1)
        #expect(inserter.calls.isEmpty)
        #expect(model.text == "draft")
    }

    @Test("AC-8: 挿入先が記録できていなければ、挿入も許可の要求もせず、文章は下書きに残る")
    func noTargetDoesNotInsert() async {
        let model = PanelModel()
        model.present(target: nil)
        model.text = "draft"
        let permission = PermissionStub(isTrusted: true)
        let inserter = InserterStub(result: .inserted)
        let performer = makePerformer(model: model, permission: permission, inserter: inserter)

        await performer.perform(model.prepareCommit(isAccessibilityTrusted: permission.isTrusted))

        #expect(model.isPresented == false)
        #expect(inserter.calls.isEmpty)
        #expect(permission.promptRequestCount == 0)
        #expect(model.text == "draft")
    }

    @Test("AC-9: 挿入先を前面にできなければ、文章を下書きに戻す")
    func targetNotActivatedRestoresDraft() async {
        let model = PanelModel()
        model.present(target: textEdit)
        model.text = "committed"
        let permission = PermissionStub(isTrusted: true)
        let inserter = InserterStub(result: .targetNotActivated)
        let performer = makePerformer(model: model, permission: permission, inserter: inserter)

        await performer.perform(model.prepareCommit(isAccessibilityTrusted: permission.isTrusted))

        #expect(inserter.calls.count == 1)
        #expect(model.text == "committed")
    }

    @Test("AC-9: その間に新しい文章を書き始めていれば、下書きに戻さず上書きしない")
    func targetNotActivatedKeepsNewText() async {
        let model = PanelModel()
        model.present(target: textEdit)
        model.text = "committed"
        let permission = PermissionStub(isTrusted: true)
        let inserter = InserterStub(result: .targetNotActivated)
        inserter.onInsert = { model.text = "new" }
        let performer = makePerformer(model: model, permission: permission, inserter: inserter)

        await performer.perform(model.prepareCommit(isAccessibilityTrusted: permission.isTrusted))

        #expect(model.text == "new")
    }

    @Test("挿入先で入力欄が選ばれていなければ、文章を下書きに戻す")
    func noTextInputRestoresDraft() async {
        let model = PanelModel()
        model.present(target: textEdit)
        model.text = "committed"
        let permission = PermissionStub(isTrusted: true)
        let inserter = InserterStub(result: .noTextInput)
        let performer = makePerformer(model: model, permission: permission, inserter: inserter)

        await performer.perform(model.prepareCommit(isAccessibilityTrusted: permission.isTrusted))

        #expect(inserter.calls.count == 1)
        #expect(model.isPresented == false)
        #expect(model.text == "committed")
    }

    // MARK: - 権限が無いときの案内

    @Test("AC-3: 権限が無く、案内を開く処理があれば、それが1回呼ばれ、許可の要求・挿入はせず、文章は下書きに残る")
    func permissionDeniedOpensGuide() async {
        let model = PanelModel()
        model.present(target: textEdit)
        model.text = "draft"
        let permission = PermissionStub(isTrusted: false)
        let inserter = InserterStub(result: .inserted)
        let performer = makePerformer(model: model, permission: permission, inserter: inserter)
        var guideOpenCount = 0
        performer.onPermissionDenied = { guideOpenCount += 1 }

        let plan = model.prepareCommit(isAccessibilityTrusted: permission.isTrusted)
        #expect(plan == .permissionDenied)
        await performer.perform(plan)

        #expect(guideOpenCount == 1)
        #expect(permission.promptRequestCount == 0)
        #expect(inserter.calls.isEmpty)
        #expect(model.isPresented == false)
        #expect(model.text == "draft")
    }

    @Test("AC-11: 権限が無く、案内を開く処理が渡されていなければ、許可の要求が1回で、挿入はせず、文章は下書きに残る")
    func permissionDeniedWithoutGuideRequestsPrompt() async {
        let model = PanelModel()
        model.present(target: textEdit)
        model.text = "draft"
        let permission = PermissionStub(isTrusted: false)
        let inserter = InserterStub(result: .inserted)
        let performer = makePerformer(model: model, permission: permission, inserter: inserter)
        #expect(performer.onPermissionDenied == nil)

        let plan = model.prepareCommit(isAccessibilityTrusted: permission.isTrusted)
        #expect(plan == .permissionDenied)
        await performer.perform(plan)

        #expect(permission.promptRequestCount == 1)
        #expect(inserter.calls.isEmpty)
        #expect(model.text == "draft")
    }

    @Test("AC-14: 案内を開く処理があっても、空・挿入先なし・挿入成功・前面にできないときは案内を開かず許可も求めない")
    func otherPlansDoNotOpenGuide() async {
        struct Scenario {
            let name: String
            let target: InsertionTarget?
            let text: String
            let insertionResult: InsertionResult
            let isExpectedPlan: (CommitPlan) -> Bool
            let expectedInsertCount: Int
            let expectedTextAfter: String
        }
        let scenarios = [
            Scenario(
                name: "文章が空",
                target: textEdit,
                text: "",
                insertionResult: .inserted,
                isExpectedPlan: { $0 == .dismissOnly },
                expectedInsertCount: 0,
                expectedTextAfter: ""
            ),
            Scenario(
                name: "挿入先が分からない",
                target: nil,
                text: "draft",
                insertionResult: .inserted,
                isExpectedPlan: { $0 == .noTarget },
                expectedInsertCount: 0,
                expectedTextAfter: "draft"
            ),
            Scenario(
                name: "挿入できた",
                target: textEdit,
                text: "hello",
                insertionResult: .inserted,
                isExpectedPlan: { if case .insert = $0 { true } else { false } },
                expectedInsertCount: 1,
                expectedTextAfter: ""
            ),
            Scenario(
                name: "挿入先を前面にできなかった",
                target: textEdit,
                text: "committed",
                insertionResult: .targetNotActivated,
                isExpectedPlan: { if case .insert = $0 { true } else { false } },
                expectedInsertCount: 1,
                expectedTextAfter: "committed"
            ),
        ]

        for scenario in scenarios {
            let model = PanelModel()
            model.present(target: scenario.target)
            model.text = scenario.text
            let permission = PermissionStub(isTrusted: true)
            let inserter = InserterStub(result: scenario.insertionResult)
            let performer = makePerformer(model: model, permission: permission, inserter: inserter)
            var guideOpenCount = 0
            performer.onPermissionDenied = { guideOpenCount += 1 }

            let plan = model.prepareCommit(isAccessibilityTrusted: permission.isTrusted)
            #expect(scenario.isExpectedPlan(plan), "\(scenario.name)")
            await performer.perform(plan)

            #expect(guideOpenCount == 0, "\(scenario.name)")
            #expect(permission.promptRequestCount == 0, "\(scenario.name)")
            #expect(inserter.calls.count == scenario.expectedInsertCount, "\(scenario.name)")
            #expect(model.text == scenario.expectedTextAfter, "\(scenario.name)")
        }
    }

    // MARK: - 確定+送信

    @Test("AC-4: 確定+送信では挿入に「送信する」が渡り、確定(引数を省いた呼び出し)では「送信しない」が渡る")
    func passesShouldSendAfterInsertToInserter() async {
        let scenarios: [(String, Bool?, Bool)] = [
            ("確定+送信", true, true),
            ("確定(明示)", false, false),
            ("確定(引数を省く)", nil, false),
        ]
        for (name, shouldSend, expected) in scenarios {
            let model = PanelModel()
            model.present(target: textEdit)
            model.text = "hello"
            let permission = PermissionStub(isTrusted: true)
            let inserter = InserterStub(result: .inserted)
            let performer = makePerformer(model: model, permission: permission, inserter: inserter)

            let plan = model.prepareCommit(isAccessibilityTrusted: permission.isTrusted)
            if let shouldSend {
                await performer.perform(plan, shouldSendAfterInsert: shouldSend)
            } else {
                await performer.perform(plan)
            }

            #expect(inserter.calls.count == 1, "\(name)")
            #expect(inserter.calls.first?.text == "hello", "\(name)")
            #expect(inserter.calls.first?.target == textEdit, "\(name)")
            #expect(inserter.calls.first?.shouldSendAfterInsert == expected, "\(name)")
        }
    }

    @Test("AC-12: 文章が空のまま確定+送信しても、挿入も送信も・許可の要求も起きない")
    func emptyTextWithSendDoesNothing() async {
        let model = PanelModel()
        model.present(target: textEdit)
        let permission = PermissionStub(isTrusted: true)
        let inserter = InserterStub(result: .inserted)
        let performer = makePerformer(model: model, permission: permission, inserter: inserter)
        var guideOpenCount = 0
        performer.onPermissionDenied = { guideOpenCount += 1 }

        let plan = model.prepareCommit(isAccessibilityTrusted: permission.isTrusted)
        #expect(plan == .dismissOnly)
        await performer.perform(plan, shouldSendAfterInsert: true)

        #expect(model.isPresented == false)
        #expect(inserter.calls.isEmpty)
        #expect(permission.promptRequestCount == 0)
        #expect(guideOpenCount == 0)
    }

    @Test("AC-5: 確定+送信でも、許可が無い・挿入先が分からないときは挿入(と送信)をせず、文章は下書きに残る")
    func sendDoesNotInsertWithoutPermissionOrTarget() async {
        do {
            let model = PanelModel()
            model.present(target: textEdit)
            model.text = "draft"
            let permission = PermissionStub(isTrusted: false)
            let inserter = InserterStub(result: .inserted)
            let performer = makePerformer(model: model, permission: permission, inserter: inserter)
            var guideOpenCount = 0
            performer.onPermissionDenied = { guideOpenCount += 1 }

            await performer.perform(model.prepareCommit(isAccessibilityTrusted: permission.isTrusted), shouldSendAfterInsert: true)

            #expect(guideOpenCount == 1)
            #expect(inserter.calls.isEmpty)
            #expect(model.text == "draft")
        }
        do {
            let model = PanelModel()
            model.present(target: nil)
            model.text = "draft"
            let permission = PermissionStub(isTrusted: true)
            let inserter = InserterStub(result: .inserted)
            let performer = makePerformer(model: model, permission: permission, inserter: inserter)

            await performer.perform(model.prepareCommit(isAccessibilityTrusted: permission.isTrusted), shouldSendAfterInsert: true)

            #expect(inserter.calls.isEmpty)
            #expect(model.text == "draft")
        }
    }

    @Test("AC-5: 確定+送信で、挿入先を前面にできない・入力欄でないと分かったときは、文章を下書きに戻す")
    func sendRestoresDraftWhenInsertionFails() async {
        let results: [InsertionResult] = [.targetNotActivated, .noTextInput]
        for insertionResult in results {
            let model = PanelModel()
            model.present(target: textEdit)
            model.text = "committed"
            let permission = PermissionStub(isTrusted: true)
            let inserter = InserterStub(result: insertionResult)
            let performer = makePerformer(model: model, permission: permission, inserter: inserter)

            await performer.perform(model.prepareCommit(isAccessibilityTrusted: permission.isTrusted), shouldSendAfterInsert: true)

            #expect(inserter.calls.count == 1, "\(insertionResult)")
            #expect(inserter.calls.first?.shouldSendAfterInsert == true, "\(insertionResult)")
            #expect(model.text == "committed", "\(insertionResult)")
        }
    }

    // MARK: - 確定の結果

    @Test("AC-7: 確定・確定+送信で挿入できたときだけ「挿入できた」を返し、前面にできない・入力欄でない・空・許可なし・挿入先なしは「挿入しなかった」")
    func performReturnsOutcome() async {
        struct Scenario {
            let name: String
            let target: InsertionTarget?
            let text: String
            let isTrusted: Bool
            let insertionResult: InsertionResult
            let shouldSendAfterInsert: Bool
            let expected: CommitOutcome
        }
        let scenarios = [
            Scenario(name: "挿入できた", target: textEdit, text: "hello", isTrusted: true, insertionResult: .inserted, shouldSendAfterInsert: false, expected: .inserted),
            Scenario(name: "確定+送信で挿入できた", target: textEdit, text: "hello", isTrusted: true, insertionResult: .inserted, shouldSendAfterInsert: true, expected: .inserted),
            Scenario(name: "前面にできなかった", target: textEdit, text: "hello", isTrusted: true, insertionResult: .targetNotActivated, shouldSendAfterInsert: false, expected: .notInserted),
            Scenario(name: "入力欄でなかった", target: textEdit, text: "hello", isTrusted: true, insertionResult: .noTextInput, shouldSendAfterInsert: true, expected: .notInserted),
            Scenario(name: "空", target: textEdit, text: "", isTrusted: true, insertionResult: .inserted, shouldSendAfterInsert: false, expected: .notInserted),
            Scenario(name: "許可なし", target: textEdit, text: "hello", isTrusted: false, insertionResult: .inserted, shouldSendAfterInsert: false, expected: .notInserted),
            Scenario(name: "挿入先なし", target: nil, text: "hello", isTrusted: true, insertionResult: .inserted, shouldSendAfterInsert: false, expected: .notInserted),
        ]

        for scenario in scenarios {
            let model = PanelModel()
            model.present(target: scenario.target)
            model.text = scenario.text
            let permission = PermissionStub(isTrusted: scenario.isTrusted)
            let inserter = InserterStub(result: scenario.insertionResult)
            let performer = makePerformer(model: model, permission: permission, inserter: inserter)

            let outcome = await performer.perform(
                model.prepareCommit(isAccessibilityTrusted: permission.isTrusted),
                shouldSendAfterInsert: scenario.shouldSendAfterInsert
            )

            #expect(outcome == scenario.expected, "\(scenario.name)")
        }
    }
}
