import Foundation
import Testing
@testable import NavRead

@Test func quotePrefersCleanedText() {
    let quote = Quote(
        id: UUID(),
        bookID: UUID(),
        chapterID: nil,
        rawText: " raw OCR text ",
        cleanedText: "Clean quote text.",
        pageLocator: "p. 42",
        note: "",
        tags: ["clarity"],
        sourceType: .manual,
        sourceURL: "",
        captureID: nil,
        createdAt: .now,
        updatedAt: .now
    )

    #expect(quote.text == "Clean quote text.")
}

@Test func emptyAuthorUsesFallbackLabel() {
    var book = Book.sample
    book.author = ""

    #expect(book.displayAuthor == "Unknown author")
}

@Test func onboardingShowsOnlyForFreshInstall() {
    let state = FirstRunOnboardingGate.resolve(
        hasCompleted: false,
        hasStarted: false,
        libraryExistedBeforeSetup: false
    )

    #expect(state == FirstRunOnboardingState(hasCompleted: false, hasStarted: true, shouldPresent: true))
}

@Test func onboardingDoesNotShowForExistingLibrary() {
    let state = FirstRunOnboardingGate.resolve(
        hasCompleted: false,
        hasStarted: false,
        libraryExistedBeforeSetup: true
    )

    #expect(state == FirstRunOnboardingState(hasCompleted: true, hasStarted: false, shouldPresent: false))
}

@Test func onboardingResumesAfterPartialSetup() {
    let state = FirstRunOnboardingGate.resolve(
        hasCompleted: false,
        hasStarted: true,
        libraryExistedBeforeSetup: true
    )

    #expect(state == FirstRunOnboardingState(hasCompleted: false, hasStarted: true, shouldPresent: true))
}
