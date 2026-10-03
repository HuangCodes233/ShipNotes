import SwiftUI

struct SettingsView: View {
    @AppStorage(AppearanceManager.appStorageKey) private var appearance = ""

    var body: some View {
        TabView {
            AppStoreConnectSettingsView()
                .tabItem { Label(L("Account"), systemImage: "key") }
            AppleAdsSettingsView()
                .tabItem { Label(L("Apple Ads"), systemImage: "megaphone") }
            GeneralSettingsView()
                .tabItem { Label(L("General"), systemImage: "gear") }
            AISettingsView()
                .tabItem { Label(L("AI"), systemImage: "sparkles") }
        }
        .frame(width: 580, height: 540)
        .padding()
        .preferredColorScheme((AppearanceOption(rawValue: appearance) ?? .system).colorScheme)
    }
}
