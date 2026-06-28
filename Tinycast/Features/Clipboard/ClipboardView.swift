import SwiftUI

struct ClipboardList: View {
    let results: [ClipboardItem]
    let selection: Int
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    @EnvironmentObject private var store: ClipboardStore

    var body: some View {
        Group {
            if results.isEmpty {
                EmptyResults(text: "Clipboard history is empty")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                ClipboardRow(item: item, selected: index == selection, imageURL: store.imageURL(for: item))
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { onSelect(index); onActivate() }
                                    .onTapGesture { onSelect(index) }
                                    .contextMenu {
                                        Button("Paste") { onSelect(index); onActivate() }
                                        Button("Delete", role: .destructive) { store.remove(item) }
                                    }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selection) { proxy.scrollTo(selection, anchor: .center) }
                }
            }
        }
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let selected: Bool
    let imageURL: URL?

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            Text(previewText)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
    }

    private var previewText: String {
        switch item.kind {
        case .text: return (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case .image: return "Image"
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.kind {
        case .text:
            Image(systemName: "text.alignleft")
                .frame(width: 26, height: 20)
                .foregroundStyle(.secondary)
        case .image:
            if let url = imageURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo").frame(width: 26, height: 20).foregroundStyle(.secondary)
            }
        }
    }
}

struct ClipboardPreview: View {
    let item: ClipboardItem?
    @EnvironmentObject private var store: ClipboardStore

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 0) {
                content(for: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                footer(for: item)
            }
            .padding(16)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func content(for item: ClipboardItem) -> some View {
        switch item.kind {
        case .text:
            ScrollView {
                Text(item.text ?? "")
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .image:
            if let url = store.imageURL(for: item), let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo").font(.system(size: 40)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func footer(for item: ClipboardItem) -> some View {
        HStack {
            Text(metadata(for: item))
            Spacer()
            Text("\(item.createdAt, style: .relative) ago")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }

    private func metadata(for item: ClipboardItem) -> String {
        switch item.kind {
        case .text:
            let count = (item.text ?? "").count
            return "Text · \(count) character\(count == 1 ? "" : "s")"
        case .image:
            if let url = store.imageURL(for: item), let image = NSImage(contentsOf: url) {
                return "Image · \(Int(image.size.width))×\(Int(image.size.height))"
            }
            return "Image"
        }
    }
}
