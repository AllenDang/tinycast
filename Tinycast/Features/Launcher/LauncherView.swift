import SwiftUI

struct LauncherList: View {
    let results: [AppEntry]
    let selection: Int
    @EnvironmentObject private var core: AppCore

    var body: some View {
        Group {
            if results.isEmpty {
                EmptyResults(text: "No apps found")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, app in
                                AppRow(app: app, selected: index == selection)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture { core.launch(app) }
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

private struct AppRow: View {
    let app: AppEntry
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 28, height: 28)
            Text(app.name)
                .font(.system(size: 15))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
    }
}
