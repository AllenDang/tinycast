import SwiftUI
import KeyboardShortcuts

struct AppHotkeysSettingsView: View {
    @EnvironmentObject private var appIndex: AppIndex
    @State private var query = ""

    private var filtered: [AppEntry] {
        query.isEmpty ? appIndex.apps : appIndex.matches(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search apps…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            // A SwiftUI `List` swallows the click that the recorder (an NSSearchField) needs to
            // become first responder, so shortcuts never record. A ScrollView + LazyVStack keeps
            // the rows lazy while letting each recorder take focus on click.
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { app in
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 22, height: 22)
                            Text(app.name).lineLimit(1)
                            Spacer()
                            if let bundleID = app.bundleID {
                                KeyboardShortcuts.Recorder(for: .app(bundleID)) { shortcut in
                                    AppCore.shared.hotKeys.setBinding(bundleID: bundleID, hasShortcut: shortcut != nil)
                                }
                            } else {
                                Text("—").foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                    }
                }
                .thinOverlayScrollbar()
            }
        }
    }
}
