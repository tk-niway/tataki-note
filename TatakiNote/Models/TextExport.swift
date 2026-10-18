import AppKit
import Foundation

/// 書き出し・共有する文章の判定。
enum ExportableText {
    /// 空、または空白・改行だけの文章か。
    static func isEmpty(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 保存ダイアログで選ばれた場所から、実際に書くファイルの場所を決める。
enum ExportFileName {
    static let initialName = "untitled"
    static let defaultExtension = "txt"

    /// 拡張子が無ければ .txt を付ける。末尾の「.」は取ってから付ける。
    static func resolvedURL(for chosen: URL) -> URL {
        guard chosen.pathExtension.isEmpty else { return chosen }
        let name = chosen.lastPathComponent
        var stem = Substring(name)
        while stem.last == "." {
            stem = stem.dropLast()
        }
        let base = stem.isEmpty ? initialName : String(stem)
        return chosen.deletingLastPathComponent().appendingPathComponent("\(base).\(defaultExtension)")
    }
}

/// 文章を UTF-8 でファイルに書く。
enum TextFileWriter {
    /// BOM を付けず、文章そのままを書く。
    nonisolated static func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}

/// 書き出しの結果。
enum TextExportOutcome: Equatable {
    case exported(URL)
    case cancelled
    case failed(String)
    case empty
    case alreadyChoosing
}

/// 保存ダイアログを出して、選ばれた場所(キャンセルなら nil)を返す。
@MainActor protocol ExportDestinationChoosing: AnyObject {
    func chooseDestination(initialName: String, directory: URL, completion: @escaping (URL?) -> Void)
    /// 開いているダイアログを前に出す。
    func bringToFront()
}

/// 保存ダイアログを1つだけ開き、選ばれた場所に文章を書いて結果を返す。
@MainActor final class TextExporter {
    private let settings: AppSettings
    private let chooser: ExportDestinationChoosing
    private let write: (String, URL) throws -> Void
    private let documentsDirectory: URL
    private let isDirectory: (URL) -> Bool

    /// 保存ダイアログが開いているか。
    private(set) var isChoosing = false

    init(
        settings: AppSettings,
        chooser: ExportDestinationChoosing,
        write: @escaping (String, URL) throws -> Void = TextFileWriter.write,
        documentsDirectory: URL = TextExporter.systemDocumentsDirectory(),
        isDirectory: @escaping (URL) -> Bool = TextExporter.isExistingDirectory
    ) {
        self.settings = settings
        self.chooser = chooser
        self.write = write
        self.documentsDirectory = documentsDirectory
        self.isDirectory = isDirectory
    }

    /// ダイアログが最初に開くフォルダ。前回書き出したフォルダ、無ければ「書類」。
    var initialDirectory: URL {
        guard let path = settings.lastExportDirectoryPath, !path.isEmpty else { return documentsDirectory }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return isDirectory(url) ? url : documentsDirectory
    }

    /// 文章を書き出す保存ダイアログを開く。結果は completion に返す。
    func export(_ text: String, completion: @escaping (TextExportOutcome) -> Void) {
        if ExportableText.isEmpty(text) {
            completion(.empty)
            return
        }
        if isChoosing {
            chooser.bringToFront()
            completion(.alreadyChoosing)
            return
        }
        isChoosing = true
        chooser.chooseDestination(initialName: ExportFileName.initialName, directory: initialDirectory) { [weak self] chosen in
            guard let self else { return }
            completion(self.finish(text, chosen: chosen))
        }
    }

    nonisolated static func systemDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    nonisolated static func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func finish(_ text: String, chosen: URL?) -> TextExportOutcome {
        isChoosing = false
        guard let chosen else { return .cancelled }
        let url = ExportFileName.resolvedURL(for: chosen)
        do {
            try write(text, url)
        } catch {
            return .failed(error.localizedDescription)
        }
        settings.lastExportDirectoryPath = url.deletingLastPathComponent().path
        return .exported(url)
    }
}

/// 書き出しの結果に対して、パネルがすること。
struct ExportFeedback: Equatable {
    var signalsEmpty = false
    var toastMessage: String?
    var toastStyle: PanelToastStyle = .done
    var failureMessage: String?
    var returnsInput = false

    /// 結果とパネルが開いているかから、揺れ・トースト・失敗の知らせ・入力欄への復帰を決める。
    static func feedback(for outcome: TextExportOutcome, isPanelPresented: Bool) -> ExportFeedback {
        switch outcome {
        case .empty:
            guard isPanelPresented else { return ExportFeedback() }
            return ExportFeedback(
                signalsEmpty: true,
                toastMessage: SaveAnimationModel.nothingToExportMessage,
                toastStyle: .notice
            )
        case .exported:
            guard isPanelPresented else { return ExportFeedback() }
            return ExportFeedback(toastMessage: SaveAnimationModel.exportedMessage, toastStyle: .done, returnsInput: true)
        case .cancelled:
            return ExportFeedback(returnsInput: isPanelPresented)
        case .failed(let reason):
            return ExportFeedback(failureMessage: reason, returnsInput: isPanelPresented)
        case .alreadyChoosing:
            return ExportFeedback()
        }
    }
}

/// 保存ダイアログの中で、⌘ のキーに当てる編集の操作。
enum SavePanelEditAction: Equatable {
    case cut
    case copy
    case paste
    case selectAll
    case undo
    case redo
}

/// 保存ダイアログの中の ⌘ のキーを、編集の操作に対応づける。
enum SavePanelEditKey {
    /// 押されたキーに当たる編集の操作。当たらなければ nil。
    static func action(modifiers: NSEvent.ModifierFlags, character: String) -> SavePanelEditAction? {
        let relevant = modifiers.intersection(PanelShortcut.relevantModifiers)
        switch EditorKeyCommand.command(modifiers: relevant, character: character) {
        case .cut: return .cut
        case .copy: return .copy
        case .paste: return .paste
        case .selectAll: return .selectAll
        case .undo: return .undo
        case .redo: return .redo
        case .moveLines, .duplicateLines, .selectLine, .selectWord, nil: return nil
        }
    }
}
