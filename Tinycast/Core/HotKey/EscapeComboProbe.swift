import Carbon.HIToolbox

/// Catches ⎋ pressed together with a modifier while the recorder is capturing. The WindowServer swallows a modified ⎋ before it ever becomes a normal key event — the same swallow ⌘⇥ and ⌘Space get, confirmed empirically: `NSEvent.addLocalMonitorForEvents`/`addGlobalMonitorForEvents` never see a ⌘⎋ keyDown at all — so `ShortcutCaptureSession`'s NSEvent monitors are blind to e.g. ⌘⎋. Carbon's hotkey table sits below that swallow (`RegisterEventHotKey` both accepts and fires it), so probing through it — the same mechanism `HotKeyCenter` uses for real bindings — catches it with no event tap and no permission prompt.
@MainActor
final class EscapeComboProbe {
    private static let signature: OSType = 0x5459_5052  // FourCC "TYPR" — distinct from HotKeyCenter's "TYCT" so the two installed handlers never mistake the other's hotkey ID
    private static var eventHandler: EventHandlerRef?
    private static var onFire: (() -> Void)?

    private var ref: EventHotKeyRef?
    private var registeredModifiers: Int?

    /// Re-registers for exactly the modifiers currently held, or clears when none are — a bare ⎋ already cancels recording through the normal keyDown path and needs no probe.
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
        // Another app (or the system) can already own this exact chord; fail quietly and let the next modifier change retry.
        guard status == noErr, let newRef else { return }
        ref = newRef
        registeredModifiers = carbonModifiers
    }

    /// Tears down the live registration, if any — called on every modifier change and whenever recording stops.
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

/// C entry point for the probe's Carbon handler, mirroring `HotKeyCenter`'s own: Carbon dispatches on the main thread, so the `EventRef` is decoded to a plain `EventHotKeyID` before `assumeIsolated` crosses into actor code.
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
