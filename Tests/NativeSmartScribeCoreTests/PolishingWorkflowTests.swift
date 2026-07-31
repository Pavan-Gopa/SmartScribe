import Foundation
import NativeSmartScribeCore
import Testing

@MainActor
@Test
func polishingWorkflowStoresBothPolishedVariants() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "hello from the raw transcript.",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let workflow = PolishingWorkflow(
        noteStore: store,
        engine: SuccessfulPolishingEngine()
    )

    await workflow.polishNote(note.id)

    let updated = store.selectedNote
    #expect(updated?.polishedVariantOne == "Variant 1: hello from the raw transcript.")
    #expect(updated?.polishedVariantTwo == "Variant 2: hello from the raw transcript.")
    #expect(updated?.polishingStatus(for: .variantOne).phase == .completed)
    #expect(updated?.polishingStatus(for: .variantTwo).phase == .completed)
    #expect(updated?.polishingStatus(for: .variantOne).backendName == "Successful Polish Engine")
}

@MainActor
@Test
func polishingWorkflowUsesCustomPromptTemplateProvider() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "raw english text",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let workflow = PolishingWorkflow(
        noteStore: store,
        engine: RenderingPolishingEngine(),
        templateProvider: { variant in
            PromptTemplate(
                id: "\(variant.id)-custom",
                title: "Custom \(variant.title)",
                body: "CUSTOM \(variant.title): \(PromptTemplate.transcriptionPlaceholder)"
            )
        }
    )

    await workflow.polishNote(note.id, variants: [.variantOne])

    #expect(store.selectedNote?.polishedVariantOne == "CUSTOM Variant 1: raw english text")
}

@MainActor
@Test
func polishingWorkflowRetriesVariantTwoWhenRussianSourceReturnsEnglishOutput() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "это русский исходный текст про API и prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = LanguageRetryPolishingEngine()
    let workflow = PolishingWorkflow(
        noteStore: store,
        engine: engine
    )

    await workflow.polishNote(note.id, variants: [.variantTwo])

    #expect(store.selectedNote?.polishedVariantTwo == "Это русский исходный текст про API и prompt template.")
    #expect(await engine.callCount == 2)
}

@MainActor
@Test
func polishingWorkflowMarksFailureWhenEngineThrows() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "raw transcript",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let workflow = PolishingWorkflow(
        noteStore: store,
        engine: FailingPolishingEngine()
    )

    await workflow.polishNote(note.id, variants: [.variantOne])

    #expect(store.selectedNote?.polishedVariantOne == "")
    #expect(store.selectedNote?.polishingStatus(for: .variantOne).phase == .failed)
    #expect(store.selectedNote?.polishingStatus(for: .variantOne).message == "Polishing failed in test.")
}

@MainActor
@Test
func polishingWorkflowMarksFailureWhenEngineReturnsEmptyText() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "raw transcript",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let workflow = PolishingWorkflow(
        noteStore: store,
        engine: EmptyPolishingEngine()
    )

    await workflow.polishNote(note.id, variants: [.variantOne])

    #expect(store.selectedNote?.polishedVariantOne == "")
    #expect(store.selectedNote?.polishingStatus(for: .variantOne).phase == .failed)
    #expect(
        store.selectedNote?.polishingStatus(for: .variantOne).message
            == AppText.localized(.emptyPolishingResult, language: .english)
    )
}

@MainActor
@Test
func polishingWorkflowMarksFailureWhenRawTextIsEmpty() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    let workflow = PolishingWorkflow(
        noteStore: store,
        engine: SuccessfulPolishingEngine()
    )

    await workflow.polishNote(note.id, variants: [.variantOne])

    #expect(store.selectedNote?.polishingStatus(for: .variantOne).phase == .failed)
    #expect(
        store.selectedNote?.polishingStatus(for: .variantOne).message
            == AppText.localized(.noTranscriptToPolish, language: .english)
    )
}

private struct SuccessfulPolishingEngine: PolishingEngine {
    let id = "successful-polish-engine"
    let displayName = "Successful Polish Engine"

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        let rendered = try request.template.render(transcription: request.rawText)
        #expect(rendered.contains(request.rawText))

