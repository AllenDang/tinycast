/// One-slot reference cache: keys name every dependency; cache writes never invalidate SwiftUI.
final class Memo<Key: Equatable, Value> {
    private var slot: (key: Key, value: Value)?

    func value(for key: Key, build: () -> Value) -> Value {
        if let slot, slot.key == key { return slot.value }
        let built = build()
        slot = (key, built)
        return built
    }
}
