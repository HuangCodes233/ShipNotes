import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings
    @State private var appSearch = ""

    private var filteredApps: [AppRecord] {
        let query = appSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return state.apps }
        return state.apps.filter {
            $0.name.localizedStandardContains(query) || $0.bundleId.localizedStandardContains(query)
        }
    }

    var body: some View {
        @Bindable var state = state

        VStack(alignment: .leading, spacing: 0) {
            accountHeader

            appsSection

            Button {
                openSettings()
            } label: {
                Label(L("Settings"), systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .shipNotesSidebarBackground))
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(L("Apps"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await state.refreshApps() }
                } label: {
                    Label(L("Refresh Apps"), systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .disabled(state.isLoadingRemote || state.isUsingMockData)
                .help(L("Refresh the app list from App Store Connect."))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            appSearchField

            ScrollView {
                LazyVStack(spacing: 3) {
                    if state.apps.isEmpty && !state.isLoadingRemote {
                        VStack(spacing: 8) {
                            Image(systemName: "square.stack.3d.up.slash")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary.opacity(0.6))
                            Text(L("No apps found"))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                    } else if filteredApps.isEmpty && !state.isLoadingRemote {
                        Text(L("No matching apps"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(filteredApps) { app in
                            Button {
                                state.selectApp(app.id)
                            } label: {
                                AppRow(app: app, isSelected: state.selectedAppId == app.id)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(app.name)
                            .accessibilityValue(state.selectedAppId == app.id ? L("Selected") : "")
                            .help("\(app.name)\n\(app.bundleId)")
                        }
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .top) {
                if state.isLoadingRemote {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 8)
                }
            }
        }
        // No background here: the sidebar-level background in `body` already
        // covers this section; repeating it per-subtree only stacks layers.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var appSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(L("Search apps"), text: $appSearch)
                .textFieldStyle(.plain)
                .onExitCommand { appSearch = "" }
                .onSubmit {
                    if filteredApps.count == 1, let app = filteredApps.first {
                        state.selectApp(app.id)
                    }
                }
                .help(L("Search by name or bundle ID. Press Return to open a single match."))
            if !appSearch.isEmpty {
                Button {
                    appSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Clear search"))
                .help(L("Clear search"))
            }
        }
        .font(.callout)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var accountHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: state.isUsingMockData ? "key.slash" : "key.fill")
                    .foregroundStyle(.tint)
                Text(state.accounts.first?.name ?? L("No account"))
                    .font(.headline)
                Spacer()

                // Status Pill
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.isUsingMockData ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)
                    Text(state.isUsingMockData ? L("MOCK") : L("LIVE"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(state.isUsingMockData ? Color.orange : Color.green)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((state.isUsingMockData ? Color.orange : Color.green).opacity(0.12), in: Capsule())

                if state.isAIConfigured {
                    Image(systemName: state.isAIRunning ? "sparkles.rectangle.stack.fill" : "sparkles")
                        .foregroundStyle(.purple)
                        .help(L("AI: %@ · %@", state.selectedAIProvider.displayName, state.currentAIModel))
                        .symbolEffect(.pulse, options: .repeating, isActive: state.isAIRunning)
                }
            }
            Text(state.accounts.first.map { state.isUsingMockData ? L(state.connectionStatus) : L("Key %@", $0.keyId) } ?? L("Add an API key to begin"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if state.isAIConfigured {
                Text(L("AI: %@ · %@", state.selectedAIProvider.displayName, state.currentAIModel))
                    .font(.caption2)
                    .foregroundStyle(.purple.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

}

extension NSColor {
    // Derived from a system appearance color so the sidebar tracks macOS
    // (light/dark/contrast) instead of frozen-in-time hardcoded RGB values.
    static var shipNotesSidebarBackground: NSColor {
        .underPageBackgroundColor
    }
}

private struct AppRow: View {
    let app: AppRecord
    let isSelected: Bool
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(app: app, size: 24, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(app.bundleId)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isSelected ? .white.opacity(0.78) : .secondary)
            }
            Spacer()
            Text(app.platform)
                .font(.caption2)
                .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background {
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.18) : Color.secondary.opacity(0.14))
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.88)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            } else if isHovered {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { hover in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                isHovered = hover
            }
        }
    }
}
