import Foundation

@MainActor
public final class PolishingWorkflow {
    private let noteStore: NoteStore
    private let engine: any PolishingEngine
    private let templateProvider: (ProcessingVariant) -> PromptTemplate
    private let messageProvider: (AppTextKey) -> String

    public init(
        noteStore: NoteStore,
        engine: any PolishingEngine,
        templateProvider: @escaping (ProcessingVariant) -> PromptTemplate = {
            .defaultTemplate(for: $0)
        },
        messageProvider: @escaping (AppTextKey) -> String = {
            AppText.localized($0, language: .english)
        }
    ) {
        self.noteStore = noteStore
        self.engine = engine
        self.templateProvider = templateProvider
        self.messageProvider = messageProvider
    }

    @discardableResult
    public func polishNote(
        _ noteID: SmartScribeNote.ID,
        variants: [ProcessingVariant] = [.variantOne, .variantTwo],
        targetLanguage: String? = nil
    ) async -> [ProcessingVariant: PolishingResult] {
        var results: [ProcessingVariant: PolishingResult] = [:]
        guard let note = noteStore.note(withID: noteID) else { return results }
        let rawText = note.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let languageGuard = PolishingLanguageGuard(sourceText: rawText, targetLanguage: targetLanguage)

        guard !rawText.isEmpty else {
            for variant in variants.polishableVariants {
                noteStore.markPolishingFailed(
                    for: noteID,
                    variant: variant,
                    message: messageProvider(.noTranscriptToPolish),
                    backendName: engine.displayName
                )
            }
            return results
        }

        for variant in variants.polishableVariants {
            noteStore.markPolishingStarted(
                for: noteID,
                variant: variant,
                backendName: engine.displayName
            )

            do {
                let result = try await polishWithLanguageGuard(
                    rawText: rawText,
                    variant: variant,
                    template: templateProvider(variant),
                    languageGuard: languageGuard
                )
                guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    noteStore.markPolishingFailed(
                        for: noteID,
                        variant: variant,
                        message: messageProvider(.emptyPolishingResult),
                        backendName: result.diagnostics.backendName
                    )
                    continue
                }
                noteStore.applyPolishingResult(for: noteID, variant: variant, result: result)
                results[variant] = result
            } catch {
                noteStore.markPolishingFailed(
                    for: noteID,
                    variant: variant,
                    message: error.localizedDescription,
                    backendName: engine.displayName
                )
            }
        }
        return results
    }

    private func polishWithLanguageGuard(
        rawText: String,
        variant: ProcessingVariant,
        template: PromptTemplate,
        languageGuard: PolishingLanguageGuard?
    ) async throws -> PolishingResult {
        let guardedTemplate = languageGuard?.applying(to: template, strict: false) ?? template
        var result = try await engine.polish(
            PolishingRequest(
                rawText: rawText,
                variant: variant,
                template: guardedTemplate
            )
        )

        guard let languageGuard, languageGuard.requiresStrictRetry(for: result.text) else {
            return result
        }

        let strictTemplate = languageGuard.applying(to: template, strict: true)
        result = try await engine.polish(
            PolishingRequest(
                rawText: rawText,
                variant: variant,
                template: strictTemplate
            )
        )
        return result
    }
}

private extension Array where Element == ProcessingVariant {
    var polishableVariants: [ProcessingVariant] {
        filter { $0 != .raw }
    }
}

private struct PolishingLanguageGuard {
    private let sourceIsCyrillicDominant: Bool
    private let translationInstruction: String?
    private let translationFooter: String?

