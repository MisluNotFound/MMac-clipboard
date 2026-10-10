import AppKit
import SwiftUI

final class SummonsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 面板的完整生命周期：按策略定位、显示/隐藏动画、键盘导航与失焦自动收起
final class PanelController {
    /// 面板可见内容（毛玻璃）的尺寸
    static let panelSize = NSSize(width: 620, height: 540)
    static let cornerRadius: CGFloat = 20
    /// 窗口比内容大一圈，透明边距用于绘制自定义阴影
    /// （关掉系统投影：它按方形窗口轮廓计算，会在圆角外露出四个直角）
    static let shadowMargin: CGFloat = 28

    static var windowSize: NSSize {
        NSSize(width: panelSize.width + shadowMargin * 2,
               height: panelSize.height + shadowMargin * 2)
    }

    let panel: SummonsPanel
    private let state: AppState
    private let settings: SettingsStore
    private let locator = CaretLocator()
    var onOpenSettings: (() -> Void)?
    /// 唤起面板时的前台 App：选中条目后把 ⌘V 定向投递给它（在 makeKey 抢焦点之前记录）
    private(set) var targetApp: NSRunningApplication?

    private var localKeyMonitor: Any?
    private var globalMouseMonitor: Any?

    private static let digitKeyCodes: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
    ]

    init(state: AppState, settings: SettingsStore) {
        self.state = state
        self.settings = settings

        panel = SummonsPanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false

        let container = NSView(frame: NSRect(origin: .zero, size: Self.windowSize))
        container.wantsLayer = true

        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Self.cornerRadius
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false

        let hosting = NSHostingView(rootView: PanelView(state: state, settings: settings))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = Self.cornerRadius
        hosting.layer?.masksToBounds = true

        container.addSubview(effect)
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.shadowMargin),
            effect.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.shadowMargin),
            effect.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.shadowMargin),
            effect.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.shadowMargin),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.shadowMargin),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.shadowMargin),
            hosting.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.shadowMargin),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.shadowMargin),
        ])
        panel.contentView = container
    }

    // MARK: - 显示 / 隐藏

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        removeMonitors()

        // 定位按可见内容计算，再外扩出阴影边距得到窗口 frame
        let contentFrame = targetFrame()
        let frame = contentFrame.insetBy(dx: -Self.shadowMargin, dy: -Self.shadowMargin)
        var startOrigin = frame.origin
        startOrigin.y += 6
        panel.setFrameOrigin(startOrigin)
        panel.alphaValue = 0

        targetApp = NSWorkspace.shared.frontmostApplication
        state.prepareForShow()
        panel.orderFrontRegardless()
        panel.makeKey()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.panel.animator().setFrame(frame, display: true)
            self.panel.animator().alphaValue = 1
        })
        installMonitors()
        DispatchQueue.main.async { self.state.requestSearchFocus() }
    }

    func hide(completion: (() -> Void)? = nil) {
        removeMonitors()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.panel.animator().alphaValue = 0
        }, completionHandler: {
            self.panel.orderOut(nil)
            completion?()
        })
    }

    // MARK: - 定位策略

    private func targetFrame() -> NSRect {
        let size = Self.panelSize
        switch settings.summonMode {
        case .center:
            return centeredFrame(size: size)
        case .mouse:
            return anchoredFrame(size: size, anchorRect: nil, fallbackPoint: NSEvent.mouseLocation)
        case .caret:
            if let caret = locator.caretRect() {
                return anchoredFrame(size: size, anchorRect: caret, fallbackPoint: nil)
            }
            if let element = locator.focusedElementRect() {
                return anchoredFrame(size: size, anchorRect: element, fallbackPoint: nil)
            }
            return anchoredFrame(size: size, anchorRect: nil, fallbackPoint: NSEvent.mouseLocation)
        }
    }

    private func anchoredFrame(size: NSSize, anchorRect: CGRect?, fallbackPoint: CGPoint?) -> NSRect {
        // 无精确矩形时，以点为左下角构造一个一行的伪光标矩形
        let reference: CGRect
        if let anchorRect {
            reference = anchorRect
        } else if let fallbackPoint {
            reference = CGRect(origin: fallbackPoint, size: CGSize(width: 0, height: 16))
        } else {
            return centeredFrame(size: size)
        }

        let screen = screen(containing: CGPoint(x: reference.midX, y: reference.midY))
        let visible = screen.visibleFrame
        let margin: CGFloat = 8

        var x = reference.minX
        x = max(x, visible.minX + margin)
        if x + size.width > visible.maxX - margin {
            x = max(visible.minX + margin, visible.maxX - margin - size.width)
        }

        // 默认弹在锚点下方；下方空间不够则翻到锚点上方
        var y = reference.minY - margin - size.height
        if y < visible.minY + margin {
            y = reference.maxY + margin
        }
        y = max(y, visible.minY + margin)
        if y + size.height > visible.maxY - margin {
            y = max(visible.minY + margin, visible.maxY - margin - size.height)
        }

        return NSRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func centeredFrame(size: NSSize) -> NSRect {
        let screen = screen(containing: NSEvent.mouseLocation)
        let frame = screen.frame
        var x = frame.midX - size.width / 2
        var y = frame.midY - size.height / 2
        let visible = screen.visibleFrame
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        return NSRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func screen(containing point: CGPoint) -> NSScreen {
        NSScreen.screens.first { NSPointInRect(point, $0.frame) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: - 事件监控

    private func installMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            return self.handlePanelKey(event)
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            if !self.panel.frame.contains(NSEvent.mouseLocation) {
                self.hide()
            }
        }
    }

    private func removeMonitors() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
    }

    @discardableResult
    private func handlePanelKey(_ event: NSEvent) -> NSEvent? {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch keyCode {
        case 53: // Esc
            hide()
            return nil
        case 36, 76: // Return / 小键盘 Enter
            state.selectFocused()
            return nil
        case 125:
            state.moveSelection(by: 1)
            return nil
        case 126:
            state.moveSelection(by: -1)
            return nil
        case 51 where state.query.isEmpty: // Backspace：清空搜索时删除选中条目
            state.deleteFocused()
            return nil
        default:
            break
        }

        // 搜索为空时，数字键 1-9 直接选中对应条目
        if state.query.isEmpty, modifiers.isEmpty,
           let digit = Self.digitKeyCodes[keyCode], digit <= state.filteredItems.count {
            state.selectItem(at: digit - 1)
            return nil
        }
        // ⌘, 打开设置（macOS 惯例，菜单栏图标被溢出隐藏时仍可达）
        if keyCode == 43, modifiers == .command {
            onOpenSettings?()
            return nil
        }
        return event
    }
}
