import AppKit
import Foundation

/// パネルの文章のファイルへの書き出しと共有。結果に応じてトースト・空の知らせを出し、入力をパネルへ戻す。
final class PanelExportSharing {
    /// 書き出す・共有する文章が空のときに呼ぶ。
    var onEmptyInput: () -> Void = {}
    /// トーストを出すときに呼ぶ。
    var onToast: (String, PanelToastStyle) -> Void = { _, _ in }
    /// キー入力をパネルへ戻すときに呼ぶ。
    var onReturnInput: () -> Void = {}

    private let model: PanelModel
    private let panel: NSWindow
    private let exporter: TextExporter
    private let sharer: TextSharing
    private let presentFailure: (String, NSWindow?, @escaping () -> Void) -> Void

    init(
        model: PanelModel,
        panel: NSWindow,
        exporter: TextExporter,
        sharer: TextSharing,
        presentFailure: @escaping (String, NSWindow?, @escaping () -> Void) -> Void
    ) {
        self.model = model
        self.panel = panel
        self.exporter = exporter
        self.sharer = sharer
        self.presentFailure = presentFailure
    }

    /// パネルの文章をファイルへ書き出す。
    func exportCurrentText() {
        exportText(model.text)
    }

    /// 渡した文章をファイルへ書き出す。
    func exportText(_ text: String) {
        exporter.export(text) { [weak self] outcome in
            self?.handleExportOutcome(outcome)
        }
    }

    /// パネルの文章を、タイトルバーの共有ボタンから共有する。空なら共有せずに知らせる。
    func shareCurrentText() {
        guard !ExportableText.isEmpty(model.text) else {
            onEmptyInput()
            onToast(SaveAnimationModel.nothingToShareMessage, .notice)
            model.requestFocus()
            return
        }
        sharer.share(model.text, from: .titleBarButton)
    }

    /// 渡した文章を共有する。
    func share(_ text: String, from anchor: SharingAnchor) {
        sharer.share(text, from: anchor)
    }

    private func handleExportOutcome(_ outcome: TextExportOutcome) {
        let feedback = ExportFeedback.feedback(for: outcome, isPanelPresented: model.isPresented)
        if feedback.signalsEmpty {
            onEmptyInput()
        }
        if let message = feedback.toastMessage {
            onToast(message, feedback.toastStyle)
        }
        if let failure = feedback.failureMessage {
            let shouldReturnInput = feedback.returnsInput
            presentFailure(failure, model.isPresented ? panel : nil) { [weak self] in
                if shouldReturnInput {
                    self?.onReturnInput()
                }
            }
        } else if feedback.returnsInput {
            onReturnInput()
        }
    }
}
