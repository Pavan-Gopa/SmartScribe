import AppKit
import ApplicationServices
import Carbon
import NativeSmartScribeCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ContentView: View {
    private enum Layout {
        static let minimumSidebarWidth = SidebarLayoutMetrics.minimumWidth
        static let idealSidebarWidth = SidebarLayoutMetrics.idealWidth
    }

    @StateObject private var noteStore = NoteStore.live()
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var translationAudioRecorder = AudioRecorder()
    @EnvironmentObject private var polishingEngineStore: PolishingEngineStore
    @EnvironmentObject private var promptTemplateStore: PromptTemplateStore
    @EnvironmentObject private var transcriptionModelStore: TranscriptionModelStore
    @EnvironmentObject private var transcriptionEngineStore: TranscriptionEngineStore
    @EnvironmentObject private var hotkeySettingsStore: HotkeySettingsStore
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var usageStatisticsStore: UsageStatisticsStore
    @EnvironmentObject private var glossaryStore: GlossaryStore
    @EnvironmentObject private var accessibilityPermissionStore: AccessibilityPermissionStore
    @State private var selectedVariant: ProcessingVariant = .raw
    @State private var selectedNoteText = ""
    @State private var isShowingTranslation = false
    @State private var isShowingOnboarding = false
    @State private var translationOriginalText = ""
    @State private var translationTranslatedText = ""
    @AppStorage("translation.targetLanguage") private var translationTargetLanguage = "English"
    @AppStorage("translation.providerID") private var translationProviderID = ""
    @State private var pendingHotkeyTarget: HotkeyTarget?
    @State private var pendingHotkeyOutputMode: HotkeyOutputMode?
    @State private var pendingHotkeySourcePID: pid_t?
    @State private var pendingHotkeyFocusedElement: AXUIElement?
    @State private var settingsWindow: NSWindow?
    @State private var lastSettingsToggleTime: Date = .distantPast
    @State private var isTogglingHotkeyRecording = false
    @State private var hotkeyOwnerID = UUID()
    @State private var hotkeySessionOverlayManager = HotkeySessionOverlayManager()
    @State private var providerQuickSwitcher = ProviderQuickSwitcher()
    @State private var pendingHotkeyForceTargetLanguage = false
    @AppStorage("hud.forceTargetLanguage") private var persistentHUDForceTargetLanguage = false

    var body: some View {
        GeometryReader { proxy in
            NavigationSplitView {
                SidebarView(noteStore: noteStore)
                    .navigationSplitViewColumnWidth(
                        min: Layout.minimumSidebarWidth,
                        ideal: Layout.idealSidebarWidth,
                        max: SidebarLayoutMetrics.maximumWidth(forWindowWidth: proxy.size.width)
                    )
            } detail: {
                NoteDetailView(
                    note: noteStore.selectedNote,
                    selectedVariant: $selectedVariant,
                    selectedText: $selectedNoteText,
                    audioRecorder: audioRecorder,
                    onRecordingCompleted: transcribeRecording,
                    onPolishRequested: polishNote,
                    onMarkdownRequested: generateMarkdown,
                    onTextChanged: updateText,
                    onAudioFileImportRequested: importAudioFile,
                    onBlankNoteRequested: createBlankNote,
                    onTranslateRequested: openTranslationModal
                )
            }
            .navigationSplitViewStyle(.balanced)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(UIScaleModifier())
            .onDrop(
                of: [
                    UTType.fileURL.identifier,
                    UTType.audio.identifier,
                    UTType.movie.identifier
                ],
                isTargeted: nil,
                perform: handleAudioFileDrop
            )
            .sheet(isPresented: $isShowingTranslation) {
                TranslationModalView(
                    audioRecorder: translationAudioRecorder,
                    providerID: $translationProviderID,
                    targetLanguage: $translationTargetLanguage,
                    originalText: $translationOriginalText,
                    translatedText: $translationTranslatedText,
                    onTranslate: translateText,
                    onRecordingCompleted: transcribeForTranslation
                )
                .environmentObject(generalSettingsStore)
                .environmentObject(polishingEngineStore)
                .environmentObject(glossaryStore)
            }
            .sheet(isPresented: $isShowingOnboarding) {
                OnboardingView(
                    accessibility: accessibilityPermissionStore,
                    audioRecorder: audioRecorder
                )
                    .environmentObject(generalSettingsStore)
                    .environmentObject(glossaryStore)
                    .environmentObject(transcriptionModelStore)
                    .environmentObject(polishingEngineStore)
                    .environmentObject(hotkeySettingsStore)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
                isShowingOnboarding = true
            }
            .onAppear {
                syncLocalizedServices()
                isShowingOnboarding = !generalSettingsStore.settings.hasCompletedOnboarding
                configureProviderQuickSwitcher()
            }
            .onChange(of: generalSettingsStore.settings.uiLanguage) { _, _ in
                syncLocalizedServices()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nativeSmartScribeHotkeyTriggered)) { _ in
                handleHotkeyTriggered()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nativeSmartScribeTargetHotkeyTriggered)) { _ in
                openFloatingTranslationWindow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nativeSmartScribeQuickTranslationHotkeyTriggered)) { _ in
                openQuickTranslationWindow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nativeSmartScribeSettingsHotkeyTriggered)) { _ in
                toggleSettingsWindow()
            }
            .onReceive(audioRecorder.$frequencyBands) { bands in
                guard audioRecorder.isRecording else { return }
                hotkeySessionOverlayManager.update(spectrumBands: bands)
            }
            .onChange(of: generalSettingsStore.settings.overlay) { _, overlaySettings in
                hotkeySessionOverlayManager.update(settings: overlaySettings)
            }
            .onChange(of: noteStore.selection) { _, _ in
                selectedNoteText = ""
            }
            .onChange(of: selectedVariant) { _, _ in
                selectedNoteText = ""
            }
        }
        .frame(minWidth: 840, minHeight: 580)
    }


    private func transcribeRecording(_ recording: AudioRecording) {
        // Respect the HUD A/E toggle (auto vs. forced target language) exactly like the
        // hotkey path does. Without this, HUD-button recordings always ran in "auto"
        // mode and Gemini kept whatever language it heard, ignoring the E (target)
        // setting — e.g. returning Russian text even when E1 was selected.
        transcribeRecording(
            recording,
            hotkeyTarget: nil,
            outputMode: nil,
            forceTargetLanguage: effectiveHUDForceTargetLanguage
        )
    }

    private func updateRawText(noteID: SmartScribeNote.ID, text: String) {
        noteStore.updateRawText(for: noteID, text: text)
    }

    private func updateText(
        noteID: SmartScribeNote.ID,
        variant: ProcessingVariant,
        text: String
    ) {
        noteStore.updateText(for: noteID, variant: variant, text: text)
    }

    private func createBlankNote() {
        _ = noteStore.addEmptyNote(title: generalSettingsStore.text(.untitledNote))
        selectedVariant = .raw
        selectedNoteText = ""
    }

    private func importAudioFile(_ url: URL) {
        Task { @MainActor in
            do {
                let recording = try AudioFileImporter.recording(from: url)
                transcribeRecording(recording)
            } catch {
                NativeSmartScribeLog.transcription.error("Audio file import failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleAudioFileDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        url = item as? URL
                    }

                    guard let url else { return }
                    Task { @MainActor in
                        importAudioFile(url)
                    }
                }
                return true
            }

            let supportedType = [UTType.audio, .movie].first {
                provider.hasItemConformingToTypeIdentifier($0.identifier)
            }

            if let supportedType {
                provider.loadFileRepresentation(forTypeIdentifier: supportedType.identifier) { url, _ in
                    guard let url else { return }
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension)
                    do {
                        if FileManager.default.fileExists(atPath: destination.path) {
                            try FileManager.default.removeItem(at: destination)
                        }
                        try FileManager.default.copyItem(at: url, to: destination)
                        Task { @MainActor in
                            importAudioFile(destination)
                        }
                    } catch {
                        NativeSmartScribeLog.transcription.error("Audio drop copy failed: \(error.localizedDescription)")
                    }
                }
                return true
            }
        }

        if providers.isEmpty {
            return true
        }

        return false
    }

    private func openTranslationModal() {
        let selected = selectedNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipboard = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = selected.isEmpty ? clipboard : selected

        translationOriginalText = source
        translationTranslatedText = source.isEmpty ? generalSettingsStore.text(.noTextToTranslate) : ""
        // Provider validation happens inside TranslationModalView.onAppear
        isShowingTranslation = true

        guard !source.isEmpty else { return }
        guard !translationProviderID.isEmpty else {
            translationTranslatedText = generalSettingsStore.text(.noTranslationProvider)
            return
        }
        Task { @MainActor in
            translationTranslatedText = generalSettingsStore.text(.translating)
            do {
                let result = try await translateText(
                    text: source,
                    targetLanguage: translationTargetLanguage,
                    providerID: translationProviderID
                )
                translationTranslatedText = result.text
            } catch {
                translationTranslatedText = error.localizedDescription
            }
        }
    }

    private func openFloatingTranslationWindow() {
        // Toggle: if already visible, close it
        if FloatingTranslationWindowManager.shared.isVisible {
            FloatingTranslationWindowManager.shared.close()
            return
        }

        Task { @MainActor in
            // Attempt to copy any currently selected text from external active app
            await postSyntheticCopy()

            let selected = selectedNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
            let clipboard = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let source = selected.isEmpty ? clipboard : selected

            translationOriginalText = source
            translationTranslatedText = source.isEmpty ? generalSettingsStore.text(.noTextToTranslate) : ""

            FloatingTranslationWindowManager.shared.show(
                audioRecorder: translationAudioRecorder,
                providerID: $translationProviderID,
                targetLanguage: $translationTargetLanguage,
                originalText: $translationOriginalText,
                translatedText: $translationTranslatedText,
                generalSettingsStore: generalSettingsStore,
                polishingEngineStore: polishingEngineStore,
                glossaryStore: glossaryStore,
                onTranslate: translateText,
                onRecordingCompleted: transcribeForTranslation
            )

            guard !source.isEmpty else { return }
            guard !translationProviderID.isEmpty else {
                translationTranslatedText = generalSettingsStore.text(.noTranslationProvider)
                return
            }

            translationTranslatedText = generalSettingsStore.text(.translating)
            do {
                let result = try await translateText(
                    text: source,
                    targetLanguage: translationTargetLanguage,
                    providerID: translationProviderID
                )
                translationTranslatedText = result.text
            } catch {
                translationTranslatedText = error.localizedDescription
            }
        }
    }

    private func postSyntheticCopy() async {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        cDown?.flags = .maskCommand
        cUp?.flags = .maskCommand
        cDown?.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 30_000_000)
        cUp?.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    private func openQuickTranslationWindow() {
        // Toggle: if already visible, close it
        if QuickTranslationWindowManager.shared.isVisible {
            QuickTranslationWindowManager.shared.close()
            return
        }

        Task { @MainActor in
            await postSyntheticCopy()

            let selected = selectedNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
            let clipboard = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let source = selected.isEmpty ? clipboard : selected

            guard !source.isEmpty, !translationProviderID.isEmpty else {
                QuickTranslationWindowManager.shared.show(
                    text: "",
                    generalSettingsStore: generalSettingsStore
                )
                return
            }

            do {
                let result = try await translateText(
                    text: source,
                    targetLanguage: translationTargetLanguage,
                    providerID: translationProviderID
                )
                QuickTranslationWindowManager.shared.show(
                    text: result.text,
                    generalSettingsStore: generalSettingsStore
                )
            } catch {
                QuickTranslationWindowManager.shared.show(
                    text: error.localizedDescription,
                    generalSettingsStore: generalSettingsStore
                )
            }
        }
    }

    private func toggleSettingsWindow() {
        let now = Date()
        guard now.timeIntervalSince(lastSettingsToggleTime) > 0.3 else { return }
        lastSettingsToggleTime = now

        NSApp.activate(ignoringOtherApps: true)

        if let window = findOfficialSettingsWindow() {
            if window.isVisible && window.isKeyWindow {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
            }
            return
        }

        if triggerSettingsMenuItem() {
            return
        }

        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private func triggerSettingsMenuItem() -> Bool {
        guard let mainMenu = NSApp.mainMenu else { return false }
        for menuItem in mainMenu.items {
            guard let submenu = menuItem.submenu else { continue }
            for item in submenu.items {
                let actionName = item.action.map { NSStringFromSelector($0) } ?? ""
                if actionName == "showSettingsWindow:" ||
                   actionName == "showPreferencesWindow:" ||
                   (item.keyEquivalent == "," && item.keyEquivalentModifierMask.contains(.command)) {
                    if let action = item.action {
                        NSApp.sendAction(action, to: item.target, from: item)
                        return true
                    }
                }
            }
        }
        return false
    }

    private func findOfficialSettingsWindow() -> NSWindow? {
        NSApp.windows.first { window in
            let title = window.title
            let className = String(describing: type(of: window))
            let identifier = window.identifier?.rawValue ?? ""
            return identifier.contains("Settings") ||
                   className.contains("Settings") ||
                   className.contains("Preferences") ||
                   title == "Settings" ||
                   title == "Настройки" ||
                   title == "Ajustes" ||
                   title == "Einstellungen" ||
                   title == "Réglages" ||
                   title.contains("Settings") ||
                   title.contains("Настройки")
        }
    }

    private func translateText(
        text: String,
        targetLanguage: String,
        providerID: String
    ) async throws -> PolishingResult {
        let prompt = try TranslationPrompt.render(text: text, targetLanguage: targetLanguage)

        // Resolve engine: per-model MLX tag vs. cloud provider ID
        let engine: any PolishingEngine
        if let modelID = TranslationModalView.localMLXModelID(from: providerID),
           let model = polishingEngineStore.allModels.first(where: { $0.id == modelID }) {
            engine = polishingEngineStore.engine(forLocalMLXModel: model)
        } else {
            engine = polishingEngineStore.engine(for: providerID)
        }

        let startedAt = Date()
        NativeSmartScribeLog.polishing.info(
            "Translation started provider=\(providerID, privacy: .public) engine=\(engine.displayName, privacy: .public) textLength=\(text.count)"
        )

        let result = try await engine.polish(
            PolishingRequest(
                rawText: prompt,
                variant: .variantOne,
                template: PromptTemplate(
                    id: "translation-pass-through",
                    title: "Translation",
                    body: PromptTemplate.transcriptionPlaceholder
                )
            )
        )

        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        NativeSmartScribeLog.polishing.info(
            "Translation completed in \(elapsedMs)ms provider=\(providerID, privacy: .public) engine=\(engine.displayName, privacy: .public)"
        )

        usageStatisticsStore.record(
            modelID: result.diagnostics.backendName,
            modelName: result.diagnostics.backendName,
            diagnostics: result.diagnostics
        )
        let rewritten = glossaryStore.apply(
            to: result.text,
            target: .translation,
            language: targetLanguage
        )
        return PolishingResult(
            text: rewritten.text,
            diagnostics: result.diagnostics
        )
    }

    private func transcribeForTranslation(_ recording: AudioRecording) async throws -> String {
        // Cloud · Google Gemini: the local TranscriptionEngineStore returns
        // UnavailableTranscriptionEngine for .geminiCloud, so route through
        // the dictation engine directly — plain transcription, no polishing.
        if transcriptionModelStore.settings.backend == .geminiCloud {
            let google = polishingEngineStore.apiSettings.configuration(for: .google)
            let engine = GeminiCloudDictationEngine(
                apiKey: google.apiKey,
                modelID: google.textModel
            )
            let result = try await engine.dictate(
                GeminiCloudDictationEngine.DictationRequest(
                    audioFileURL: recording.fileURL,
                    forceTargetLanguage: false,
                    targetLanguageName: ""
                )
            )
            return glossaryStore.apply(to: result.text, target: .source).text
        }

        let engine = transcriptionEngineStore.activeEngine(modelStore: transcriptionModelStore)
        let languageCode = transcriptionModelStore.resolvedLanguageCode
        // Native translation is only available on multilingual Whisper; Parakeet
        // and English-only Whisper translate via the polishing pass instead.
        let isMultilingual = activeModelSupportsNativeTranslation
        let route = TranscriptionLanguageRouter.route(
            resolvedLanguageCode: languageCode,
            isMultilingualModel: isMultilingual
        )
        let result = try await engine.transcribe(
            TranscriptionRequest(
                audioFileURL: recording.fileURL,
                forcedLanguageCode: route.forcedLanguageCode,
                translateToEnglish: route.translateToEnglish
            )
        )
        return glossaryStore.apply(to: result.text, target: .source).text
    }

    private func transcribeRecording(
        _ recording: AudioRecording,
        hotkeyTarget: HotkeyTarget?,
        outputMode: HotkeyOutputMode?,
        forceTargetLanguage: Bool = false
    ) {
        Task { @MainActor in
            // Cloud · Google Gemini: fast audio-to-Raw first, followed by an
            // optional text-only Variant 1/2 polishing pass.
            if transcriptionModelStore.settings.backend == .geminiCloud {
                await transcribeRecordingViaGeminiCloud(
                    recording,
                    hotkeyTarget: hotkeyTarget,
                    outputMode: outputMode,
                    forceTargetLanguage: forceTargetLanguage
                )
                return
            }

            let workflow = RecordingTranscriptionWorkflow(
                noteStore: noteStore,
                engine: transcriptionEngineStore.activeEngine(
                    modelStore: transcriptionModelStore
                ),
                glossarySettingsProvider: { glossaryStore.settings }
            )
            let languageCode: String
            if forceTargetLanguage {
                // E / target mode: output must be the configured target language.
                languageCode = targetLanguageCode
            } else if hotkeyTarget != nil {
                // A / auto mode on hotkey: always auto-detect spoken language.
                languageCode = "auto"
            } else {
                languageCode = transcriptionModelStore.resolvedLanguageCode
            }
            // Native translation is only available on multilingual Whisper; Parakeet
            // and English-only Whisper translate via the polishing pass instead.
            let isMultilingual = activeModelSupportsNativeTranslation
            let route = TranscriptionLanguageRouter.route(
                resolvedLanguageCode: languageCode,
                isMultilingualModel: isMultilingual,
                forceTargetLanguage: forceTargetLanguage
            )

            let noteID = await workflow.transcribeRecording(
                recording,
                forcedLanguageCode: route.forcedLanguageCode,
                translateToEnglish: route.translateToEnglish
            )

            // Target language display name for any post-Whisper LLM translation.
            let autoTranslationTargetLanguage = route.autoTranslateTargetLanguageCode.map {
                TranscriptionLanguageOption.displayName(for: $0)
            } ?? (forceTargetLanguage ? TranscriptionLanguageOption.displayName(for: languageCode) : nil)

            // Raw + force-target:
            // - English target: Whisper `task: .translate` already produced English.
            //   No LLM/MLX (fast path the user expects for E+R).
            // - Any other target (Spanish, French, …): Whisper cannot output that
            //   language natively, so we must run a translation pass (translation
            //   provider / polishing engine) before inserting raw text.
            if let hotkeyTarget, hotkeyTarget == .raw {
                if forceTargetLanguage,
                   let targetCode = route.autoTranslateTargetLanguageCode,
                   let rawText = noteStore.note(withID: noteID)?.rawText,
                   !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let targetLanguageName = autoTranslationTargetLanguage
                        ?? TranscriptionLanguageOption.displayName(for: targetCode)
                    NativeSmartScribeLog.hotkey.info(
                        "Raw hotkey non-English target path forceTargetLanguage=true target=\(targetCode, privacy: .public) (LLM translation after Whisper)"
                    )
                    await autoTranslateRawText(
                        noteID: noteID,
                        rawText: rawText,
                        targetLanguage: targetLanguageName
                    )
                } else {
                    NativeSmartScribeLog.hotkey.info(
                        "Raw hotkey path forceTargetLanguage=\(forceTargetLanguage) translateToEnglish=\(route.translateToEnglish) forcedLanguageCode=\(route.forcedLanguageCode ?? "none", privacy: .public) resolvedLanguageCode=\(languageCode, privacy: .public) (Whisper only)"
                    )
                }
                selectedVariant = .raw
                applyHotkeyOutputIfNeeded(for: noteID, target: hotkeyTarget, mode: outputMode)
                finishHotkeySessionIfNeeded(target: hotkeyTarget)
                return
            }

            // E1 / E2 (and non-raw flows): optional LLM translation + polishing.
            let rawText = noteStore.note(withID: noteID)?.rawText ?? ""
            let rawTextLooksForeign = rawTextNeedsTargetLanguageConversion(
                rawText,
                targetLanguageCode: languageCode
            )
            let needsTranslation = forceTargetLanguage
                && (route.autoTranslateTargetLanguageCode != nil || rawTextLooksForeign)

            NativeSmartScribeLog.hotkey.info(
                "Transcription routing forceTargetLanguage=\(forceTargetLanguage) translateToEnglish=\(route.translateToEnglish) forcedLanguageCode=\(route.forcedLanguageCode ?? "none", privacy: .public) autoTranslationTarget=\(autoTranslationTargetLanguage ?? "none", privacy: .public) resolvedLanguageCode=\(languageCode, privacy: .public) needsTranslation=\(needsTranslation) rawLooksForeign=\(rawTextLooksForeign)"
            )
            // Variant B: only native-translation models (multilingual Whisper)
            // pre-translate the raw text here. For Parakeet / English-only Whisper
            // the raw transcript stays in the source language and the translation is
            // produced by the polishing pass below (the target language is forwarded
            // to `polish` via `polishingTargetLang`).
            let needsRawPreTranslation = activeModelSupportsNativeTranslation && needsTranslation
            if needsRawPreTranslation,
               let targetLanguageName = autoTranslationTargetLanguage,
               !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await autoTranslateRawText(
                    noteID: noteID,
                    rawText: rawText,
                    targetLanguage: targetLanguageName
                )
            }

            if let hotkeyTarget {
                selectedVariant = hotkeyTarget.processingVariant
            }

            guard polishingEngineStore.canAutoPolishAfterTranscription else {
                NativeSmartScribeLog.polishing.info("Skipped automatic polishing because no local polishing model is ready.")
                // Show the raw transcription tab so the user sees the (potentially
                // English-translated) text even when no polishing model is active.
                selectedVariant = hotkeyTarget?.processingVariant ?? .raw
                if polishingEngineStore.selectedEngineID != PolishingEngineStore.disabledEngineID {
                    markPolishingUnavailable(for: noteID)
                }
                applyHotkeyOutputIfNeeded(for: noteID, target: hotkeyTarget, mode: outputMode)
                finishHotkeySessionIfNeeded(target: hotkeyTarget)
                return
            }

            let requestedVariants = hotkeyTarget?.requestedPolishingVariants ?? [.variantOne, .variantTwo]
            selectedVariant = hotkeyTarget?.processingVariant ?? requestedVariants.first ?? .variantOne
            let polishingTargetLang = forceTargetLanguage ? targetLanguageCode : nil
            await polish(noteID, variants: requestedVariants, targetLanguage: polishingTargetLang)
            selectedVariant = hotkeyTarget?.processingVariant ?? selectedVariant
            applyHotkeyOutputIfNeeded(for: noteID, target: hotkeyTarget, mode: outputMode)
            finishHotkeySessionIfNeeded(target: hotkeyTarget)
        }
    }

    private func polishNote(_ noteID: SmartScribeNote.ID) {
        selectedVariant = .variantOne
        Task { @MainActor in
            await polish(noteID)
        }
    }

    private func polish(
        _ noteID: SmartScribeNote.ID,
        variants: [ProcessingVariant] = [.variantOne, .variantTwo],
        targetLanguage: String? = nil
    ) async {
        let workflow = PolishingWorkflow(
            noteStore: noteStore,
            engine: polishingEngineStore.activeEngine,
            templateProvider: { variant in
                promptTemplateStore.template(for: variant)
            },
            messageProvider: { key in
                generalSettingsStore.text(key)
            }
        )
        let results = await workflow.polishNote(noteID, variants: variants, targetLanguage: targetLanguage)
        for result in results.values {
            usageStatisticsStore.record(
                modelID: result.diagnostics.backendName,
                modelName: result.diagnostics.backendName,
                diagnostics: result.diagnostics
            )
        }
    }

    /// Translates the raw transcription to the target language using the active
    /// polishing engine and overwrites `rawText` with the translated version.
    /// Used for auto-translation when any non-auto transcription language is selected,
    /// including English (all languages now share this LLM path).
    private func autoTranslateRawText(
        noteID: SmartScribeNote.ID,
        rawText: String,
        targetLanguage: String
    ) async {
        // Resolve the translation engine the same way the in-app Translation
        // modal does: prefer the user-selected translation provider (which may be
        // a local MLX model tagged "local-mlx:<modelID>"), and only fall back to
        // the active polishing engine when no translation provider is configured.
        // This keeps HUD auto-translation working even when the active polishing
        // engine (e.g. a cloud provider with a missing API key) is unavailable.
        let engine: any PolishingEngine
        if let resolved = resolveTranslationEngine(providerID: translationProviderID) {
            engine = resolved
        } else if polishingEngineStore.canAutoPolishAfterTranscription {
            engine = polishingEngineStore.activeEngine
        } else {
            NativeSmartScribeLog.polishing.info(
                "Skipped auto-translation — no translation provider or polishing engine available."
            )
            return
        }

        do {
            let prompt = try TranslationPrompt.render(
                text: rawText,
                targetLanguage: targetLanguage
            )
            let result = try await engine.polish(
                PolishingRequest(
                    rawText: prompt,
                    variant: .variantOne,
                    template: PromptTemplate(
                        id: "auto-translation-pass-through",
                        title: "Auto Translation",
                        body: PromptTemplate.transcriptionPlaceholder
                    )
                )
            )

            let translatedText = glossaryStore.apply(
                to: result.text,
                target: .translation,
                language: targetLanguage
            ).text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translatedText.isEmpty else { return }

            noteStore.updateRawText(for: noteID, text: translatedText)
            usageStatisticsStore.record(
                modelID: result.diagnostics.backendName,
                modelName: result.diagnostics.backendName,
                diagnostics: result.diagnostics
            )
        } catch {
            NativeSmartScribeLog.polishing.error(
                "Auto-translation failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Resolves the polishing engine to use for translation from a translation
    /// provider tag, mirroring `translateText`. Local MLX models are tagged
    /// "local-mlx:<modelID>"; anything else is treated as a provider/engine ID.
    /// Returns `nil` when the provider tag is empty or its model is unavailable.
    private func resolveTranslationEngine(providerID: String) -> (any PolishingEngine)? {
        let trimmed = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let modelID = TranslationModalView.localMLXModelID(from: trimmed) {
            guard let model = polishingEngineStore.allModels.first(where: { $0.id == modelID }) else {
                return nil
            }
            return polishingEngineStore.engine(forLocalMLXModel: model)
        }

        return polishingEngineStore.engine(for: trimmed)
    }

    private func generateMarkdown(
        for noteID: SmartScribeNote.ID,
        variant: ProcessingVariant
    ) {
        guard variant != .raw else { return }
        guard let note = noteStore.note(withID: noteID) else { return }

        let sourceText: String
        switch variant {
        case .raw:
            sourceText = note.rawText
        case .variantOne:
            sourceText = note.polishedVariantOne
        case .variantTwo:
            sourceText = note.polishedVariantTwo
        }

        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard polishingEngineStore.selectedEngineID != PolishingEngineStore.disabledEngineID else { return }
        guard polishingEngineStore.selectedEngineID != "local-rule-based-polish" else { return }

        Task { @MainActor in
            noteStore.markPolishingStarted(
                for: noteID,
                variant: variant,
                backendName: polishingEngineStore.activeEngine.displayName
            )

            do {
                let result = try await polishingEngineStore.activeEngine.polish(
                    PolishingRequest(
                        rawText: trimmed,
                        variant: variant,
                        template: promptTemplateStore.markdownTemplate()
                    )
                )

                let markdown = MarkdownGenerationPostProcessor.ensureVisibleMarkdown(
                    result.text,
                    sourceText: trimmed
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !markdown.isEmpty else {
                    noteStore.markPolishingFailed(
                        for: noteID,
                        variant: variant,
                        message: generalSettingsStore.text(.emptyPolishingResult),
                        backendName: result.diagnostics.backendName
                    )
                    return
                }

                noteStore.applyPolishingResult(
                    for: noteID,
                    variant: variant,
                    result: PolishingResult(
                        text: markdown,
                        diagnostics: result.diagnostics
                    )
                )
                usageStatisticsStore.record(
                    modelID: result.diagnostics.backendName,
                    modelName: result.diagnostics.backendName,
                    diagnostics: result.diagnostics
                )
            } catch {
                noteStore.markPolishingFailed(
                    for: noteID,
                    variant: variant,
                    message: error.localizedDescription,
                    backendName: polishingEngineStore.activeEngine.displayName
                )
            }
        }
    }

    private func handleHotkeyTriggered() {
        guard !isTogglingHotkeyRecording else { return }

        let settings = hotkeySettingsStore.settings
        guard settings.enabled else { return }

        isTogglingHotkeyRecording = true
        Task { @MainActor in
            defer { isTogglingHotkeyRecording = false }

            if audioRecorder.isRecording {
                // Prefer normal recording → processing transition. If the session
                // phase was lost while audio kept running (older 5-minute timeout,
                // multi-window race), reclaim from idle so stop still works.
                let canProcess = HotkeySessionCoordinator.shared.beginProcessing(ownerID: hotkeyOwnerID)
                    || HotkeySessionCoordinator.shared.reclaimOrphanedRecordingForStop(ownerID: hotkeyOwnerID)
                guard canProcess else {
                    NativeSmartScribeLog.hotkey.info(
                        "Ignored stop hotkey for non-owner content view owner=\(self.hotkeyOwnerID.uuidString, privacy: .public) phaseOwned=\(HotkeySessionCoordinator.shared.isOwned(by: self.hotkeyOwnerID))"
                    )
                    return
                }

                guard let recording = audioRecorder.stop() else {
                    NativeSmartScribeLog.hotkey.error(
                        "Stop hotkey: audioRecorder reported isRecording but stop() returned nil"
                    )
                    HotkeySessionCoordinator.shared.finish(ownerID: hotkeyOwnerID)
                    hotkeySessionOverlayManager.hide()
                    return
                }
                hotkeySessionOverlayManager.show(
                    mode: .processing,
                    settings: generalSettingsStore.settings.overlay,
                    showsControls: false,
                    onOriginChange: persistOverlayOrigin
                )
                let target = pendingHotkeyTarget ?? settings.target
                let mode = pendingHotkeyOutputMode ?? settings.mode
                let forceTargetValue = effectiveHUDForceTargetLanguage
                pendingHotkeyTarget = nil
                pendingHotkeyOutputMode = nil
                pendingHotkeyForceTargetLanguage = forceTargetValue
                NativeSmartScribeLog.hotkey.info(
                    "Stopped hotkey recording target=\(target.rawValue, privacy: .public) mode=\(mode.rawValue, privacy: .public) forceTargetLanguage=\(forceTargetValue) capturedSourcePID=\(pendingHotkeySourcePID ?? -1, privacy: .public) hasFocusedElement=\(pendingHotkeyFocusedElement != nil, privacy: .public)"
                )
                transcribeRecording(recording, hotkeyTarget: target, outputMode: mode, forceTargetLanguage: forceTargetValue)
            } else {
                guard HotkeySessionCoordinator.shared.beginRecording(ownerID: hotkeyOwnerID) else {
                    NativeSmartScribeLog.hotkey.info(
                        "Ignored start hotkey for non-owner content view owner=\(self.hotkeyOwnerID.uuidString, privacy: .public)"
                    )
                    return
                }

                let sourceApplication = NSWorkspace.shared.frontmostApplication
                pendingHotkeySourcePID = sourceApplication?.processIdentifier
                pendingHotkeyFocusedElement = AccessibilityPermissionService.focusedElement()
                let resolvedTarget = settings.target
                let languageControlEnabled = isHUDLanguageControlEnabled(for: resolvedTarget)
                if !languageControlEnabled {
                    persistentHUDForceTargetLanguage = false
                }
                let forceTargetLanguage = effectiveHUDForceTargetLanguage
                pendingHotkeyTarget = resolvedTarget
                pendingHotkeyOutputMode = settings.mode
                pendingHotkeyForceTargetLanguage = forceTargetLanguage
                if resolvedTarget != .raw {
                    polishingEngineStore.ensurePolishingEnabledForWidgetTarget()
                }
                NativeSmartScribeLog.hotkey.info(
                    "Started hotkey recording activeTargetLang=\(forceTargetLanguage) languageControlEnabled=\(languageControlEnabled) target=\(settings.target.rawValue, privacy: .public) mode=\(settings.mode.rawValue, privacy: .public) sourcePID=\(sourceApplication?.processIdentifier ?? -1, privacy: .public) sourceBundle=\(sourceApplication?.bundleIdentifier ?? "unknown", privacy: .public) hasFocusedElement=\(pendingHotkeyFocusedElement != nil, privacy: .public)"
                )
                await audioRecorder.start()

                if audioRecorder.isRecording {
                    hotkeySessionOverlayManager.show(
                        mode: .listening,
                        settings: generalSettingsStore.settings.overlay,
                        languageMode: forceTargetLanguage ? .target : .auto,
                        hotkeyTarget: resolvedTarget,
                        targetLanguageLabel: autoTranslationLanguageLabel,
                        showsControls: true,
                        languageControlEnabled: languageControlEnabled,
                        onOriginChange: persistOverlayOrigin,
                        onLanguageTap: handleOverlayLanguageTap,
                        onTargetTap: handleOverlayTargetTap,
                        onScroll: handleOverlayProviderScroll
                    )
                    hotkeySessionOverlayManager.update(
                        spectrumBands: audioRecorder.frequencyBands,
                        settings: generalSettingsStore.settings.overlay
                    )
                    hotkeySessionOverlayManager.playCue(.start, settings: generalSettingsStore.settings.overlay)
                } else {
                    pendingHotkeySourcePID = nil
                    pendingHotkeyFocusedElement = nil
                    pendingHotkeyTarget = nil
                    pendingHotkeyOutputMode = nil
                    pendingHotkeyForceTargetLanguage = false
                    hotkeySessionOverlayManager.hide()
                    HotkeySessionCoordinator.shared.finish(ownerID: hotkeyOwnerID)
                }
            }
        }
    }

    private func applyHotkeyOutputIfNeeded(
        for noteID: SmartScribeNote.ID,
        target: HotkeyTarget?,
        mode: HotkeyOutputMode?
    ) {
        guard let mode, let target, let note = noteStore.note(withID: noteID) else { return }

        let text = HotkeyOutputTextResolver.text(from: note, target: target)
        let targetApplication = pendingHotkeySourcePID.flatMap(NSRunningApplication.init(processIdentifier:))
        NativeSmartScribeLog.hotkey.info(
            "Resolved hotkey output target=\(target.rawValue, privacy: .public) mode=\(mode.rawValue, privacy: .public) textLength=\(text.trimmingCharacters(in: .whitespacesAndNewlines).count, privacy: .public) sourcePID=\(pendingHotkeySourcePID ?? -1, privacy: .public) sourceBundle=\(targetApplication?.bundleIdentifier ?? "unknown", privacy: .public)"
        )
        HotkeyOutputDispatcher.shared.dispatch(
            text: text,
            mode: mode,
            targetApplication: targetApplication,
            targetElement: pendingHotkeyFocusedElement
        )
        pendingHotkeySourcePID = nil
        pendingHotkeyFocusedElement = nil
    }

    private func finishHotkeySessionIfNeeded(target: HotkeyTarget?) {
        hotkeySessionOverlayManager.playCue(.finish, settings: generalSettingsStore.settings.overlay)
        hotkeySessionOverlayManager.hide()
        providerQuickSwitcher.hide()
        HotkeySessionCoordinator.shared.finish(ownerID: hotkeyOwnerID)
    }

    private func persistOverlayOrigin(_ origin: OverlayHUDOrigin) {
        generalSettingsStore.update { settings in
            settings.overlay.setOrigin(origin, for: settings.overlay.style)
        }
    }

    // MARK: - Provider quick switcher (hidden HUD scroll gesture)

    private func configureProviderQuickSwitcher() {
        let store = polishingEngineStore
        let switcher = providerQuickSwitcher
        switcher.onSwitchProvider = { providerID in
            ContentView.applyQuickSwitchProvider(providerID: providerID, store: store)
        }
        switcher.onModelMenuRequested = { providerID, anchorView, location in
            ContentView.presentQuickSwitchModelMenu(
                providerID: providerID,
                anchorView: anchorView,
                location: location,
                store: store,
                switcher: switcher
            )
        }
    }

    private func handleOverlayProviderScroll(deltaY: CGFloat) {
        var providers: [ProviderQuickSwitcherModel.Provider] = [
            ProviderQuickSwitcherModel.Provider(
                id: PolishingEngineStore.mlxSwiftEngineID,
                displayName: "Local.AI"
            )
        ]

        let cloudProviders = polishingEngineStore.apiSettings.availablePolishingProviders.map {
            ProviderQuickSwitcherModel.Provider(
                id: $0.kind.polishingEngineID,
                displayName: $0.displayName
            )
        }

        for p in cloudProviders {
            if !providers.contains(where: { $0.id == p.id || $0.displayName == p.displayName }) {
                providers.append(p)
            }
        }

        guard !providers.isEmpty,
              let anchorFrame = hotkeySessionOverlayManager.currentHUDFrame() else {
            return
        }
        providerQuickSwitcher.handleHUDScroll(
            deltaY: deltaY,
            providers: providers,
            activeID: polishingEngineStore.selectedEngineID,
            anchorFrame: anchorFrame
        )
    }

    private static func applyQuickSwitchProvider(providerID: String, store: PolishingEngineStore) {
        if providerID == PolishingEngineStore.mlxSwiftEngineID {
            store.selectedEngineID = PolishingEngineStore.mlxSwiftEngineID
        } else if let kind = APIProviderKind(polishingEngineID: providerID) {
            store.selectAPIProvider(kind)
        }
    }

    private static func presentQuickSwitchModelMenu(
        providerID: String,
        anchorView: NSView,
        location: NSPoint,
        store: PolishingEngineStore,
        switcher: ProviderQuickSwitcher
    ) {
        if providerID == PolishingEngineStore.mlxSwiftEngineID {
            let downloadedModels = store.allModels.filter { store.installationState(for: $0).isDownloaded }
            let currentActiveID = store.settings.activeModelID
            let menu = NSMenu()
            menu.autoenablesItems = false
            var targets: [QuickSwitcherMenuTarget] = []

            if downloadedModels.isEmpty {
                let item = NSMenuItem(
                    title: "No local models downloaded",
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                menu.addItem(item)
            } else {
                for model in downloadedModels {
                    let target = QuickSwitcherMenuTarget {
                        store.activate(model)
                        switcher.hide()
                    }
                    targets.append(target)
                    let item = NSMenuItem(
                        title: model.displayName,
                        action: #selector(QuickSwitcherMenuTarget.invoke),
                        keyEquivalent: ""
                    )
                    item.target = target
                    if model.id == currentActiveID {
                        item.state = NSControl.StateValue.on
                    }
                    menu.addItem(item)
                }
            }
            menu.popUp(positioning: nil, at: location, in: anchorView)
            return
        }

        guard let kind = APIProviderKind(polishingEngineID: providerID) else { return }
        let optionsProvider = PolishingModelOptionsProvider(apiSettings: store.apiSettings)
        let options = optionsProvider.providerModelOptions(
            for: kind,
            favorites: FavoriteModelsStore.loadFavorites()
        )
        guard !options.isEmpty else { return }

        let currentModel = store.apiSettings.configuration(for: kind).textModel
        let menu = NSMenu()
        menu.autoenablesItems = false
        var targets: [QuickSwitcherMenuTarget] = []
        for option in options {
            let target = QuickSwitcherMenuTarget {
                var config = store.apiSettings.configuration(for: kind)
                config.textModel = option.id
                store.updateAPIConfiguration(config, for: kind)
                store.selectAPIProvider(kind)
                switcher.hide()
            }
            targets.append(target)
            let item = NSMenuItem(
                title: option.displayName,
                action: #selector(QuickSwitcherMenuTarget.invoke),
                keyEquivalent: ""
            )
            item.target = target
            if option.id == currentModel {
                item.state = NSControl.StateValue.on
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: location, in: anchorView)
    }

    /// Retains a closure behind an `NSMenuItem` target for the duration of a
    /// synchronous `NSMenu.popUp` call.
    private final class QuickSwitcherMenuTarget: NSObject {
        private let handler: () -> Void
        init(handler: @escaping () -> Void) {
            self.handler = handler
        }
        @objc func invoke() {
            handler()
        }
    }

    /// Target language code used when the HUD is in E (force target) mode.
    ///
    /// Priority:
    /// 1. Hotkey "Transcription Language" setting when it is not Auto
    /// 2. Glossary Auto Translation Language
    /// 3. English
    ///
    /// This matches the settings copy: choosing a specific transcription language
    /// enables auto-translation into that language regardless of what was spoken.
    private var targetLanguageCode: String {
        let fromTranscription = transcriptionModelStore.resolvedLanguageCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !fromTranscription.isEmpty, fromTranscription != "auto" {
            return normalizeLanguageCode(fromTranscription)
        }

        let autoLang = glossaryStore.settings.autoTranslationLanguage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizeLanguageCode(autoLang.isEmpty ? "en" : autoLang)
    }

    private func normalizeLanguageCode(_ value: String) -> String {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if code.isEmpty || code == "auto" {
            return "en"
        }
        if code.hasPrefix("en") || code == "english" {
            return "en"
        }
        if let option = TranscriptionLanguageOption.builtIn.first(where: {
            $0.displayName.lowercased() == code || $0.code == code
        }) {
            return option.code
        }
        return code
    }

    /// Heuristic: after Whisper, does the raw transcript still look like it is
    /// not in the requested target language? Used to trigger an LLM fallback
    /// for ER (target language + Raw) when native Whisper translate fails.
    private func rawTextNeedsTargetLanguageConversion(
        _ text: String,
        targetLanguageCode: String
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let target = normalizeLanguageCode(targetLanguageCode)
        let hasCyrillic = trimmed.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil
        let hasLatin = trimmed.range(of: "[A-Za-z]", options: .regularExpression) != nil

        if target == "en" || target.hasPrefix("en") {
            // English target: any substantial Cyrillic means conversion failed.
            return hasCyrillic
        }

        if target == "ru" || target == "uk" || target == "bg" || target == "sr" {
            // Cyrillic target: Latin-only text likely still needs conversion.
            return hasLatin && !hasCyrillic
        }

        // Other targets: if the spoken language left Cyrillic and the target is
        // not Cyrillic, conversion is still needed.
        return hasCyrillic
    }

    /// Compact HUD letter for the configured target language
    /// (English → E, Spanish → S, French → F, Chinese → C, …).
    private var autoTranslationLanguageLabel: String {
        TranscriptionLanguageOption.hudLabel(for: targetLanguageCode)
    }

    /// Whether the active transcription model can translate speech natively.
    /// Only multilingual Whisper supports this (WhisperKit `task: .translate`,
    /// X→English). Parakeet and English-only Whisper cannot translate natively;
    /// for them translation happens during the polishing pass instead.
    private var activeModelSupportsNativeTranslation: Bool {
        guard let activeModel = transcriptionModelStore.activeModel else { return false }
        return activeModel.backend == .whisperKitCoreML
            && activeModel.languageSupport == .multilingual
    }

    /// The processing target currently reflected by the HUD (R / 1 / 2).
    private var currentHUDTarget: HotkeyTarget {
        pendingHotkeyTarget ?? hotkeySettingsStore.settings.target
    }

    private var isHUDLanguageControlEnabled: Bool {
        isHUDLanguageControlEnabled(for: currentHUDTarget)
    }

    /// Whether the HUD language ("A") control should be enabled for a given target.
    /// - Gemini Cloud and native-translation models (multilingual Whisper): always.
    /// - Non-translating models (Parakeet, English-only Whisper): only for polishing
    ///   variants (1/2) and only when an LLM polishing engine is available, because
    ///   the translation is performed by the polishing model. On RAW there is no
    ///   translation path, so the control stays disabled.
    private func isHUDLanguageControlEnabled(for target: HotkeyTarget) -> Bool {
        if transcriptionModelStore.settings.backend == .geminiCloud {
            return true
        }
        if activeModelSupportsNativeTranslation {
            return true
        }
        guard target != .raw else { return false }
        return polishingEngineStore.isActiveEngineTranslationCapable
    }

    private var effectiveHUDForceTargetLanguage: Bool {
        isHUDLanguageControlEnabled && persistentHUDForceTargetLanguage
    }

    /// Toggles the transcription language mode between auto-detection
    /// and the configured target language, persisting the selection for future sessions.
    private func handleOverlayLanguageTap() {
        guard isHUDLanguageControlEnabled else {
            persistentHUDForceTargetLanguage = false
            pendingHotkeyForceTargetLanguage = false
            hotkeySessionOverlayManager.update(
                languageMode: .auto,
                languageControlEnabled: false
            )
            return
        }

        persistentHUDForceTargetLanguage.toggle()
        pendingHotkeyForceTargetLanguage = persistentHUDForceTargetLanguage
        hotkeySessionOverlayManager.update(
            languageMode: persistentHUDForceTargetLanguage ? .target : .auto,
            targetLanguageLabel: autoTranslationLanguageLabel
        )
    }

    /// Cycles the processing target (raw -> variant 1 -> variant 2) and persists
    /// it as the new default for future sessions. Automatically re-enables the last used
    /// polishing engine/model if polishing was previously disabled.
    private func handleOverlayTargetTap() {
        let current = pendingHotkeyTarget ?? hotkeySettingsStore.settings.target
        let next = current.next()
        pendingHotkeyTarget = next
        hotkeySettingsStore.settings.target = next
        if next != .raw {
            polishingEngineStore.ensurePolishingEnabledForWidgetTarget()
        }
        // For non-translating models the language ("A") control is only available on
        // polishing variants. Re-evaluate it after every target change and reset the
        // forced target language when the control becomes unavailable (e.g. on RAW).
        let languageControlEnabled = isHUDLanguageControlEnabled(for: next)
        if !languageControlEnabled {
            persistentHUDForceTargetLanguage = false
            pendingHotkeyForceTargetLanguage = false
        }
        hotkeySessionOverlayManager.update(
            languageMode: persistentHUDForceTargetLanguage ? .target : .auto,
            hotkeyTarget: next,
            targetLanguageLabel: autoTranslationLanguageLabel,
            languageControlEnabled: languageControlEnabled
        )
    }

    /// Two-stage cloud dictation:
    /// 1. Gemini Flash/Flash-Lite turns audio into a faithful, lightly cleaned Raw transcript.
    /// 2. Variant 1/2, when requested, runs as a separate text-only polishing request.
    private func transcribeRecordingViaGeminiCloud(
        _ recording: AudioRecording,
        hotkeyTarget: HotkeyTarget?,
        outputMode: HotkeyOutputMode?,
        forceTargetLanguage: Bool
    ) async {
        let google = polishingEngineStore.apiSettings.configuration(for: .google)
        let resolvedTarget = hotkeyTarget ?? hotkeySettingsStore.settings.target
        let targetName = TranscriptionLanguageOption.displayName(for: targetLanguageCode)

        let note = noteStore.addRecordedNote(recording: recording, now: .now)
        let noteID = note.id
        noteStore.markTranscriptionStarted(for: noteID, backendName: "Google Gemini")

        do {
            let engine = GeminiCloudDictationEngine(
                apiKey: google.apiKey,
                modelID: google.textModel
            )
            let result = try await engine.dictate(
                GeminiCloudDictationEngine.DictationRequest(
                    audioFileURL: recording.fileURL,
                    forceTargetLanguage: forceTargetLanguage,
                    targetLanguageName: targetName
                )
            )

            let glossarySettings = glossaryStore.settings
            let rewrittenRaw = glossarySettings.enabled
                ? GlossaryTextRewriter.apply(
                    to: result.text,
                    entries: glossarySettings.entries,
                    target: .source
                )
                : GlossaryTextRewriter.Result(text: result.text, count: 0)

            noteStore.applyTranscriptionResult(
                for: noteID,
                result: TranscriptionResult(
                    text: rewrittenRaw.text,
                    diagnostics: result.diagnostics
                )
            )

            usageStatisticsStore.record(
                modelID: result.diagnostics.backendName,
                modelName: result.diagnostics.backendName,
                diagnostics: result.diagnostics
            )

            if resolvedTarget == .raw {
                selectedVariant = .raw
                applyHotkeyOutputIfNeeded(for: noteID, target: resolvedTarget, mode: outputMode)
                finishHotkeySessionIfNeeded(target: hotkeyTarget == nil ? nil : resolvedTarget)
                return
            }

            guard polishingEngineStore.canAutoPolishAfterTranscription else {
                selectedVariant = resolvedTarget.processingVariant
                markPolishingUnavailable(for: noteID)
                applyHotkeyOutputIfNeeded(for: noteID, target: resolvedTarget, mode: outputMode)
                finishHotkeySessionIfNeeded(target: hotkeyTarget == nil ? nil : resolvedTarget)
                return
            }

            let variant = resolvedTarget.processingVariant
            let polishingTargetLanguage = forceTargetLanguage ? targetLanguageCode : nil
            await polish(
                noteID,
                variants: [variant],
                targetLanguage: polishingTargetLanguage
            )

            selectedVariant = variant
            applyHotkeyOutputIfNeeded(for: noteID, target: resolvedTarget, mode: outputMode)
            finishHotkeySessionIfNeeded(target: hotkeyTarget == nil ? nil : resolvedTarget)
        } catch {
            NativeSmartScribeLog.transcription.error(
                "Gemini cloud dictation failed: \(error.localizedDescription, privacy: .public)"
            )
            noteStore.markTranscriptionFailed(
                for: noteID,
                message: error.localizedDescription,
                backendName: "Google Gemini"
            )
            if resolvedTarget != .raw {
                noteStore.markPolishingFailed(
                    for: noteID,
                    variant: resolvedTarget.processingVariant,
                    message: error.localizedDescription,
                    backendName: polishingEngineStore.activeEngine.displayName
                )
            }
            selectedVariant = resolvedTarget.processingVariant
            finishHotkeySessionIfNeeded(target: hotkeyTarget == nil ? nil : resolvedTarget)
        }
    }

    private func syncLocalizedServices() {
        audioRecorder.setTextProvider(generalSettingsStore.text)
        translationAudioRecorder.setTextProvider(generalSettingsStore.text)
    }

    private func markPolishingUnavailable(for noteID: SmartScribeNote.ID) {
        let message = polishingEngineStore.preparationSnapshot.message
            ?? generalSettingsStore.text(.chooseLocalPolishingModel)

        for variant in [ProcessingVariant.variantOne, .variantTwo] {
            noteStore.markPolishingFailed(
                for: noteID,
                variant: variant,
                message: message,
                backendName: polishingEngineStore.activeEngine.displayName
            )
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PolishingEngineStore.live())
        .environmentObject(PromptTemplateStore.live())
        .environmentObject(TranscriptionModelStore.live())
        .environmentObject(TranscriptionEngineStore.live())
        .environmentObject(HotkeySettingsStore.live())
        .environmentObject(GeneralSettingsStore.live())
        .environmentObject(UsageStatisticsStore.live())
}
