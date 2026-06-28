import SwiftUI

struct LauncherList: View {
    let results: [AppEntry]
    let selectedID: AppEntry.ID?
    @EnvironmentObject private var core: AppCore

    var body: some View {
        Group {
            if results.isEmpty {
                EmptyResults(text: "No apps found")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(results) { app in
                                AppRow(app: app, selected: app.id == selectedID)
                                    .contentShape(Rectangle())
                                    .onTapGesture { core.launch(app) }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedID) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
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
