import AppKit
import SwiftUI

struct ItemRow: View {
    let item: ClipboardItem
    let index: Int?
    let isSelected: Bool
    let now: Date

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            if let index, itemShowsBadge(at: index) {
                Text("\(index + 1)")
                    .monospacedDigit()
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, alignment: .trailing)
            }

            switch item.kind {
            case .text:
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayText)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    if let source = item.sourceName {
                        Text(source)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            case .image:
                if let thumbnail = thumbnailImage {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.sizeDescription ?? "图片")
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    if let source = item.sourceName {
                        Text(source)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if let icon = AppIconCache.icon(forBundleID: item.sourceBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(Self.relativeFormatter.localizedString(for: item.createdAt, relativeTo: now))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .onHover { hovering = $0 }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if isSelected { return Color.accentColor.opacity(0.20) }
        if hovering { return Color.primary.opacity(0.05) }
        return .clear
    }

    private var thumbnailImage: NSImage? {
        guard let path = item.imagePath else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private func itemShowsBadge(at index: Int) -> Bool {
        index < 9
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

/// 按 bundleID 缓存来源 App 图标
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        cache[bundleID] = icon
        return icon
    }
}
