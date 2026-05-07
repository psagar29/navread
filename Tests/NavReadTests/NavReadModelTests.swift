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

@Test func aiAttachmentPromptTruncatesReadableText() {
    let attachment = AIAttachment(
        kind: .pdf,
        name: "notes.pdf",
        extractedText: String(repeating: "a", count: 32),
        sourceURL: "/tmp/notes.pdf",
        assetPath: nil,
        captureID: nil,
        createdAt: .now
    )

    let prompt = attachment.promptDescription(maxCharacters: 12)

    #expect(prompt.contains("notes.pdf"))
    #expect(prompt.contains("PDF"))
    #expect(prompt.contains(String(repeating: "a", count: 12)))
    #expect(!prompt.contains(String(repeating: "a", count: 13)))
}

@Test func aiAttachmentPolicyCapsSingleTurnUploads() {
    #expect(AIAttachmentPolicy.maxItems == 5)
}