    init?(sourceText: String, targetLanguage: String? = nil) {
        let normalizedTarget = targetLanguage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Explicit translation request (HUD "A" → target language): instruct the
        // polishing model to translate the output into the target language. This
        // supersedes any source-language lock so that, e.g., Russian speech can be
        // rendered as Spanish/English/etc. text by the polishing model. The raw
        // transcription itself is left untouched upstream; only the polished
        // variant is translated.
        if let normalizedTarget, !normalizedTarget.isEmpty {
            let languageName = TranscriptionLanguageOption.displayName(for: normalizedTarget)
            translationInstruction = """
            === TRANSLATION OVERRIDE - READ THIS FIRST, HIGHEST PRIORITY ===
            For THIS task you MUST translate the ENTIRE text into \(languageName).
            This requirement OVERRIDES and SUSPENDS every other language rule in this prompt. Ignore any instruction below that says to keep, preserve, or not change the input language, to "never translate", to "not translate the text", to output in the same language as the input, or to confirm that the output matches the input language. Those rules DO NOT apply to this task.
            Still follow the cleaning, editing, and formatting rules below, but write the final result entirely in \(languageName).
            Preserve embedded technical terms, product and company names, APIs, commands, code fragments, file paths, UI labels, and abbreviations exactly where appropriate; the surrounding prose MUST be in \(languageName).
            Return ONLY the final text. Do not mention this override or the translation.
            === END OVERRIDE ===
            """
            translationFooter = """
            === FINAL TRANSLATION REMINDER ===
            Return the text above entirely in \(languageName). Ignore any earlier instruction that says to keep the original language or not to translate. Output ONLY the final polished text in \(languageName) - no explanations, no notes, no source-language text.
            """
            sourceIsCyrillicDominant = false
            return
        }

        // No translation requested: keep the output in the source language. When the
        // source is primarily Russian/Cyrillic, lock the output to Cyrillic so the
        // polishing model does not drift into English.
        let sourceProfile = ScriptProfile(text: sourceText)
        guard sourceProfile.isCyrillicDominant else {
            return nil
        }

        sourceIsCyrillicDominant = true
        translationInstruction = nil
        translationFooter = nil
    }

    func applying(to template: PromptTemplate, strict: Bool) -> PromptTemplate {
        if let translationInstruction {
            var body = "\(translationInstruction)\n\n\(template.body)"
            if let translationFooter {
                body += "\n\n\(translationFooter)"
            }
            return PromptTemplate(
                id: template.id,
                title: template.title,
                body: body
            )
        }

        guard sourceIsCyrillicDominant else {
            return template
        }

        let instruction: String
        if strict {
            instruction = """
            CRITICAL LANGUAGE LOCK:
            - The source text is primarily Russian written in Cyrillic.
            - Your output MUST remain primarily Russian written in Cyrillic.
            - If you answer mostly in English or another non-Cyrillic language, the answer is wrong.
            - Preserve embedded English technical terms, product names, APIs, commands, code fragments, file paths, UI labels, and abbreviations exactly where appropriate.
            """
        } else {
            instruction = """
            LANGUAGE LOCK:
            - The source text is primarily Russian written in Cyrillic.
            - Keep the output primarily in Russian written in Cyrillic.
            - Preserve embedded English technical terms, product names, APIs, commands, code fragments, file paths, UI labels, and abbreviations exactly where appropriate.
            """
        }

        return PromptTemplate(
            id: template.id,
            title: template.title,
            body: """
            \(instruction)

            \(template.body)
            """
        )
    }

    func requiresStrictRetry(for outputText: String) -> Bool {
        // When translating, the output is expected to be in the target language, so
        // the Cyrillic-drift retry must never trigger.
        guard translationInstruction == nil else { return false }
        let outputProfile = ScriptProfile(text: outputText)
        return sourceIsCyrillicDominant && outputProfile.isClearlyNonCyrillicComparedToCyrillicSource
    }
}

private struct ScriptProfile {
    let cyrillicCount: Int
    let latinCount: Int

    init(text: String) {
        var cyrillicCount = 0
        var latinCount = 0

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0041...0x005A, 0x0061...0x007A:
                latinCount += 1
            case 0x0400...0x04FF, 0x0500...0x052F, 0x2DE0...0x2DFF, 0xA640...0xA69F:
                cyrillicCount += 1
            default:
                continue
            }
        }

        self.cyrillicCount = cyrillicCount
        self.latinCount = latinCount
    }

    var isCyrillicDominant: Bool {
        cyrillicCount >= 8 && cyrillicCount > latinCount
    }

    var isClearlyNonCyrillicComparedToCyrillicSource: Bool {
        latinCount >= 12 && cyrillicCount * 2 < latinCount
    }
}
