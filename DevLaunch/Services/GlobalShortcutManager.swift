import Carbon
import CoreGraphics
import Foundation

@MainActor
final class GlobalShortcutManager {
    nonisolated(unsafe) var eventTap: CFMachPort?
    nonisolated(unsafe) var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) var registeredShortcut: GlobalShortcut = .none

    var onTrigger: (() -> Void)?

    func start(shortcut: GlobalShortcut) {
        stop()
        guard shortcut.isSet else { return }
        registeredShortcut = shortcut

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let info = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: globalShortcutEventCallback,
            userInfo: info
        ) else {
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        registeredShortcut = .none
    }

    @discardableResult
    nonisolated func requestAccessibilityPermissionIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    nonisolated func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    /// Called from the C callback (on arbitrary thread).
    nonisolated func handleKeyEvent(_ event: CGEvent) -> Bool {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        let relevantMask: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        let eventModifiers = flags.intersection(relevantMask).rawValue
        let shortcutModifiers = registeredShortcut.modifiers

        if keyCode == registeredShortcut.keyCode && eventModifiers == shortcutModifiers {
            Task { @MainActor [weak self] in
                self?.onTrigger?()
            }
            return true // swallow the event
        }
        return false
    }

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }
}

// MARK: - C Callback

private func globalShortcutEventCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-enable tap if the system disabled it
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo = userInfo {
            let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown, let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userInfo).takeUnretainedValue()
    if manager.handleKeyEvent(event) {
        return nil // swallow
    }
    return Unmanaged.passUnretained(event) // pass through
}
