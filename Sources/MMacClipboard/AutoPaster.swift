import AppKit
import ApplicationServices
import CoreGraphics

enum AutoPaster {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 弹系统授权引导（prompt 传 true 时弹出系统弹窗）
    static func requestTrust(prompt: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 合成一次 ⌘V 按键。优先按进程 ID 定向投递给目标 App（避免焦点竞态），
    /// 没有目标时退回系统 HID 层广播。需要辅助功能授权。
    static func paste(into target: NSRunningApplication?) {
        guard AXIsProcessTrusted() else { return }
        let pid = target?.processIdentifier
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(9) // kVK_ANSI_V

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyUp?.flags = .maskCommand

        if let pid, target?.isTerminated == false {
            NSLog("[paste] 定向投递 ⌘V → pid \(pid) (\(target?.bundleIdentifier ?? "?"))")
            keyDown?.postToPid(pid)
            keyUp?.postToPid(pid)
        } else {
            NSLog("[paste] 广播 ⌘V 到 HID 层")
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}
