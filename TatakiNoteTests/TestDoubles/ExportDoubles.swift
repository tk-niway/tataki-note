import Foundation
@testable import TatakiNote

@MainActor
final class ExportChooserSpy: ExportDestinationChoosing {
    private(set) var requests: [(initialName: String, directory: URL)] = []
    private(set) var bringToFrontCount = 0
    private var completions: [(URL?) -> Void] = []

    var requestCount: Int { requests.count }

    func chooseDestination(initialName: String, directory: URL, completion: @escaping (URL?) -> Void) {
        requests.append((initialName, directory))
        completions.append(completion)
    }

    func bringToFront() {
        bringToFrontCount += 1
    }

    func complete(with url: URL?) {
        guard !completions.isEmpty else { return }
        completions.removeFirst()(url)
    }
}

@MainActor
final class SharerSpy: TextSharing {
    private(set) var calls: [(text: String, anchor: SharingAnchor)] = []

    func share(_ text: String, from anchor: SharingAnchor) {
        calls.append((text, anchor))
    }
}
