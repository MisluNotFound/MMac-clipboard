import AppKit
import ApplicationServices

/// 定位面板唤起位置：打字光标 → 焦点输入框 → 鼠标 → 屏幕居中
struct CaretLocator {
    /// 通过辅助功能 API 尝试拿到打字光标（插入点）的屏幕矩形。
    /// 返回值已从 AX 的“主屏左上原点”坐标转换为 AppKit 的“主屏左下原点”坐标。
    func caretRect() -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef else { return nil }
        let focused = unsafeBitCast(focusedRef, to: AXUIElement.self)

        guard supportsTextEditing(focused) else { return nil }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef else { return nil }
        let selectedRange = unsafeBitCast(rangeRef, to: AXValue.self)

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focused, kAXBoundsForRangeParameterizedAttribute as CFString, selectedRange, &boundsRef
        ) == .success, let boundsRef else { return nil }

        var axRect = CGRect.zero
        guard AXValueGetValue(unsafeBitCast(boundsRef, to: AXValue.self), .cgRect, &axRect) else { return nil }
        guard axRect.origin.x.isFinite, axRect.origin.y.isFinite,
              axRect.width >= 0, axRect.height >= 0, !axRect.isInfinite else { return nil }
        return Self.cocoaRect(fromAXRect: axRect)
    }

    /// 拿不到光标时，退而求其次拿焦点元素整体的矩形
    func focusedElementRect() -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef else { return nil }
        let focused = unsafeBitCast(focusedRef, to: AXUIElement.self)

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(focused, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else { return nil }

        var axPosition = CGPoint.zero
        var axSize = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(positionRef, to: AXValue.self), .cgPoint, &axPosition),
              AXValueGetValue(unsafeBitCast(sizeRef, to: AXValue.self), .cgSize, &axSize) else { return nil }

        let axRect = CGRect(origin: axPosition, size: axSize)
        guard axRect.origin.x.isFinite, axRect.origin.y.isFinite, !axRect.isInfinite else { return nil }
        return Self.cocoaRect(fromAXRect: axRect)
    }

    private func supportsTextEditing(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let roleRef else { return true } // 拿不到 role 也允许继续尝试取选区
        let role = unsafeBitCast(roleRef, to: NSString.self) as String
        let editableRoles: Set<String> = [
            "AXTextArea", "AXTextField", "AXSearchField",
            "AXWebArea", "AXStaticText", "AXComboBox",
        ]
        return editableRoles.contains(role)
    }

    /// AX 坐标以主屏左上角为原点，AppKit 全局坐标以主屏左下角为原点
    static func cocoaRect(fromAXRect rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        return CGRect(
            x: rect.origin.x,
            y: primary.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
