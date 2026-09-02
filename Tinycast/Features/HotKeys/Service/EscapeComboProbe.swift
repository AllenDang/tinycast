import Carbon.HIToolbox

@MainActor
final class EscapeComboProbe {
    // A distinct FourCC prevents cross-handler hotkey IDs.
    private static let signature: OSType = 0x5459_5052
    private static var eventHandler: EventHandlerRef?
    private static var onFire: (() -> Void)?

    private var ref: EventHotKeyRef?
    private var registeredModifiers: Int?

    func update(carbonModifiers: Int, onFire: @escaping () -> Void) {
        guard carbonModifiers != 0 else {
            clear()
            return
        }
        guard registeredModifiers != carbonModifiers else { return }
        clear()
        Self.installEventHandlerIfNeeded()
        Self.onFire = onFire
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape), UInt32(carbonModifiers),
            EventHotKeyID(signature: Self.signature, id: 1),
            GetEventDispatcherTarget(), 0, &newRef)
        guard status == noErr, let newRef else { return }
        ref = newRef
        registeredModifiers = carbonModifiers
    }

    func clear() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        registeredModifiers = nil
        Self.onFire = nil
    }

    private static func installEventHandlerIfNeeded() {
        guard eventHandler == nil, let dispatcher = GetEventDispatcherTarget() else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(dispatcher, escapeComboProbeHandler, 1, &eventType, nil, &eventHandler)
    }

    fileprivate static func handle(_ hotKeyID: EventHotKeyID) -> OSStatus {
        guard hotKeyID.signature == signature, let onFire else { return OSStatus(eventNotHandledErr) }
        onFire()
        return noErr
    }
}

private func escapeComboProbeHandler(
    _: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let error = GetEventParameter(
        event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard error == noErr else { return error }
    return MainActor.assumeIsolated { EscapeComboProbe.handle(hotKeyID) }
}
