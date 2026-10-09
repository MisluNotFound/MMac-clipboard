import AppKit
import Carbon
import Carbon.HIToolbox

/// 基于 Carbon RegisterEventHotKey 的全局快捷键（无需权限）
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var currentKeyCode: UInt32?
    private var currentModifiers: UInt32?
    private var handler: (() -> Void)?
    private var installed = false

    private static let eventSpec = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
    )
    private static let signature: OSType = 0x4D4D4342 // 'MMCB'

    func register(keyCode: UInt32, carbonModifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        unregister()

        let hotKeyID = EventHotKeyID(signature: HotkeyManager.signature, id: 1)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else {
            NSLog("注册全局快捷键失败: \(status)")
            return
        }
        hotKeyRef = newRef
        currentKeyCode = keyCode
        currentModifiers = carbonModifiers
        installHandlerIfNeeded()
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        currentKeyCode = nil
        currentModifiers = nil
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = Self.eventSpec
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let getStatus = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard getStatus == noErr, hotKeyID.signature == HotkeyManager.signature else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.handler?() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), nil)
    }
}

// MARK: - 快捷键的显示与转换

extension HotkeyManager {
    static func carbonMask(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }

    static func nseventMask(fromCarbon mask: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if mask & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if mask & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if mask & UInt32(optionKey) != 0 { flags.insert(.option) }
        if mask & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    static func displayString(keyCode: CGKeyCode, carbonModifiers: UInt32) -> String {
        var result = ""
        let flags = nseventMask(fromCarbon: carbonModifiers)
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        result += keyLabel(for: UInt32(keyCode)) ?? "Key\(keyCode)"
        return result
    }

    static func keyLabel(for keyCode: UInt32) -> String? {
        Self.keyLabels[keyCode]
    }

    private static let keyLabels: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 48: "⇥", 49: "空格", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12",
    ]
}
