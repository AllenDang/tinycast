import AppKit
import Carbon.HIToolbox
import Combine
@preconcurrency import IOKit.hidsystem

// `mach_task_self_` is an imported mutable C global (process-constant in practice); snapshot it
// once so actor code never touches the raw global under strict concurrency.
private let machTaskSelf = mach_task_self_

/// C entry point for the event tap. The run-loop source is installed on the main run loop, so this
/// always executes on the main thread: decode the `CGEvent` to plain values, cross into the actor
/// via `assumeIsolated` for a Sendable `Decision`, and apply it to the event out here
/// (`Unmanaged<CGEvent>` is not Sendable, so it can't come back through `assumeIsolated`).
private func hyperKeyEventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HyperKeyTap>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    }

    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let isSynthetic = event.getIntegerValueField(.eventSourceUserData) == HyperKeyTap.syntheticTag
    let flags = event.flags.rawValue

    let decision = MainActor.assumeIsolated {
        tap.decide(
            type: type, keyCode: keyCode, flagsRaw: flags,
            isAutorepeat: isAutorepeat, isSynthetic: isSynthetic)
    }
    switch decision {
    case .pass:
        return Unmanaged.passUnretained(event)
    case .suppress:
        return nil
    case .rewriteFlags(let raw):
        event.flags = CGEventFlags(rawValue: raw)
        return Unmanaged.passUnretained(event)
    }
}

/// The Hyper Key engine: a modifying `CGEventTap` that turns one physical key (Caps Lock, a
/// side-specific modifier, or an F-key) into the ⌃⌥(⇧)⌘ chord, system-wide. Carbon
/// `RegisterEventHotKey` can't intercept lone physical keys, so this is a separate layer from
/// `HotKeyCenter`; rewritten flags flow into Carbon matching, which is how existing Tinycast
/// hotkeys (and other apps' shortcuts) fire from Hyper+key with no changes to the hotkey stack.
@MainActor
final class HyperKeyTap: ObservableObject {
    enum Status: Equatable {
        case off
        case active
        case needsAccessibility
    }

    /// What the tap callback should do with an event, decided on the actor.
    enum Decision: Sendable {
        case pass
        case suppress
        case rewriteFlags(UInt64)
    }

    /// Marker riding in `.eventSourceUserData` on events this tap posts, so it never reacts to
    /// its own synthetics. FourCC "TYCT", same signature as `HotKeyCenter`.
    nonisolated static let syntheticTag: Int64 = 0x5459_4354

    @Published private(set) var status: Status = .off

    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var sessionTokens: [NotificationToken] = []
    private var hidConnect: io_connect_t = IO_OBJECT_NULL

    // Mirrors of the AppSettings values, so `decide` reads plain fields on the hot path.
    private var key: HyperKeyPhysicalKey = .none
    private var includeShift = true
    private var quickPress: HyperKeyQuickPress = .none

    /// Synthetic flags OR'd into every event while the Hyper key is held.
    private var hyperMask: CGEventFlags = []
    /// The key's own flag bits scrubbed from rewritten events: its generic modifier bit when that
    /// sits outside the Hyper set, and Caps Lock's alpha-shift residue.
    private var strippedMask: CGEventFlags = []

    // Hold state machine.
    private var hyperActive = false
    private var hyperDownAt: ContinuousClock.Instant?
    private var otherKeyPressed = false
    private let clock = ContinuousClock()
    private static let quickPressWindow: Duration = .milliseconds(250)

    /// Our notion of the user's Caps Lock state: the tap forces the hardware state off on every
    /// Hyper press (the HID system toggles it upstream of session taps, so suppressing the event
    /// alone leaves the LED on), and this remembers what to restore or toggle afterwards.
    private var virtualCapsLockOn = false

