import AppKit

/// 挿入先のアプリの最前面のウィンドウの位置を、ウィンドウの一覧から求める。
enum TargetWindowLocator {
    static func frontWindowBounds(in windowList: [[String: Any]], processIdentifier: pid_t) -> CGRect? {
        for window in windowList {
            guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value == processIdentifier
            else { continue }
            guard let layer = window[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0 else { continue }
            guard let bounds = rect(from: window[kCGWindowBounds as String]) else { continue }
            return bounds
        }
        return nil
    }

    private static func rect(from value: Any?) -> CGRect? {
        guard let dictionary = value as? [String: Any],
              ["X", "Y", "Width", "Height"].allSatisfy({ dictionary[$0] is NSNumber })
        else { return nil }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }

    static func frontWindowFrame(processIdentifier: pid_t) -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        guard let bounds = frontWindowBounds(in: windowList, processIdentifier: processIdentifier),
              let primaryScreen = NSScreen.screens.first
        else { return nil }
        return PanelPlacement.cocoaFrame(fromQuartz: bounds, primaryScreenHeight: primaryScreen.frame.height)
    }
}
