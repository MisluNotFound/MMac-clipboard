import AppKit
import Combine
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsStore!
    private var store: SQLiteStore!
    private var state: AppState!
    private var panel: PanelController!
    private var hotkey: HotkeyManager!
    private var monitor: ClipboardMonitor!
    private var settingsWindowController: NSWindowController?
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var applyingInternalSettingChange = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsStore()
        store = try? SQLiteStore()
        if store == nil {
            presentFatalError("历史数据库无法打开，请检查 ~/Library/Application Support/MMac-clipboard 目录权限。")
            return
        }

        state = AppState(store: store, settings: settings)
        state.onItemSelected = { [weak self] item in self?.itemSelected(item) }
        state.onItemCopied = { [weak self] item in
            PasteboardWriter.write(item)
            self?.panel.hide()
        }
        state.onOpenAccessibilitySettings = { [weak self] in
            self?.panel.hide()
            AutoPaster.openAccessibilitySettings()
        }
        state.reload()
        state.pruneToLimit()

        panel = PanelController(state: state, settings: settings)
        panel.onOpenSettings = { [weak self] in
            self?.openSettings()
        }

        monitor = ClipboardMonitor()
        monitor.onCapture = { [weak state] payload in
            state?.ingest(payload)
        }
        monitor.start()

        hotkey = HotkeyManager()
        registerHotkey()

        setupStatusItem()
        observeSettings()

        // 测试辅助：--show-panel 启动后自动弹出面板（供自动化验证）
        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.panel.show()
            }
        }
        // 测试辅助：--self-test 自动跑一遍核心交互管线后退出
        if CommandLine.arguments.contains("--self-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.runSelfTest()
            }
        }
    }

    private func runSelfTest() {
        var passed = true
        func check(_ condition: Bool, _ name: String) {
            print("[SELFTEST] \(condition ? "PASS" : "FAIL") — \(name)")
            if !condition { passed = false }
        }

        // 自带种子：插入一条唯一文本，测完删除，不依赖外部历史
        let marker = "SELFTEST-\(UUID().uuidString.prefix(8))"
        let expectedText = "\(marker) 自动化冒烟条目"
        state.ingest(CapturePayload(
            content: .text(expectedText),
            imagePath: nil,
            contentHash: "selftest-\(marker)",
            sourceBundleID: nil,
            sourceName: "SelfTest",
            capturedAt: Date()
        ))
        defer { if let seeded = state.items.first(where: { $0.text == expectedText }) { state.delete(seeded) } }

        panel.show()
        check(panel.panel.isVisible, "show() 后面板可见")
        check(state.filteredItems.count >= 3, "历史记录已加载（\(state.filteredItems.count) 条）")

        state.query = marker
        check(state.filteredItems.count == 1 && state.filteredItems.first?.displayText == expectedText, "搜索过滤命中唯一条目")

        state.query = ""
        state.moveSelection(by: 1)
        check(state.selectedIndex == 1, "↓ 移动选中到第 2 条")
        state.moveSelection(by: -1)
        check(state.selectedIndex == 0, "↑ 回到第 1 条")

        guard let target = state.items.first(where: { $0.displayText == expectedText }) else {
            print("[SELFTEST] FAIL — 找不到目标条目")
            exit(2)
        }
        state.select(target)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            check(!self.panel.panel.isVisible, "选中后面板已隐藏")
            let pasted = NSPasteboard.general.string(forType: .string)
            check(pasted?.trimmingCharacters(in: .whitespacesAndNewlines) == expectedText, "选中内容已写入剪贴板")

            self.openSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                check(self.settingsWindowController?.window?.isVisible == true, "设置窗口可正常打开")
                self.settingsWindowController?.close()
                print("[SELFTEST] \(passed ? "ALL PASS" : "存在失败项")")
                exit(passed ? 0 : 2)
            }
        }
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "MMac-clipboard")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "显示剪贴板历史", action: #selector(togglePanel), keyEquivalent: "")
        menu.items.last?.target = self
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 MMac-clipboard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.last?.target = NSApp
        item.menu = menu
        statusItem = item
    }

    // MARK: - 设置联动

    private func observeSettings() {
        settings.$historyLimit
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.state.pruneToLimit()
                self?.state.reload()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(settings.$hotkeyCode, settings.$hotkeyModifiers)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.registerHotkey()
            }
            .store(in: &cancellables)

        settings.$launchAtLogin
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self, !self.applyingInternalSettingChange else { return }
                do {
                    try LoginItemService.setEnabled(enabled)
                } catch {
                    NSAlert.show(message: "设置登录项失败：\(error.localizedDescription)")
                    self.applyingInternalSettingChange = true
                    self.settings.launchAtLogin = LoginItemService.isEnabled
                    self.applyingInternalSettingChange = false
                }
            }
            .store(in: &cancellables)
    }

    private func registerHotkey() {
        hotkey.register(keyCode: settings.hotkeyCode,
                        carbonModifiers: settings.hotkeyModifiers) { [weak self] in
            self?.togglePanel()
        }
    }

    // MARK: - 动作

    @objc private func togglePanel() {
        panel.toggle()
    }

    @objc private func openSettings() {
        panel.hide()
        if settingsWindowController == nil {
            let controller = SettingsWindowController(settings: settings, state: state)
            settingsWindowController = controller
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func itemSelected(_ item: ClipboardItem) {
        PasteboardWriter.write(item)
        panel.hide { [weak self] in
            guard let self else { return }
            if AutoPaster.isTrusted {
                let target = self.panel.targetApp ?? NSWorkspace.shared.frontmostApplication
                // 显式唤回目标 App，给系统一点时间恢复键盘焦点，再定向投递 ⌘V
                target?.activate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    AutoPaster.paste(into: target)
                }
            } else {
                NSLog("[paste] 跳过：辅助功能未授权")
                self.showAccessibilityHintIfNeeded()
            }
        }
    }

    private func showAccessibilityHintIfNeeded() {
        guard !CommandLine.arguments.contains("--self-test") else { return }
        let key = "didShowAccessibilityHint"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "尚未授权辅助功能"
        alert.informativeText = "内容已复制到剪贴板，但自动粘贴需要在 系统设置 → 隐私与安全性 → 辅助功能 中授权 MMac-clipboard。"
        alert.addButton(withTitle: "去授权")
        alert.addButton(withTitle: "稍后再说")
        if alert.runModal() == .alertFirstButtonReturn {
            AutoPaster.openAccessibilitySettings()
        }
    }

    private func presentFatalError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "MMac-clipboard 无法启动"
        alert.informativeText = message
        alert.addButton(withTitle: "退出")
        alert.runModal()
        NSApp.terminate(nil)
    }
}

// MARK: - 剪贴板写入

enum PasteboardWriter {
    static func write(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            pasteboard.setString(item.text ?? "", forType: .string)
        case .image:
            if let path = item.imagePath,
               let data = FileManager.default.contents(atPath: path) {
                pasteboard.setData(data, forType: .png)
            }
        }
    }
}

extension NSAlert {
    static func show(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
