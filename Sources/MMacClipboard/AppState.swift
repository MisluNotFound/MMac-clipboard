import AppKit
import Combine
import Foundation

/// 面板 UI 的唯一数据源：内存中的历史列表 + 选中态 + 搜索词
final class AppState: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var selectedIndex = 0
    @Published var query = ""
    @Published private(set) var focusToken = UUID()

    /// 条目被选中（回车/点击/数字键）后由 AppDelegate 执行写剪贴板 + 隐藏 + 粘贴
    var onItemSelected: ((ClipboardItem) -> Void)?
    /// 仅复制不粘贴（右键菜单）
    var onItemCopied: ((ClipboardItem) -> Void)?
    /// 面板底栏的授权提示被点击
    var onOpenAccessibilitySettings: (() -> Void)?

    /// 辅助功能授权状态（面板每次弹出时刷新，用于底栏提示）
    @Published private(set) var accessibilityTrusted = AutoPaster.isTrusted

    private let store: SQLiteStore
    private let settings: SettingsStore
    private var clockTimer: Timer?

    init(store: SQLiteStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var filteredItems: [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        let needle = trimmed.lowercased()
        return items.filter { item in
            switch item.kind {
            case .text:
                return (item.text ?? "").lowercased().contains(needle)
            case .image:
                return (item.sourceName ?? "").lowercased().contains(needle)
            }
        }
    }

    // MARK: - 捕获入库

    func ingest(_ payload: CapturePayload) {
        var payload = payload
        var writtenImagePath: String?

        if case .image(let pngData, _, _) = payload.content {
            let fileName = UUID().uuidString + ".png"
            let fileURL = store.imagesDirectory.appendingPathComponent(fileName)
            do {
                try pngData.write(to: fileURL)
                writtenImagePath = fileURL.path
                payload.imagePath = fileURL.path
            } catch {
                NSLog("图片落盘失败: \(error)")
                return
            }
        }

        do {
            let result = try store.upsert(payload)
            if case .touched = result, let path = writtenImagePath {
                // 已有相同内容，刚写入的文件成为孤儿，清掉
                try? FileManager.default.removeItem(atPath: path)
            }
        } catch {
            NSLog("入库失败: \(error)")
            return
        }

        pruneToLimit()
        reload()
    }

    func pruneToLimit() {
        let removed = store.prune(limit: settings.historyLimit)
        removed.forEach { try? FileManager.default.removeItem(atPath: $0) }
    }

    func reload() {
        items = store.loadAll()
        clampSelection()
    }

    func clearAll() {
        let paths = store.clearAll()
        paths.forEach { try? FileManager.default.removeItem(atPath: $0) }
        reload()
    }

    // MARK: - 选中与交互

    func prepareForShow() {
        query = ""
        selectedIndex = 0
        accessibilityTrusted = AutoPaster.isTrusted
    }

    func queryChanged() {
        selectedIndex = 0
    }

    func requestSearchFocus() {
        focusToken = UUID()
    }

    func moveSelection(by delta: Int) {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta % count + count) % count
    }

    func selectItem(at index: Int) {
        let items = filteredItems
        guard items.indices.contains(index) else { return }
        select(items[index])
    }

    func selectFocused() {
        selectItem(at: selectedIndex)
    }

    func select(_ item: ClipboardItem) {
        onItemSelected?(item)
    }

    func copyOnly(_ item: ClipboardItem) {
        onItemCopied?(item)
    }

    func deleteFocused() {
        let items = filteredItems
        guard items.indices.contains(selectedIndex) else { return }
        delete(items[selectedIndex])
    }

    func delete(_ item: ClipboardItem) {
        if let path = store.delete(id: item.id) {
            try? FileManager.default.removeItem(atPath: path)
        }
        reload()
    }

    private func clampSelection() {
        let count = filteredItems.count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex, 0), count - 1)
    }
}
