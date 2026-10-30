extension ClosedRange where Bound == Double {
    /// 値をこの範囲に収める。有限でない値は `nonFiniteFallback` を返す。
    func clamping(_ value: Double, nonFiniteFallback: Double) -> Double {
        guard value.isFinite else { return nonFiniteFallback }
        return min(max(value, lowerBound), upperBound)
    }
}