    func start(settings: AppSettings) {
        // @Published emits synchronously on the main actor, hence assumeIsolated.
        settings.$hyperKey
            .sink { [weak self] value in MainActor.assumeIsolated { self?.setKey(value) } }
            .store(in: &cancellables)
        settings.$hyperKeyIncludesShift
            .sink { [weak self] value in MainActor.assumeIsolated { self?.setIncludeShift(value) } }
            .store(in: &cancellables)
        settings.$hyperKeyQuickPress
            .sink { [weak self] value in MainActor.assumeIsolated { self?.quickPress = value } }
            .store(in: &cancellables)

        // Fast user switching: another session owns the keyboard, so drop any half-held state
        // and stop rewriting until this session is active again.
        let center = NSWorkspace.shared.notificationCenter
        sessionTokens = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidResign() }
                }, center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sessionDidBecomeActive() }
                }, center: center),
        ]
    }

    // MARK: - Event decisions

    func decide(
        type: CGEventType, keyCode: Int, flagsRaw: UInt64, isAutorepeat: Bool, isSynthetic: Bool
    ) -> Decision {
        guard !isSynthetic, let hyperCode = key.keyCode else { return .pass }

        if keyCode == hyperCode {
            return decideHyperKeyEvent(type: type, flagsRaw: flagsRaw, isAutorepeat: isAutorepeat, hyperCode: hyperCode)
        }
        guard hyperActive else { return .pass }
        // Any other key or modifier going down while Hyper is held makes this a combo, not a tap.
        if type == .keyDown || type == .flagsChanged { otherKeyPressed = true }
        return .rewriteFlags(hyperized(flagsRaw))
    }

    private func decideHyperKeyEvent(
        type: CGEventType, flagsRaw: UInt64, isAutorepeat: Bool, hyperCode: Int
    ) -> Decision {
        if key.isModifierLike {
            // Caps Lock and the modifiers arrive as flagsChanged for both press and release.
            // Flag presence can't distinguish the two (both Controls held, caps lock state bit),
            // so ask the session key state for the physical key itself.
            guard type == .flagsChanged else { return .pass }
            let isDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(hyperCode))
            if isDown {
                if !hyperActive { beginHold() }
                // Rewrite (not suppress) so apps and the shortcut recorder see the Hyper
                // modifiers go down the instant the key does.
                return .rewriteFlags(hyperized(flagsRaw))
            }
            if hyperActive { endHold() }
            return .rewriteFlags(flagsRaw & ~strippedMask.rawValue)
        }

        // F-keys arrive as keyDown/keyUp; swallow both ends of the press.
        switch type {
        case .keyDown:
            if isAutorepeat { return .suppress }
            if !hyperActive { beginHold() }
            return .suppress
        case .keyUp:
            if hyperActive { endHold() }
            return .suppress
        default:
            return .pass
        }
    }

    private func hyperized(_ flagsRaw: UInt64) -> UInt64 {
        (flagsRaw & ~strippedMask.rawValue) | hyperMask.rawValue
    }

    // MARK: - Hold state machine

    private func beginHold() {
        hyperActive = true
        hyperDownAt = clock.now
        otherKeyPressed = false
        // The HID system already toggled the caps state upstream of this tap; force it back off
        // so holding Hyper never leaves the LED or uppercase typing on.
        if key == .capsLock { setCapsLockState(false) }
    }

    private func endHold() {
        let isQuick =
            !otherKeyPressed && hyperDownAt.map { clock.now - $0 < Self.quickPressWindow } ?? false
        hyperActive = false
        hyperDownAt = nil
        let action: HyperKeyQuickPress = isQuick ? quickPress : .none
        let key = key
        // Posting events or touching IOKit from inside the tap callback risks re-entrancy;
        // finish the press on the next runloop turn.
        Task { @MainActor [weak self] in self?.finishHold(key: key, quickAction: action) }
    }

    private func finishHold(key: HyperKeyPhysicalKey, quickAction: HyperKeyQuickPress) {
        switch quickAction {
        case .none:
            if key == .capsLock { setCapsLockState(virtualCapsLockOn) }
        case .originalKey:
            if key == .capsLock {
                virtualCapsLockOn.toggle()
                setCapsLockState(virtualCapsLockOn)
            } else if let code = key.keyCode {
                postKey(CGKeyCode(code))
            }
        case .escape:
            if key == .capsLock { setCapsLockState(virtualCapsLockOn) }
            postKey(CGKeyCode(kVK_Escape))
        }
    }

    private func cancelHold(restoreCaps: Bool) {
        let wasActive = hyperActive
        hyperActive = false
        hyperDownAt = nil
        otherKeyPressed = false
        if wasActive, restoreCaps, key == .capsLock { setCapsLockState(virtualCapsLockOn) }
    }

    // MARK: - Configuration

    private func setKey(_ newKey: HyperKeyPhysicalKey) {
        guard newKey != key else { return }
        cancelHold(restoreCaps: true)
        key = newKey
        recomputeMasks()
        syncTapPresence()
    }

    private func setIncludeShift(_ include: Bool) {
        guard include != includeShift else { return }
        includeShift = include
        recomputeMasks()
    }

    private func recomputeMasks() {
        hyperMask = [.maskControl, .maskAlternate, .maskCommand]
        if includeShift { hyperMask.insert(.maskShift) }
        strippedMask = []
        if let own = key.ownFlag, !hyperMask.contains(own) { strippedMask = own }
    }

    // MARK: - Tap lifecycle

    private func syncTapPresence() {
        if key == .none {
            tearDownTap()
            stopHealthTimer()
            status = .off
        } else {
            startHealthTimer()
            installTapIfNeeded()
        }
    }

    private func installTapIfNeeded() {
        guard tapPort == nil, key != .none else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: hyperKeyEventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            // A modifying keyboard tap needs the Accessibility grant; the health timer keeps
            // retrying so the dot flips green the moment the user grants it.
            status = .needsAccessibility
            return
        }
        tapPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        status = .active
        virtualCapsLockOn = capsLockState()
    }

    private func tearDownTap() {
        cancelHold(restoreCaps: true)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            CFMachPortInvalidate(tapPort)
            self.tapPort = nil
        }
    }

    /// Called from the callback when the system disables the tap (timeout / user input); any
    /// half-tracked hold is stale by then.
    fileprivate func reenable() {
        cancelHold(restoreCaps: true)
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
    }

    private func startHealthTimer() {
        guard healthTimer == nil else { return }
        healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.healthCheck() }
        }
    }

    private func stopHealthTimer() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    /// One-second watchdog while a key is configured: retries installation until Accessibility is
    /// granted, notices revocation, revives a system-disabled tap, and clears a stuck hold.
    private func healthCheck() {
        guard key != .none else { return }
        if tapPort == nil {
            installTapIfNeeded()
        } else if !Permissions.isAccessibilityTrusted() {
            tearDownTap()
            status = .needsAccessibility
        } else if let tapPort, !CGEvent.tapIsEnabled(tap: tapPort) {
            CGEvent.tapEnable(tap: tapPort, enable: true)
        }
        // Modifier-like presses flow through rewritten (never suppressed), so the session key
        // state is trustworthy for stuck-hold detection. F-key holds are resolved by their own
        // suppressed keyUp or by reenable().
        if hyperActive, key.isModifierLike, let code = key.keyCode,
            !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code))
        {
            cancelHold(restoreCaps: true)
        }
        // Adopt outside caps changes (another keyboard, software toggles) while idle.
        if !hyperActive, key == .capsLock, status == .active {
            virtualCapsLockOn = capsLockState()
        }
    }

    private func sessionDidResign() {
        cancelHold(restoreCaps: true)
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: false) }
    }

    private func sessionDidBecomeActive() {
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: true)
        } else {
            installTapIfNeeded()
        }
    }

    // MARK: - Synthetics & caps state

    /// Synthesize a bare key press for Quick Press, tagged so `decide` ignores it.
    private func postKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        for event in [down, up] {
            event?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
            event?.post(tap: .cghidEventTap)
        }
    }

    /// The classic IOHIDSystem connection for reading/driving the Caps Lock LED + lock state
    /// (no extra permission beyond running unsandboxed).
    private func hidConnection() -> io_connect_t {
        if hidConnect != IO_OBJECT_NULL { return hidConnect }
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != IO_OBJECT_NULL else { return IO_OBJECT_NULL }
        var connect: io_connect_t = IO_OBJECT_NULL
        IOServiceOpen(service, machTaskSelf, UInt32(kIOHIDParamConnectType), &connect)
        IOObjectRelease(service)
        hidConnect = connect
        return connect
    }

    private func capsLockState() -> Bool {
        let connect = hidConnection()
        guard connect != IO_OBJECT_NULL else { return false }
        var on = false
        IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &on)
        return on
    }

    private func setCapsLockState(_ on: Bool) {
        let connect = hidConnection()
        guard connect != IO_OBJECT_NULL else { return }
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), on)
    }
}
