import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: SettingsStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            separator

            if state.filteredItems.isEmpty {
                emptyState
            } else {
                historyList
            }

            separator
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.30), radius: 16, x: 0, y: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .onAppear { searchFocused = true }
        .onChange(of: state.focusToken) { _ in searchFocused = true }
        .onChange(of: state.query) { _ in state.queryChanged() }
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("搜索剪贴板历史", text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
            if !state.query.isEmpty {
                Button {
                    state.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            Text("\(state.filteredItems.count) 条")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(state.filteredItems.enumerated()), id: \.element.id) { index, item in
                        ItemRow(
                            item: item,
                            index: state.query.isEmpty ? index : nil,
                            isSelected: index == state.selectedIndex,
                            now: Date()
                        )
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture { state.select(item) }
                        .contextMenu {
                            Button("粘贴") { state.select(item) }
                            Button("仅复制") { state.copyOnly(item) }
                            Divider()
                            Button("删除", role: .destructive) { state.delete(item) }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .onChange(of: state.selectedIndex) { newIndex in
                guard state.filteredItems.indices.contains(newIndex) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(state.filteredItems[newIndex].id, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: state.query.isEmpty ? "clipboard" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(state.query.isEmpty ? "还没有记录" : "没有匹配的结果")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if state.query.isEmpty {
                Text("复制点内容，然后按 \(settings.hotkeyDisplay) 唤起")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("↩ 粘贴")
            Text("↑↓ 选择")
            Text("1-9 快选")
            Text("⌫ 删除")
            Spacer()
            Text("\(settings.hotkeyDisplay) 唤起 · Esc 关闭")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }
}
