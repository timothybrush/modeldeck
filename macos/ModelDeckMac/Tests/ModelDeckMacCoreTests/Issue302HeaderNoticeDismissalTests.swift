import Foundation
import Testing
@testable import ModelDeckMacCore

// Issue #302 — header info-space notices are dismissible, and dismissal
// persists. Tim: "anything that gets put into that space, I would like it
// to be dismissible. We don't need the extra noise again." Per-KIND
// dismissal (DeckHeaderNotice), stored in app-local UserDefaults like every
// other popover view preference (the #73 pattern).

@Suite("Header notice dismissal (issue #302)")
@MainActor
struct HeaderNoticeDismissalTests {
    private func freshStore() -> UserDefaults {
        ScratchDefaults.make("issue302")
    }

    private func model(store: UserDefaults) -> DeckPopoverModel {
        DeckPopoverModel(defaults: store)
    }

    @Test func nothingIsDismissedByDefault() {
        let model = model(store: freshStore())
        for notice in DeckPopoverModel.DeckHeaderNotice.allCases {
            #expect(!model.isHeaderNoticeDismissed(notice))
        }
    }

    @Test func dismissingHidesTheNotice() {
        let model = model(store: freshStore())
        model.dismissHeaderNotice(.menuBarSource)
        #expect(model.isHeaderNoticeDismissed(.menuBarSource))
    }

    @Test func dismissalPersistsAcrossModelInstances() {
        let store = freshStore()
        model(store: store).dismissHeaderNotice(.menuBarSource)
        // A fresh model over the same store — the app-relaunch shape.
        #expect(model(store: store).isHeaderNoticeDismissed(.menuBarSource))
    }

    @Test func dismissingTwiceIsIdempotent() {
        let store = freshStore()
        let model = model(store: store)
        model.dismissHeaderNotice(.menuBarSource)
        model.dismissHeaderNotice(.menuBarSource)
        let stored = store
            .stringArray(forKey: DeckPopoverModel.dismissedHeaderNoticesDefaultsKey)
        #expect(stored == ["menuBarSource"])
    }

    @Test func unrecognizedStoredKindsAreDroppedNotResurrected() {
        // A downgrade or hand-edited plist: unknown raw values must neither
        // crash the load nor surface as some other notice's dismissal.
        let store = freshStore()
        store.set(
            ["menuBarSource", "someFutureNotice"],
            forKey: DeckPopoverModel.dismissedHeaderNoticesDefaultsKey
        )
        let model = model(store: store)
        #expect(model.isHeaderNoticeDismissed(.menuBarSource))
        #expect(model.dismissedHeaderNotices.count == 1)
    }

    @Test func rawValuesAreThePersistenceContract() {
        // Renaming a case's raw value would silently resurrect every
        // dismissed notice on upgrade — pin the format.
        #expect(DeckPopoverModel.DeckHeaderNotice.menuBarSource.rawValue == "menuBarSource")
    }
}