        return PolishingResult(
            text: "\(request.variant.title): \(request.rawText)",
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

private struct RenderingPolishingEngine: PolishingEngine {
    let id = "rendering-polish-engine"
    let displayName = "Rendering Polish Engine"

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        let rendered = try request.template.render(transcription: request.rawText)
        return PolishingResult(
            text: rendered,
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

private struct FailingPolishingEngine: PolishingEngine {
    let id = "failing-polish-engine"
    let displayName = "Failing Polish Engine"

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        throw TestPolishingError()
    }
}

private struct EmptyPolishingEngine: PolishingEngine {
    let id = "empty-polish-engine"
    let displayName = "Empty Polish Engine"

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        PolishingResult(
            text: "   ",
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

private actor LanguageRetryPolishingEngine: PolishingEngine {
    nonisolated let id = "language-retry-engine"
    nonisolated let displayName = "Language Retry Engine"

    private(set) var callCount = 0

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        callCount += 1
        let body = request.template.body
        let text: String
        if body.contains("CRITICAL LANGUAGE LOCK") {
            text = "Это русский исходный текст про API и prompt template."
        } else {
            text = "This is an English rewrite about API and prompt template."
        }

        return PolishingResult(
            text: text,
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

private struct TestPolishingError: LocalizedError, Sendable {
    var errorDescription: String? {
        "Polishing failed in test."
    }
}

@MainActor
@Test
func polishingWorkflowInjectsTranslationOverrideWhenTargetLanguageSet() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "это русский исходный текст про API и prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = PromptCapturingPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    await workflow.polishNote(note.id, variants: [.variantOne], targetLanguage: "es")

    let body = await engine.lastTemplateBody ?? ""
    // An authoritative translation override names the target language.
    #expect(body.contains("TRANSLATION OVERRIDE"))
    #expect(body.contains("into Spanish"))
    // The override explicitly suspends the templates' "never translate" rules...
    #expect(body.contains("OVERRIDES and SUSPENDS"))
    // ...and the real default template's anti-translation clause is still present,
    // now superseded by the override.
    #expect(body.contains("Never translate"))
    // The template's polishing style is preserved alongside the override.
    #expect(body.contains("precision transcription editor"))
    // A final reminder is appended after the template body to counter recency.
    #expect(body.contains("FINAL TRANSLATION REMINDER"))
    // The translation override must supersede the Cyrillic source-language lock.
    #expect(!body.contains("LANGUAGE LOCK"))
    // The transcription placeholder must still be rendered away.
    #expect(!body.contains("${transcription}"))
}

@MainActor
@Test
func polishingWorkflowKeepsCyrillicLockWhenNoTargetLanguage() async {
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "это русский исходный текст про API и prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = PromptCapturingPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    await workflow.polishNote(note.id, variants: [.variantOne])

    let body = await engine.lastTemplateBody ?? ""
    #expect(body.contains("LANGUAGE LOCK"))
    #expect(!body.contains("TRANSLATION OVERRIDE"))
}

@MainActor
@Test
func polishingWorkflowTranslatesEnglishTargetWithoutCyrillicLock() async {
    // Behavior change: an explicit English target now produces a translation
    // override even for Cyrillic source (previously English targets were a
    // no-op that merely skipped the Cyrillic lock).
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "это русский исходный текст про API и prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = PromptCapturingPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    await workflow.polishNote(note.id, variants: [.variantOne], targetLanguage: "en")

    let body = await engine.lastTemplateBody ?? ""
    #expect(body.contains("TRANSLATION OVERRIDE"))
    #expect(body.contains("into English"))
    #expect(!body.contains("LANGUAGE LOCK"))
}

@MainActor
@Test
func polishingWorkflowTranslatesNonCyrillicSourceWhenTargetSet() async {
    // A non-Cyrillic source would normally yield no language guard at all, but
    // an explicit target language must still inject the translation override.
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "this is a plain english transcript about an API and a prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = PromptCapturingPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    await workflow.polishNote(note.id, variants: [.variantOne], targetLanguage: "fr")

    let body = await engine.lastTemplateBody ?? ""
    #expect(body.contains("TRANSLATION OVERRIDE"))
    #expect(body.contains("into French"))
    #expect(body.contains("FINAL TRANSLATION REMINDER"))
}

@MainActor
@Test
func polishingWorkflowIgnoresBlankTargetLanguageAndKeepsCyrillicLock() async {
    // A whitespace-only target language normalizes to empty and must be treated
    // as "no translation requested", preserving the Cyrillic source lock.
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "это русский исходный текст про API и prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = PromptCapturingPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    await workflow.polishNote(note.id, variants: [.variantOne], targetLanguage: "   ")

    let body = await engine.lastTemplateBody ?? ""
    #expect(body.contains("LANGUAGE LOCK"))
    #expect(!body.contains("TRANSLATION OVERRIDE"))
}

@MainActor
@Test
func polishingWorkflowDoesNotStrictRetryWhileTranslating() async {
    // When translating, the polished output is expected to be in the target
    // (non-Cyrillic) language, so the Cyrillic-drift strict retry must never
    // trigger even if the engine returns Latin-only text.
    let store = NoteStore()
    let note = store.addEmptyNote()
    store.applyTranscriptionResult(
        for: note.id,
        result: TranscriptionResult(
            text: "это русский исходный текст про API и prompt template",
            diagnostics: EngineDiagnostics(backendName: "Test Transcriber")
        )
    )
    let engine = CountingEnglishPolishingEngine()
    let workflow = PolishingWorkflow(noteStore: store, engine: engine)

    await workflow.polishNote(note.id, variants: [.variantOne], targetLanguage: "es")

    #expect(await engine.callCount == 1, "translation must suppress the strict Cyrillic retry")
}

private actor CountingEnglishPolishingEngine: PolishingEngine {
    nonisolated let id = "counting-english-polish-engine"
    nonisolated let displayName = "Counting English Polish Engine"

    private(set) var callCount = 0

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        callCount += 1
        return PolishingResult(
            text: "This is an English translation about an API and a prompt template.",
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}

private actor PromptCapturingPolishingEngine: PolishingEngine {
    nonisolated let id = "prompt-capturing-polish-engine"
    nonisolated let displayName = "Prompt Capturing Polish Engine"

    private(set) var lastTemplateBody: String?

    func polish(_ request: PolishingRequest) async throws -> PolishingResult {
        lastTemplateBody = try request.template.render(transcription: request.rawText)
        return PolishingResult(
            text: request.rawText,
            diagnostics: EngineDiagnostics(backendName: displayName)
        )
    }
}
