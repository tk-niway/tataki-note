import Observation

/// `tracking` で読んだ値が変わるたびに、MainActor で `onChange` を呼んで見張りを掛け直す。`onChange` が false を返すとやめる。
func observeRepeatedly(
    tracking: @MainActor @escaping () -> Void,
    onChange: @MainActor @escaping () -> Bool
) {
    withObservationTracking {
        tracking()
    } onChange: {
        Task { @MainActor in
            if onChange() {
                observeRepeatedly(tracking: tracking, onChange: onChange)
            }
        }
    }
}
