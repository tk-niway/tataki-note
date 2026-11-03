import ApplicationServices

/// フォーカスのある要素を1回の問い合わせでまとめて取った結果。
nonisolated struct FocusedElementProbe: @unchecked Sendable {
    let element: AXUIElement?
    let lookup: FocusedElementLookup
    let frame: CGRect?

    var subrole: String? {
        if case .element(_, let subrole, _) = lookup {
            return subrole
        }
        return nil
    }

    /// 2つの要素が同じ要素か。どちらかが nil なら偽。
    nonisolated static func isSameElement(_ lhs: AXUIElement?, _ rhs: AXUIElement?) -> Bool {
        guard let lhs, let rhs else { return false }
        return CFEqual(lhs, rhs)
    }
}

/// 自動表示の見張りが調べた、あるアプリのフォーカスのある要素。
struct ObservedFocus {
    let processIdentifier: pid_t
    let probe: FocusedElementProbe
}

protocol FocusedElementProbing {
    func probeFocusedElement(in target: InsertionTarget, readsFrame: Bool) -> FocusedElementProbe
    /// 要素の位置と大きさ(アクセシビリティの座標)。
    func frame(of element: AXUIElement) -> CGRect?
}
