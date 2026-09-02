import SwiftUI

struct ApplicationsSettingsView: View {
    var body: some View {
        SettingsPane(
            title: "Applications",
            subtitle: "Choose where Tinycast looks for apps, which ones appear in the launcher, and how to reach them."
        ) {
            SearchScopesCard()

            LauncherItemsCard(
                kind: .application,
                header: "Applications",
                searchPrompt: "Search applications…")
        }
    }
}
