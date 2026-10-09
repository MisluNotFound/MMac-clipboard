import AppKit
import CryptoKit

/// 通过轮询 NSPasteboard.changeCount 监听系统剪贴板变化（无需任何权限）
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount: Int

    var onCapture: ((CapturePayload) -> Void)?

    init() {
        lastChangeCount = pasteboard.changeCount
    }

    func start(interval: TimeInterval = 0.25) {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let types = Set(pasteboard.types ?? [])
        var content: CapturePayload.Content?

        if types.contains(.png) || types.contains(.tiff) {
            content = readImage()
        }
        if content == nil, types.contains(.string) {
            if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content = .text(text)
            }
        }

        guard let content else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let payload = CapturePayload(
            content: content,
            imagePath: nil,
            contentHash: SHA256.hash(data: content.hashSeed).map { String(format: "%02x", $0) }.joined(),
            sourceBundleID: frontmost?.bundleIdentifier,
            sourceName: frontmost?.localizedName,
            capturedAt: Date()
        )
        onCapture?(payload)
    }

    private func readImage() -> CapturePayload.Content? {
        var pngData = pasteboard.data(forType: .png)
        var width = 0
        var height = 0

        if let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) {
            width = rep.pixelsWide
            height = rep.pixelsHigh
            if pngData == nil {
                pngData = rep.representation(using: .png, properties: [:])
            }
        } else if let png = pngData, let rep = NSBitmapImageRep(data: png) {
            width = rep.pixelsWide
            height = rep.pixelsHigh
        }

        guard let pngData, width > 0, height > 0 else { return nil }
        return .image(pngData: pngData, width: width, height: height)
    }
}

private extension CapturePayload.Content {
    var hashSeed: Data {
        switch self {
        case .text(let text):
            return Data("t:".utf8) + Data(text.utf8)
        case .image(let pngData, _, _):
            return Data("i:".utf8) + pngData
        }
    }
}
