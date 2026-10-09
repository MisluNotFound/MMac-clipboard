import AppKit
import Combine
import Carbon.HIToolbox

enum SummonMode: String, CaseIterable, Identifiable {
    case caret
    case mouse
    case center

    var id: String { rawValue }

    var label: String {
        switch self {
        case .caret: return "跟随打字光标"
        case .mouse: return "跟随鼠标"
        case .center: return "屏幕居中"
        }
    }

    var footnote: String {
        switch self {
        case .caret: return "优先在打字光标处弹出，拿不到时依次退到焦点输入框、鼠标位置、屏幕居中"
        case .mouse: return "在鼠标指针所在位置弹出"
        case .center: return "始终在屏幕中央弹出"
        }
    }
}

final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let hotkeyCode = "hotkeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let historyLimit = "historyLimit"
        static let summonMode = "summonMode"
        static let launchAtLogin = "launchAtLogin"
    }

    @Published var hotkeyCode: UInt32 {
        didSet { defaults.set(Int(hotkeyCode), forKey: Keys.hotkeyCode) }
    }

    @Published var hotkeyModifiers: UInt32 {
        didSet { defaults.set(Int(hotkeyModifiers), forKey: Keys.hotkeyModifiers) }
    }

    @Published var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: Keys.historyLimit) }
    }

    @Published var summonMode: SummonMode {
        didSet { defaults.set(summonMode.rawValue, forKey: Keys.summonMode) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    init() {
        hotkeyCode = UInt32(defaults.object(forKey: Keys.hotkeyCode) as? Int ?? Int(kVK_ANSI_V))
        hotkeyModifiers = UInt32(defaults.object(forKey: Keys.hotkeyModifiers) as? Int ?? Int(cmdKey | shiftKey))
        let storedLimit = defaults.object(forKey: Keys.historyLimit) as? Int ?? 1000
        historyLimit = min(max(storedLimit, 100), 10_000)
        summonMode = SummonMode(rawValue: defaults.string(forKey: Keys.summonMode) ?? "") ?? .caret
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
    }

    var hotkeyDisplay: String {
        HotkeyManager.displayString(keyCode: CGKeyCode(hotkeyCode), carbonModifiers: hotkeyModifiers)
    }
}
