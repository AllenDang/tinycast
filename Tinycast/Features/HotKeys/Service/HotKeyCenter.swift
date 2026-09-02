import Carbon.HIToolbox

private func hotKeyCarbonEventHandler(
    _: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let error = GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard error == noErr else { return error }
    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    return MainActor.assumeIsolated { center.handle(hotKeyID) }
}

@MainActor
final class HotKeyCenter {
    private struct Entry {
        let shortcut: KeyShortcut
        let onKeyDown: () -> Void
        let carbonID: UInt32
        var ref: EventHotKeyRef?
    }

    private var entries: [String: Entry] = [:]
    private var idToKey: [UInt32: String] = [:]
    private var nextCarbonID: UInt32 = 0
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x5459_4354  // FourCC "TYCT"

    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            for key in entries.keys {
                if isPaused { deactivate(key) } else { activate(key) }
            }
        }
    }

    func register(id: String, shortcut: KeyShortcut, onKeyDown: @escaping () -> Void) {
        unregister(id: id)
        nextCarbonID += 1
        entries[id] = Entry(
            shortcut: shortcut, onKeyDown: onKeyDown, carbonID: nextCarbonID, ref: nil)
        idToKey[nextCarbonID] = id
        if !isPaused { activate(id) }
    }

    func unregister(id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        if let ref = entry.ref { UnregisterEventHotKey(ref) }
        idToKey.removeValue(forKey: entry.carbonID)
    }

    private func activate(_ id: String) {
        guard var entry = entries[id], entry.ref == nil else { return }
        installEventHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let error = RegisterEventHotKey(
            UInt32(entry.shortcut.carbonKeyCode),
            UInt32(entry.shortcut.carbonModifiers),
            EventHotKeyID(signature: signature, id: entry.carbonID),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard error == noErr, let ref else {
            NSLog("Tinycast: could not register hotkey for %@ (OSStatus %d)", id, error)
            return
        }
        entry.ref = ref
        entries[id] = entry
    }

    private func deactivate(_ id: String) {
        guard var entry = entries[id], let ref = entry.ref else { return }
        UnregisterEventHotKey(ref)
        entry.ref = nil
        entries[id] = entry
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil, let dispatcher = GetEventDispatcherTarget() else { return }
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        ]
        InstallEventHandler(
            dispatcher,
            hotKeyCarbonEventHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    fileprivate func handle(_ hotKeyID: EventHotKeyID) -> OSStatus {
        guard
            hotKeyID.signature == signature,
            let key = idToKey[hotKeyID.id],
            let entry = entries[key]
        else { return OSStatus(eventNotHandledErr) }
        entry.onKeyDown()
        return noErr
    }
}
