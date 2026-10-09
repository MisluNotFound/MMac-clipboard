import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var state: AppState

    @State private var showingClearConfirmation = false
    @State private var accessibilityTrusted = AutoPaster.isTrusted
    @State private var refreshTimer: Timer?

    var body: some View {
        Form {
            Section("通用") {
                Toggle("登录时自动启动", isOn: $settings.launchAtLogin)

                HStack {
                    LabeledContent("全局快捷键") {
                        HotkeyRecorder(settings: settings)
                    }
                }
                Button("恢复默认 (⇧⌘V)") {
                    settings.hotkeyCode = UInt32(9)
                    settings.hotkeyModifiers = UInt32(cmdKey | shiftKey)
                }
                .controlSize(.small)

                Picker("历史记录上限", selection: $settings.historyLimit) {
                    Text("200").tag(200)
                    Text("500").tag(500)
                    Text("1000").tag(1000)
                    Text("2000").tag(2000)
                }
                .pickerStyle(.segmented)
                Text("当前共 \(state.items.count) 条记录")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Section("面板唤起位置") {
                Picker("唤起位置", selection: $settings.summonMode) {
                    ForEach(SummonMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(settings.summonMode.footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Section("数据") {
                Button("清空全部历史", role: .destructive) {
                    showingClearConfirmation = true
                }
            }

            Section("权限") {
                HStack {
                    Text("辅助功能（自动粘贴）")
                    Spacer()
                    if accessibilityTrusted {
                        Label("已授权", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Button("去授权") {
                            AutoPaster.requestTrust(prompt: true)
                        }
                        .controlSize(.small)
                    }
                }
                Text("自动粘贴需要辅助功能权限；仅复制和剪贴板记录不受影响。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 520)
        .confirmationDialog("确定清空全部历史记录吗？此操作无法撤销。", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("清空", role: .destructive) { state.clearAll() }
            Button("取消", role: .cancel) {}
        }
        .onAppear { startMonitoringTrust() }
        .onDisappear { refreshTimer?.invalidate() }
    }

    private func startMonitoringTrust() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            accessibilityTrusted = AutoPaster.isTrusted
        }
    }
}

// MARK: - 快捷键录制控件

private struct HotkeyRecorder: NSViewRepresentable {
    @ObservedObject var settings: SettingsStore

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.settings = settings
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.settings = settings
        button.refreshTitle()
    }
}

/// 点击进入录制态，按下任意「含 ⌘/⌥/⌃ 修饰」的组合即保存；Esc 取消
private final class RecorderButton: NSButton {
    var settings: SettingsStore? {
        didSet { refreshTitle() }
    }

    private var recording = false {
        didSet { refreshTitle() }
    }

    override var acceptsFirstResponder: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 140, height: 28))
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func beginRecording() {
        recording = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 { // Esc 取消
            recording = false
            return
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // 至少需要一个非 Shift 修饰键，避免单键全局热键误触发
        guard !modifiers.intersection([.command, .option, .control]).isEmpty else {
            NSSound.beep()
            return
        }
        settings?.hotkeyCode = UInt32(event.keyCode)
        settings?.hotkeyModifiers = HotkeyManager.carbonMask(from: modifiers)
        recording = false
    }

    func refreshTitle() {
        guard let settings else { return }
        title = recording ? "按下新的组合键…" : settings.hotkeyDisplay
    }
}

// MARK: - 设置窗口

final class SettingsWindowController: NSWindowController {
    init(settings: SettingsStore, state: AppState) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置 · MMac-clipboard"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings, state: state))
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}
