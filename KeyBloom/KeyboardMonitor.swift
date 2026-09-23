import CoreGraphics
import Foundation
import AppKit
import IOKit.hid

final class KeyboardMonitor {
    var onKeyDown: ((Int, Date) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hidManager: IOHIDManager?
    private var pressedModifierKeyCodes: Set<Int> = []
    private var recentFunctionKeyEvents: [Int: [RecentFunctionKeyEvent]] = [:]

    private enum FunctionKeySource {
        case quartz
        case hidKeyboard
        case hidConsumer
        case hidVendor
    }

    private struct RecentFunctionKeyEvent {
        let source: FunctionKeySource
        let date: Date
    }

    private static let modifierKeyCodes: Set<Int> = [54, 55, 56, 58, 59, 60, 61, 62, 63]
    private static let functionRowKeyCodes: Set<Int> = [96, 97, 98, 99, 100, 101, 103, 109, 111, 118, 120, 122]
    // NSEvent.systemDefined / NX_SYSDEFINED is raw event type 14 in the Quartz stream.
    private static let systemDefinedEventType: UInt32 = 14

    var isRunning: Bool { eventTap != nil }

    func start() -> Bool {
        guard !isRunning else { return true }

        pressedModifierKeyCodes.removeAll()
        recentFunctionKeyEvents.removeAll()

        let eventTapStarted = startEventTap()
        guard eventTapStarted else { return false }
        _ = startHIDMonitor()
        return true
    }

    func stop() {
        if let manager = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        pressedModifierKeyCodes.removeAll()
        recentFunctionKeyEvents.removeAll()
    }

    private func startEventTap() -> Bool {
        let eventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << Self.systemDefinedEventType)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: KeyboardMonitor.eventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func startHIDMonitor() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Match all HID devices, then accept only the consumer and Apple keyboard
        // usage pages below. Mission Control and Launchpad can be delivered as
        // HID controls rather than ordinary F-key events.
        IOHIDManagerSetDeviceMatching(manager, nil)
        IOHIDManagerRegisterInputValueCallback(
            manager,
            KeyboardMonitor.hidValueCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        hidManager = manager

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            hidManager = nil
            return false
        }
        return true
    }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak monitor] in
                guard let tap = monitor?.eventTap else { return }
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            // Modifier keys are counted from flagsChanged only, to avoid counting
            // twice on systems that also emit a regular keyDown for them.
            guard !KeyboardMonitor.modifierKeyCodes.contains(keyCode), keyCode != 57 else {
                return Unmanaged.passUnretained(event)
            }
            let timestamp = Date()
            DispatchQueue.main.async { [weak monitor] in
                monitor?.onKeyDown?(keyCode, timestamp)
            }
        } else if type == .flagsChanged {
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            guard KeyboardMonitor.modifierKeyCodes.contains(keyCode) || keyCode == 57 else {
                return Unmanaged.passUnretained(event)
            }

            let timestamp = Date()
            if keyCode == 57 {
                // Caps Lock reports each press as a flagsChanged event; its flag
                // represents the latched state, so both turning it on and off count.
                DispatchQueue.main.async { [weak monitor] in
                    monitor?.onKeyDown?(keyCode, timestamp)
                }
            } else {
                DispatchQueue.main.async { [weak monitor] in
                    monitor?.handleModifierChange(keyCode: keyCode, at: timestamp)
                }
            }
        } else if type.rawValue == KeyboardMonitor.systemDefinedEventType,
                  let keyCode = KeyboardMonitor.functionKeyCode(forSystemDefinedEvent: event) {
            let timestamp = Date()
            DispatchQueue.main.async { [weak monitor] in
                monitor?.recordFunctionKeyDown(keyCode: keyCode, at: timestamp, source: .quartz)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private static let hidValueCallback: IOHIDValueCallback = { context, result, _, value in
        guard result == kIOReturnSuccess,
              let context,
              IOHIDValueGetIntegerValue(value) != 0 else { return }

        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        guard let keyCode = KeyboardMonitor.functionRowKeyCode(usagePage: usagePage, usage: usage) else { return }

        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue()
        let timestamp = Date()
        let source: FunctionKeySource
        switch usagePage {
        case 0x0007: source = .hidKeyboard
        case 0x000C: source = .hidConsumer
        default: source = .hidVendor
        }
        DispatchQueue.main.async { [weak monitor] in
            monitor?.recordFunctionKeyDown(keyCode: keyCode, at: timestamp, source: source)
        }
    }

    private func handleModifierChange(keyCode: Int, at date: Date) {
        // A flagsChanged event is itself a physical modifier transition. Toggle
        // this key's state directly so left/right modifiers remain independent;
        // querying Quartz's aggregate key-state table can miss right-side keys.
        if pressedModifierKeyCodes.insert(keyCode).inserted {
            onKeyDown?(keyCode, date)
        } else {
            pressedModifierKeyCodes.remove(keyCode)
        }
    }

    private func recordFunctionKeyDown(keyCode: Int, at date: Date, source: FunctionKeySource) {
        // Quartz and HID can both report the same top-row press. Pair cross-source
        // reports within a short interval so one physical press contributes once,
        // while rapid presses reported by the same source remain separate.
        let pairingWindow: TimeInterval = 0.12
        var recent = recentFunctionKeyEvents[keyCode, default: []].filter {
            abs(date.timeIntervalSince($0.date)) <= pairingWindow
        }
        if let duplicateIndex = recent.firstIndex(where: { $0.source != source }) {
            recent.remove(at: duplicateIndex)
            recentFunctionKeyEvents[keyCode] = recent
            return
        }

        recent.append(RecentFunctionKeyEvent(source: source, date: date))
        recentFunctionKeyEvents[keyCode] = recent
        onKeyDown?(keyCode, date)
    }

    private static func functionKeyCode(forSystemDefinedEvent event: CGEvent) -> Int? {
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else { return nil }

        let packedData = nsEvent.data1
        let keyType = (packedData >> 16) & 0xFFFF
        let keyState = packedData & 0xFF00
        guard keyState == 0x0A00 else { return nil } // Key-down, not key-up.

        // Map standard Apple keyboard top-row actions to their physical F-key slots.
        switch keyType {
        case 0: return 111   // Volume up -> F12
        case 1: return 103   // Volume down -> F11
        case 2: return 120   // Display brightness up -> F2
        case 3: return 122   // Display brightness down -> F1
        case 7: return 109   // Mute -> F10
        case 16: return 100  // Play/pause -> F8
        case 17: return 101  // Next track -> F9
        case 18: return 98   // Previous track -> F7
        case 19: return 101  // Fast forward -> F9
        case 20: return 98   // Rewind -> F7
        case 21: return 97   // Keyboard illumination up -> F6
        case 22: return 96   // Keyboard illumination down -> F5
        case 23: return 97   // Keyboard illumination toggle -> F6
        default:
            // Some keyboards report an auxiliary top-row action using the
            // corresponding virtual F-key code rather than an NX key type.
            return functionRowKeyCodes.contains(keyType) ? keyType : nil
        }
    }

    private static func functionRowKeyCode(usagePage: UInt32, usage: UInt32) -> Int? {
        // USB HID Keyboard/Keypad page: standard F1–F12 usages. Some keyboards
        // expose the physical function row this way even when macOS assigns the
        // keys system actions, so normalize them to the same keycodes as Quartz.
        if usagePage == 0x0007 {
            switch usage {
            case 0x003A: return 122 // F1
            case 0x003B: return 120 // F2
            case 0x003C: return 99  // F3
            case 0x003D: return 118 // F4
            case 0x003E: return 96  // F5
            case 0x003F: return 97  // F6
            case 0x0040: return 98  // F7
            case 0x0041: return 100 // F8
            case 0x0042: return 101 // F9
            case 0x0043: return 109 // F10
            case 0x0044: return 103 // F11
            case 0x0045: return 111 // F12
            default: return nil
            }
        }

        // USB HID Consumer page. These controls are the media/brightness actions
        // traditionally printed on the Mac's F1–F12 row.
        if usagePage == 0x000C {
            switch usage {
            case 0x006F: return 120 // Brightness up -> F2
            case 0x0070: return 122 // Brightness down -> F1
            case 0x0079: return 97  // Keyboard illumination up -> F6
            case 0x007A: return 96  // Keyboard illumination down -> F5
            case 0x00B3, 0x00B5: return 101 // Fast-forward / next track -> F9
            case 0x00B4, 0x00B6: return 98  // Rewind / previous track -> F7
            case 0x00CD: return 100 // Play/pause -> F8
            case 0x00E2: return 109 // Mute -> F10
            case 0x00E9: return 111 // Volume up -> F12
            case 0x00EA: return 103 // Volume down -> F11
            case 0x0221, 0x02A0: return 118 // Spotlight / Launchpad -> F4
            case 0x029F: return 99 // Mission Control -> F3
            default: return nil
            }
        }

        // Apple Vendor Keyboard page (0xFF01): Mission Control/Expose All and
        // Spotlight/Launchpad. Usage IDs are the controls exposed by Apple
        // keyboards; other vendor-page values are intentionally ignored.
        if usagePage == 0xFF01 {
            switch usage {
            case 0x0001, 0x0004: return 118 // Spotlight / Launchpad -> F4
            case 0x0010, 0x0011: return 99 // Expose All / Desktop -> F3
            case 0x0020: return 120 // Brightness up -> F2
            case 0x0021: return 122 // Brightness down -> F1
            default: return nil
            }
        }

        // Apple Vendor Top Case page (0xFF00): keyboard backlight controls.
        if usagePage == 0xFF00 {
            switch usage {
            case 0x0005: return 122 // Brightness down -> F1
            case 0x0004: return 120 // Brightness up -> F2
            case 0x0009: return 96  // Illumination down -> F5
            case 0x0007, 0x0008: return 97 // Illumination toggle/up -> F6
            default: return nil
            }
        }

        return nil
    }
}
