# MMac-clipboard

> A macOS clipboard history manager that summons at your text cursor and pastes on Enter. Native Swift + SwiftUI.

macOS 剪贴板历史工具。菜单栏常驻，全局快捷键在打字光标处唤起毛玻璃面板，选中即复制并自动粘贴。Swift + SwiftUI 原生实现。

## 截图

<p align="center">
  <img src="Docs/screenshot-history.png" width="620" alt="历史列表面板">
</p>
<p align="center">
  <img src="Docs/screenshot-empty.png" width="620" alt="空状态面板">
</p>

## 功能

- 记录文字与图片剪贴板历史（SQLite + 图片文件持久化，默认上限 1000 条）
- 全局快捷键（默认 `⇧⌘V`，可自定义）唤起面板
- 面板唤起位置：跟随打字光标（AX 辅助功能定位，逐级降级到焦点输入框 → 鼠标 → 屏幕居中）/ 跟随鼠标 / 屏幕居中
- 输入即搜索、`↑↓` 导航、`↩` 粘贴、`1-9` 快速选择、`⌫` 删除、`Esc` 关闭
- 选中后自动粘贴回之前的输入位置（需要辅助功能授权，唯一权限）
- 登录时自动启动（SMAppService）
- 深浅色自动跟随

## 构建

依赖：macOS 13+，Xcode Command Line Tools（`xcode-select --install`）。

```bash
./scripts/build-app.sh
open build/MMac-clipboard.app
```

## 首次使用

1. 启动后菜单栏出现剪贴板图标。
2. 按 `⇧⌘V` 唤起面板；首次粘贴会引导前往 系统设置 → 隐私与安全性 → 辅助功能 授权（用于自动粘贴与光标定位，不授权则退化为仅复制）。

> **开发注意**：本地构建使用 ad-hoc 签名，每次重新构建指纹都会变化，系统里的辅助功能授权会静默失效。`./scripts/build-app.sh` 重新打包后，请在辅助功能列表中先移除旧的 MMac-clipboard 再重新添加。面板底栏出现橙色「未授权辅助功能」提示即为授权失效信号。

## 数据位置

- 数据库：`~/Library/Application Support/MMac-clipboard/history.sqlite`
- 图片：`~/Library/Application Support/MMac-clipboard/images/`

## 开发与测试

```bash
# 自动化冒烟：弹出面板 → 搜索过滤 → 键盘导航 → 选中写回剪贴板 → 隐藏 → 打开设置窗口，全绿退出码 0
swift build && .build/debug/MMacClipboard --self-test

# 启动即弹出面板（便于联调）
.build/debug/MMacClipboard --show-panel
```

## 目录结构

```
Sources/MMacClipboard/
    main.swift              入口（NSApplication 手动装配）
    AppDelegate.swift       总装：菜单栏、面板、监听、快捷键、粘贴流程
    AppState.swift          面板数据源（列表、选中态、搜索）
    Models.swift            ClipboardItem / CapturePayload
    ClipboardMonitor.swift  changeCount 轮询监听
    SQLiteStore.swift       SQLite 持久化
    HotkeyManager.swift     Carbon 全局快捷键
    CaretLocator.swift      AX 打字光标定位 + 降级链
    PanelController.swift   浮动面板（定位、动画、键盘/鼠标监控）
    AutoPaster.swift        CGEvent 合成 ⌘V
    LoginItemService.swift  登录自启
    SettingsStore.swift     用户设置（UserDefaults）
    Views/                  SwiftUI 界面（面板、条目行、设置）
Resources/Info.plist        app bundle 描述（LSUIElement 等）
scripts/build-app.sh        构建打包脚本
```

## 许可

[MIT](LICENSE)
