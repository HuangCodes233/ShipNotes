import Foundation
import Observation
import Testing
@testable import ShipNotes

/// Long-running AI work and background reloads must not discard what the
/// user is typing or looking at.
@Suite("Edit preservation")
@MainActor
struct EditPreservationTests {
    private func makeState(ai: MockAIService) -> AppState {
        let state = AppState(
            aiKeychainStore: InMemoryAIKeychainStore(),
            aiService: ai,
            defaults: makeTestDefaults()
        )
        state.bootstrapWithMockData()
        return state
    }

    @Test func translationIsNotAppliedOverTextTypedWhileItRan() async {
        let ai = MockAIService()
        ai.translateDelayNanoseconds = 200_000_000
        let state = makeState(ai: ai)
        guard state.localeNotes.count >= 2 else { Issue.record("Sample data needs two locales"); return }
        let source = state.localeNotes[0].locale
        let target = state.localeNotes[1].locale
        state.updateLocalText(for: source, text: "Source notes")

        state.translateLocale(target, fromLocale: source)
        #expect(await waitUntil { state.isAIRunning })
        state.updateLocalText(for: target, text: "Typed by the user")
        #expect(await waitUntil { !state.isAIRunning })

        #expect(state.localeNotes.first { $0.locale == target }?.localText == "Typed by the user")
        #expect(state.lastError?.message == expectedLocalized(
            "%@ was edited while AI was translating, so the translation was not applied.", target
        ))
    }

    @Test func bulkTranslationSkipsLocalesFilledWhileItRan() async {
        let ai = MockAIService()
        ai.translateDelayNanoseconds = 150_000_000
        let state = makeState(ai: ai)
        guard state.localeNotes.count >= 3 else { Issue.record("Sample data needs three locales"); return }
        let source = state.localeNotes[0].locale
        let first = state.localeNotes[1].locale
        let second = state.localeNotes[2].locale
        state.updateLocalText(for: source, text: "Source notes")
        state.updateLocalText(for: first, text: "")
        state.updateLocalText(for: second, text: "")

        state.translateAllEmptyLocales(from: source)
        #expect(await waitUntil { state.isAIRunning })
        state.updateLocalText(for: second, text: "Filled by hand")
        #expect(await waitUntil { !state.isAIRunning })

        #expect(state.localeNotes.first { $0.locale == first }?.localText == "MOCK TRANSLATION")
        #expect(state.localeNotes.first { $0.locale == second }?.localText == "Filled by hand")
    }

    @Test func optimizationKeepsFieldsEditedWhileItRan() async {
        let ai = MockAIService()
        ai.optimizeDelayNanoseconds = 200_000_000
        let state = makeState(ai: ai)
        guard let locale = state.storeCopyLocales.first?.locale else { Issue.record("Sample data needs store copy"); return }

        state.optimizeStoreCopyLocale(locale)
        #expect(await waitUntil { state.isAIRunning })
        state.updateStoreCopyField(for: locale, field: .description, text: "My own description")
        #expect(await waitUntil { !state.isAIRunning })

        let metadata = state.storeCopyLocales.first { $0.locale == locale }?.localMetadata
        #expect(metadata?.description == "My own description")
        #expect(metadata?.keywords == "optimized,keywords")
    }

    @Test func reloadingNotesKeepsTheSelectedLocale() {
        let state = makeState(ai: MockAIService())
        guard let second = state.localeNotes.dropFirst().first?.locale else { Issue.record("Sample data needs two locales"); return }
        state.selectLocale(second)

        state.loadMockNotesForCurrentVersion()

        #expect(state.selectedLocale == second)
    }

    @Test func savingAnAIKeyUpdatesViewsReadingIsAIConfigured() {
        let state = AppState(aiKeychainStore: InMemoryAIKeychainStore(), defaults: makeTestDefaults())
        final class Flag: @unchecked Sendable {
            private let lock = NSLock()
            private var raised = false
            var isRaised: Bool { lock.withLock { raised } }
            func raise() { lock.withLock { raised = true } }
        }
        let changed = Flag()
        withObservationTracking {
            _ = state.isAIConfigured
        } onChange: {
            changed.raise()
        }

        state.aiService = MockAIService()

        #expect(changed.isRaised)
        #expect(state.isAIConfigured)
    }

    @Test func keywordEditsDoNotGrowTheField() {
        let packed = "alpha,beta,gamma,delta"
        #expect(KeywordList.removing(at: 1, from: packed) == "alpha,gamma,delta")
        // Spaced input is compacted rather than expanded.
        #expect(KeywordList.removing(at: 0, from: "alpha, beta, gamma") == "beta,gamma")
        // Only the chosen copy of a repeated keyword goes.
        #expect(KeywordList.removing(at: 2, from: "a,b,a") == "a,b")
        #expect(KeywordList.adding("Beta, epsilon", to: packed) == "alpha,beta,gamma,delta,epsilon")
        #expect(KeywordList.adding("  ", to: packed) == nil)
    }
}
