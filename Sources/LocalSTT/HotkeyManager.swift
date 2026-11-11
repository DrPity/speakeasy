import AppKit
import Carbon.HIToolbox
import CoreGraphics
import LocalSTTCore
import Observation

/// Listens for a system-wide push-to-talk key through an active `CGEventTap`.
///
/// "Active" (`.defaultTap`) lets us *consume* the key: handing back `nil` from
/// the callback keeps the press away from the focused application, meaning the
/// held key never gets typed. Needs Accessibility permission.
@MainActor
@Observable
final class HotkeyManager {

    static let escapeKeyCode: Int64 = 53

    private(set) var shortcut: Shortcut {
        didSet { matcher.shortcut = shortcut }
    }
    /// Indicates if the tap is installed and live right now.
    private(set) var isActive: Bool = false

    /// Called on the main actor when the shortcut is first pressed down.
    var onPress: (() -> Void)?
    /// Called on the main actor the moment the shortcut is let go.
    var onRelease: (() -> Void)?
    /// Called once Escape is pressed, provided `shouldInterceptEscape` said yes.
    var onCancel: (() -> Void)?
    /// Consulted prior to touching Escape. Escape is consumed solely when this
    /// answers true, which keeps an idle app from disturbing Escape behaviour
    /// elsewhere in the OS.
    var shouldInterceptEscape: (() -> Bool)?

    private let defaults: UserDefaults
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Decides press / release / consume for each event (see LocalSTTCore).
    @ObservationIgnored private var matcher: PushToTalkMatcher

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let shortcut = ShortcutStore.load(from: defaults)
        self.shortcut = shortcut
        self.matcher = PushToTalkMatcher(shortcut: shortcut)
    }

    // MARK: - Lifecycle

    /// Set up the tap. Does nothing (and answers false) when Accessibility
    /// hasn't been granted.
    @discardableResult
    func start() -> Bool {
        guard !isActive else { return true }
        guard AXIsProcessTrusted() else { return false }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        isActive = true
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            // Merely disabling leaks the port, and every rebind would leak it once more.
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
        isActive = false
        matcher.reset()
    }

    /// Store and activate a freshly captured shortcut, rebuilding the tap.
    func rebind(_ newShortcut: Shortcut) {
        shortcut = newShortcut
        ShortcutStore.save(newShortcut, to: defaults)
        if isActive {
            stop()
            start()
        }
    }

    // MARK: - Event handling (reached from the C trampoline, on the main thread)

    /// Answers true when the event belongs to us and ought to be consumed.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        // macOS may turn the tap off; switch it back on and let the event
        // through. A key-up sent while it was off is gone, so a hold in
        // progress ends here instead of recording with nothing to stop it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            if matcher.tapInterrupted() == .release { onRelease?() }
            return false
        }

        // Escape throws away the active dictation. It is evaluated first and
        // intercepted solely while a session genuinely runs. It is bypassed
        // altogether when Escape *is* the talk key, since holding it would
        // autorepeat directly into a cancellation.
        if type == .keyDown,
           shortcut.keyCode != Self.escapeKeyCode,
           event.getIntegerValueField(.keyboardEventKeycode) == Self.escapeKeyCode,
           shouldInterceptEscape?() == true {
            onCancel?()
            return true
        }

        let kind: PushToTalkMatcher.EventKind
        switch type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        default: return false
        }

        let decision = matcher.handle(
            kind,
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
        switch decision.action {
        case .press: onPress?()
        case .release: onRelease?()
        case .none: break
        }
        return decision.consume
    }
}

// MARK: - C trampoline

/// The file-private `CGEventTapCallBack`. Rebuilds the `HotkeyManager` reference
/// from `refcon`, forwards the event to it on the main actor, and consumes the
/// event when instructed.
private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

    // Because the tap is registered on the main run loop, this executes on the
    // main thread already; invoke the @MainActor method in place.
    let swallow = MainActor.assumeIsolated {
        manager.handle(type: type, event: event)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
