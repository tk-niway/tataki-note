import CoreGraphics
import Observation

/// 挿入先の入力欄を囲む枠線の場所。
@Observable
final class InsertionTargetOutlineModel {
    /// 枠線で囲む枠(左上が原点)。出さないときは nil。
    private(set) var rect: CGRect?

    /// 枠を入れ替える。変わらないときは何もしない。
    func update(_ rect: CGRect?) {
        guard self.rect != rect else { return }
        self.rect = rect
    }
}
