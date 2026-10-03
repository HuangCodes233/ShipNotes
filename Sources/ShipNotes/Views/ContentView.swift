import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHistory = false
    @AppStorage(SettingsKey.hasSeenOnboarding) private var hasSeenOnboarding = false
    @State private var showOnboarding = false
    // Persisted so the sidebar survives relaunches instead of always
    // reappearing. App-level preference (not per-window), hence @AppStorage.
    @AppStorage("shipnotes.sidebarVisible") private var isSidebarVisible = true
    // View-level @AppStorage is reliably reactive (unlike App-scene level), so
    // flipping the appearance in Settings updates this window live.
    @AppStorage(AppearanceManager.appStorageKey) private var appearanceRaw: String = ""

    private let sidebarWidth: CGFloat = 260
    private let sidebarAnimation = Animation.linear(duration: 0.28)

    // Release-notes split: the workspace pane's width is persisted so the
    // divider survives relaunches, matching the Store Copy workspace.
    private let workspaceMinWidth: CGFloat = 380
    private let inspectorMinWidth: CGFloat = 400
    private let splitDividerHitWidth: CGFloat = 12
    @SceneStorage("releaseNotes.workspacePaneWidth") private var workspacePaneWidth = 500.0
    @GestureState private var workspacePaneDragOffset: CGFloat = 0

    var body: some View {
        @Bindable var state = state

        splitLayout
            .preferredColorScheme((AppearanceOption(rawValue: appearanceRaw) ?? .system).colorScheme)
            .toolbar { mainToolbar }
            .safeAreaInset(edge: .top, spacing: 0) {
                TopBannerStack()
            }
            .sheet(isPresented: $showHistory) {
                SyncHistoryView()
                    .environment(state)
            }
            .sheet(
                isPresented: Binding(
                    get: { state.pendingImport != nil },
                    set: { if !$0 { state.cancelPendingImport() } }
                )
            ) {
                ImportReviewSheet()
                    .environment(state)
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingSheet {
                    hasSeenOnboarding = true
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { state.showPromoteVersionSheet },
                    set: { state.showPromoteVersionSheet = $0 }
                )
            ) {
                PromoteVersionSheet()
                    .environment(state)
            }
            .onChange(of: state.dryRunCompletionTick) { _, _ in
                // Dry runs are silent otherwise — pop the sheet so the user
                // can see the diff that was just computed.
                showHistory = true
            }
            .task {
                // First-launch: show the onboarding sheet exactly once if the
                // user hasn't already connected an App Store Connect account.
                if !hasSeenOnboarding && state.isUsingMockData {
                    try? await Task.sleep(for: .nanoseconds(250_000_000))
                    showOnboarding = true
                }
            }
    }

    private var splitLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebarColumn

            switch state.workspaceMode {
            case .releaseNotes:
                releaseNotesSplit
            case .storeCopy:
                StoreCopyWorkspaceView()
                    .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
            case .screenshots:
                ScreenshotWorkspaceView()
                    .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
            case .ads:
                AdsWorkspaceView()
                    .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Errors and AI progress are surfaced once, by the banner stack in the
        // top safe-area inset. A second bottom-trailing toast for the same
        // `lastError` / `aiActivity` showed every message twice.
    }

    /// Custom split (rather than HSplitView, which can't report or restore its
    /// divider position) so the pane width round-trips through SceneStorage.
    private var releaseNotesSplit: some View {
        GeometryReader { geometry in
            let maxWorkspaceWidth = max(
                workspaceMinWidth,
                geometry.size.width - inspectorMinWidth - splitDividerHitWidth
            )
            let effectiveWorkspaceWidth = min(
                max(CGFloat(workspacePaneWidth) + workspacePaneDragOffset, workspaceMinWidth),
                maxWorkspaceWidth
            )

            HStack(spacing: 0) {
                WorkspaceView()
                    .frame(width: effectiveWorkspaceWidth)
                    .frame(maxHeight: .infinity)
                    .safeAreaInset(edge: .bottom, spacing: 0) { BottomCommandBar() }

                PaneSplitDivider(resizeDescription: L("Resize workspace"))
                    .frame(width: splitDividerHitWidth)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($workspacePaneDragOffset) { value, offset, _ in
                                offset = value.translation.width
                            }
                            .onEnded { value in
                                let proposedWidth = CGFloat(workspacePaneWidth) + value.translation.width
                                workspacePaneWidth = Double(
                                    min(max(proposedWidth, workspaceMinWidth), maxWorkspaceWidth)
                                )
                            }
                    )

                InspectorView()
                    .frame(minWidth: inspectorMinWidth, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sidebarColumn: some View {
        ZStack(alignment: .trailing) {
            SidebarView()
                .frame(width: sidebarWidth, alignment: .leading)
                .frame(maxHeight: .infinity)
            Color(nsColor: .separatorColor)
                .frame(width: 1)
        }
        // Single, native-style motion: the content is always `sidebarWidth`
        // wide and pinned to the trailing edge of an outer frame that
        // animates 260→0. As the frame shrinks, the content's right edge
        // stays glued to the (leftward-moving) boundary and the left side
        // clips under the window edge — a clean left-slide, no compound
        // offset+clip "doubling".
        .frame(width: sidebarWidth, alignment: .trailing)
        .frame(width: isSidebarVisible ? sidebarWidth : 0, alignment: .trailing)
        .clipped()
        .background(Color(nsColor: .shipNotesSidebarBackground))
        .allowsHitTesting(isSidebarVisible)
        .accessibilityHidden(!isSidebarVisible)
        // NOTE: no implicit `.animation(value:)` here — it would animate only
        // this column, leaving the sibling Workspace/Inspector to snap into
        // the reclaimed space (the "half animates, half jumps" feel). We drive
        // the whole HStack relayout from `toggleSidebar()` via `withAnimation`.
    }

    private func toggleSidebar() {
        // Wrap the state change so the ENTIRE layout transition animates as
        // one transaction: the sidebar collapses AND Workspace/Inspector
        // slide left to fill, together, on the same curve.
        withAnimation(reduceMotion ? nil : sidebarAnimation) {
            isSidebarVisible.toggle()
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                toggleSidebar()
            } label: {
                Label(L("Toggle Sidebar"), systemImage: "sidebar.left")
            }
            .help(L("Show or hide the sidebar."))
            .keyboardShortcut("s", modifiers: [.command, .option])
        }

        ToolbarItem(placement: .principal) {
            Picker(
                "",
                selection: Binding(
                    get: { state.workspaceMode },
                    set: { state.workspaceMode = $0 }
                )
            ) {
                ForEach(WorkspaceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(minWidth: 360, idealWidth: 420, maxWidth: 460)
            .layoutPriority(1)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            switch state.workspaceMode {
            case .releaseNotes:
                ControlGroup {
                    Button {
                        state.presentImportPicker()
                    } label: {
                        Label(L("Import Folder"), systemImage: "folder.badge.plus")
                    }
                    .help(L("Import release notes (⌘⇧O)"))

                    Button {
                        state.toggleWatching()
                    } label: {
                        Label(
                            state.watching ? L("Watching") : L("Watch Folder"),
                            systemImage: state.watching ? "eye.fill" : "eye")
                    }
                    .disabled(state.sourceFolder == nil)
                    .help(L("Watch release-notes folder for changes"))
                }

                ControlGroup {
                    Button {
                        state.askAIToReparseCurrentReleaseNotes()
                    } label: {
                        Label(L("Ask AI to re-parse"), systemImage: "sparkles")
                    }
                    .disabled(!state.canReparseCurrentReleaseNotesWithAI)
                    .help(state.releaseNotesAIReparseHelp + " (⌘⇧R)")
                }

                Button {
                    showHistory = true
                } label: {
                    Label(L("Sync History"), systemImage: "clock.arrow.circlepath")
                }
                .help(L("Open sync history log"))

            case .storeCopy:
                // Import + AI Re-parse only: the locale-contextual actions
                // (AI Optimize, Sync Current/All) live in the workspace row
                // right above the editor — duplicating them here put the same
                // buttons on screen twice with drifting help text.
                ControlGroup {
                    Button {
                        state.presentStoreCopyImportPicker()
                    } label: {
                        Label(L("Import Store Copy"), systemImage: "folder.badge.plus")
                    }
                    .help(
                        L("Import store copy from a local Markdown, YAML, JSON, text file, or metadata folder (⌘⇧O)."))

                    Button {
                        state.askAIToReparseCurrentStoreCopy()
                    } label: {
                        Label(L("AI Re-parse"), systemImage: "sparkles")
                    }
                    .disabled(!state.canReparseCurrentStoreCopyWithAI)
                    .help(state.storeCopyAIReparseHelp + " (⌘⇧R)")
                }

            case .screenshots:
                ControlGroup {
                    Button {
                        state.presentScreenshotPicker()
                    } label: {
                        Label(L("Import Screenshots"), systemImage: "photo.on.rectangle.angled")
                    }
                    .help(L("Import screenshot folder (⌘⇧O)"))

                    Button {
                        if let folder = state.screenshotFolder {
                            state.loadScreenshotsFolder(folder)
                        }
                    } label: {
                        Label(L("Refresh Screenshots"), systemImage: "arrow.clockwise")
                    }
                    .disabled(state.screenshotFolder == nil)
                    .help(L("Refresh screenshot folder"))
                }

                ScreenshotAIMatchToolbarGroup()
                ScreenshotPreviewToolbarGroup()

            case .ads:
                Button {
                    state.refreshAppleAds()
                } label: {
                    Label(L("Refresh Ads"), systemImage: "arrow.clockwise")
                }
                .disabled(state.selectedAppId == nil || state.isLoadingAds)
                .help(L("Reload campaigns and reports for the selected app."))

                Button {
                    state.presentPromoteVersionSheet()
                } label: {
                    Label(L("Promote…"), systemImage: "megaphone")
                }
                .disabled(state.selectedAppId == nil)
                .help(L("Create a Search results campaign for this app."))
            }
        }
    }
}

// The toolbar and banners are split into their own views so each tracks only
// the state it reads. Inline in `ContentView.body`, every upload progress tick
// and every store-copy keystroke re-evaluated the whole window body, including
// the screenshot toolbar's coverage and AI-matching checks.

/// Banners use their own `.transition(...)` for show/hide motion. We
/// intentionally do NOT put a global `.animation(...)` modifier on this
/// VStack — that would inherit into descendants and the sidebar column toggle
/// would crawl through an easeInOut curve.
private struct TopBannerStack: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            if let activity = state.aiActivity {
                AIProgressBanner(activity: activity)
            }
            if let activity = state.screenshotUploadActivity {
                ScreenshotUploadBanner(activity: activity)
            }
            if let error = state.lastError {
                ErrorBanner(error: error) { state.dismissError() }
            }
        }
    }
}

private struct ScreenshotAIMatchToolbarGroup: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ControlGroup {
            Button {
                state.askAIToClassifyScreenshots()
            } label: {
                Label(L("AI Match"), systemImage: "sparkles")
            }
            .disabled(!state.canClassifyScreenshotsWithAI)
            .help(state.screenshotAIClassificationHelp)
        }
    }
}

private struct ScreenshotPreviewToolbarGroup: View {
    @Environment(AppState.self) private var state

    var body: some View {
        // One evaluation for both buttons; the workspace uses the same state.
        let controls = state.screenshotPreviewControlsState
        ControlGroup {
            Button {
                state.uploadSelectedScreenshotLocale()
            } label: {
                Label(L("Preview Selected"), systemImage: "eye")
            }
            .disabled(controls.selectedDisabledReason != nil)
            .help(controls.selectedDisabledReason ?? L("Preview screenshot replacements for selected locale."))

            Button {
                state.uploadAllScreenshots()
            } label: {
                Label(L("Preview All"), systemImage: "eye.fill")
            }
            .disabled(controls.allDisabledReason != nil)
            .help(controls.allDisabledReason ?? L("Preview screenshot replacements for all ready locales."))
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState.preview)
        .frame(width: 1200, height: 760)
}
