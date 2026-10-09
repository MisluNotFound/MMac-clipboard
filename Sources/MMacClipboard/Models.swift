import Foundation

enum ItemKind: String {
    case text
    case image
}

struct ClipboardItem: Identifiable, Equatable {
    let id: Int64
    let kind: ItemKind
    var text: String?
    var imagePath: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var sourceBundleID: String?
    var sourceName: String?
    var createdAt: Date
    var contentHash: String

    var displayText: String {
        switch kind {
        case .text:
            return (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case .image:
            return ""
        }
    }

    var sizeDescription: String? {
        guard kind == .image, let w = pixelWidth, let h = pixelHeight else { return nil }
        return "\(w)×\(h)"
    }
}

/// 一次剪贴板捕获的原始载荷，入库前的中转结构
struct CapturePayload {
    enum Content {
        case text(String)
        case image(pngData: Data, width: Int, height: Int)

        var kindRaw: String {
            switch self {
            case .text: return ItemKind.text.rawValue
            case .image: return ItemKind.image.rawValue
            }
        }
    }

    let content: Content
    /// 图片条目已写入磁盘的 PNG 路径（入库前由调用方落盘）
    var imagePath: String?
    let contentHash: String
    let sourceBundleID: String?
    let sourceName: String?
    let capturedAt: Date
}
