import AppKit
import NativeSmartScribeCore
import SwiftUI
import UniformTypeIdentifiers

struct NoteDetailView: View {
    let note: SmartScribeNote?
    @Binding var selectedVariant: ProcessingVariant
    @Binding var selectedText: String
    @ObservedObject var audioRecorder: AudioRecorder
    let onRecordingCompleted: (AudioRecording) -> Void
    let onPolishRequested: (SmartScribeNote.ID) -> Void
    let onMarkdownRequested: (SmartScribeNote.ID, ProcessingVariant) -> Void
    let onTextChanged: (SmartScribeNote.ID, ProcessingVariant, String) -> Void
    let onAudioFileImportRequested: (URL) -> Void
    let onBlankNoteRequested: () -> Void
    let onTranslateRequested: () -> Void
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var polishingEngineStore: PolishingEngineStore
    @EnvironmentObject private var transcriptionModelStore: TranscriptionModelStore
    @EnvironmentObject private var hotkeySettingsStore: HotkeySettingsStore
    @EnvironmentObject private var glossaryStore: GlossaryStore
    @State private var isTogglingRecording = false
    @State private var isShowingAudioImporter = false
    @State private var glossaryDraft: NoteGlossaryDraft?

    var body: some View {
        Group {
            if let note {
                VStack(spacing: 0) {
                    // Top config zone
                    VStack(alignment: .leading, spacing: 8) {
                        header(for: note)
                        topConfigBar(for: note)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                    // Content zone (expands)
                    ResultTextPanel(
                        variant: selectedVariant,
                        title: variantTitle(selectedVariant),
                        text: bindingText(for: note, variant: selectedVariant),
                        selectedText: $selectedText,
                        placeholder: placeholderText(for: note, variant: selectedVariant),
                        copyTitle: generalSettingsStore.text(.copy),
                        isEditable: true,
                        showsMarkdownAction: selectedVariant != .raw,
                        markdownActionDisabled: markdownButtonDisabled(for: note, variant: selectedVariant),
                        addToGlossaryTitle: "Add to Glossary",
                        onMarkdown: {
                            onMarkdownRequested(note.id, selectedVariant)
                        },
                        onAddToGlossary: { selectedText in
                            beginGlossaryDraft(
                                selectedText: selectedText,
                                note: note,
                                variant: selectedVariant
                            )
                        },
                        textScale: generalSettingsStore.settings.textScale,
                        textFont: generalSettingsStore.settings.textFont
                    ) {
                        copyToPasteboard(text(for: note, variant: selectedVariant))
                    }
                    .padding(.horizontal, 20)

                    // Bottom action zone
                    bottomBar(for: note)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            } else {
                emptyStateView
            }
        }
        .fileImporter(
            isPresented: $isShowingAudioImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result,
                  let url = urls.first
            else {
                return
            }

            onAudioFileImportRequested(url)
        }
        .sheet(item: $glossaryDraft) { draft in
            GlossaryDraftModal(
                selectedText: draft.selectedText,
                initialSide: draft.side,
                authorTranscriptionLanguage: glossaryStore.settings.authorTranscriptionLanguage,
                autoTranslationLanguage: glossaryStore.settings.autoTranslationLanguage,
                entries: glossaryStore.settings.entries,
                categories: glossaryStore.categories,
                onCancel: { glossaryDraft = nil },
                onSave: { request in
                    saveGlossaryDraft(request, draft: draft)
                }
            )
        }
        .onAppear {
            audioRecorder.refreshInputDeviceStatus()
        }
    }

    private func header(for note: SmartScribeNote) -> some View {
        HStack(spacing: 8) {
            Label(note.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
            if let recording = note.audioRecording {
                Text(recordingSummary(for: recording))
            }
        }
        .smartScribeFont(.caption)
        .foregroundStyle(.secondary)
    }

    private func topConfigBar(for note: SmartScribeNote) -> some View {
        ControlSurface(cornerRadius: 10) {
            VStack(spacing: 12) {
                let isCloudGemini = transcriptionModelStore.settings.backend == .geminiCloud
                
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        transcriptionModelPicker
                            .frame(minWidth: 140, idealWidth: 210, maxWidth: 240)
                        
                        polishingProviderPicker(isCloudGemini: isCloudGemini)
                            .frame(minWidth: 100, idealWidth: 125, maxWidth: 140)
                        
                        if isPolishingModelPickerAvailable {
                            polishingModelPicker
                                .frame(minWidth: 110, idealWidth: 150, maxWidth: 180)
                        }
                    }

                    HStack(spacing: 8) {
                        transcriptionModelPicker
                            .frame(minWidth: 110, idealWidth: 160, maxWidth: 200)
                        
                        polishingProviderPicker(isCloudGemini: isCloudGemini)
                            .frame(minWidth: 85, idealWidth: 105, maxWidth: 125)
                        
                        if isPolishingModelPickerAvailable {
                            polishingModelPicker
                                .frame(minWidth: 95, idealWidth: 130, maxWidth: 160)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                VariantSegmentControl(
                    note: note,
                    selectedVariant: $selectedVariant,
                    titleProvider: variantTitle
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var transcriptionModelPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            
            Menu {
                Button {
                    transcriptionModelStore.setBackend(.geminiCloud)
                    if hotkeySettingsStore.settings.target == .raw {
                        hotkeySettingsStore.settings.target = .note
                    }
                } label: {
                    Text(TranscriptionBackend.geminiCloud.displayName)
                    if transcriptionModelStore.settings.backend == .geminiCloud {
                        Image(systemName: "checkmark")
                    }
                }

                Divider()

                if downloadedTranscriptionModels.isEmpty {
                    Text(generalSettingsStore.text(.noDownloadedTranscriptionModels))
                } else {
                    ForEach(downloadedTranscriptionModels) { model in
                        Button {
                            transcriptionSelection.wrappedValue = model.id
                        } label: {
                            Text(model.displayName)
                            if transcriptionModelStore.settings.backend == .localWhisper
                                && transcriptionSelection.wrappedValue == model.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

            } label: {
                HStack {
                    Text(transcriptionMenuLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help(transcriptionModelStore.settings.backend.shortDescription)
        }
    }

    private func polishingProviderPicker(isCloudGemini: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
                .frame(width: 14)
            
            Menu {
                Button {
                    polishingSelection.wrappedValue = PolishingEngineStore.disabledEngineID
                } label: {
                    Text(generalSettingsStore.text(.polishingDisabled))
                    if polishingSelection.wrappedValue == PolishingEngineStore.disabledEngineID {
                        Image(systemName: "checkmark")
                    }
                }
                
                Divider()
                
                ForEach(downloadedPolishingModels) { model in
                    Button {
                        polishingSelection.wrappedValue = Self.localPolishingTag(for: model.id)
                    } label: {
                        Text(model.displayName)
                        if polishingSelection.wrappedValue == Self.localPolishingTag(for: model.id) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                if !downloadedPolishingModels.isEmpty && !apiPolishingDescriptors.isEmpty {
                    Divider()
                }
                
                ForEach(apiPolishingDescriptors) { descriptor in
                    Button {
                        polishingSelection.wrappedValue = descriptor.id
                    } label: {
                        Text(polishingDescriptorTitle(for: descriptor))
                        if polishingSelection.wrappedValue == descriptor.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            } label: {
                HStack {
                    Text(currentPolishingProviderDisplayName())
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .disabled(isCloudGemini)
            .opacity(isCloudGemini ? 0.6 : 1.0)
            .help(isCloudGemini ? generalSettingsStore.text(.cloudDictationUsesGemini) : "")
        }
    }

    private var polishingModelPicker: some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu")
                .foregroundStyle(.secondary)
                .frame(width: 14)
            
            Menu {
                ForEach(currentProviderModelOptions) { option in
                    Button {
                        selectPolishingModel(id: option.id)
                    } label: {
                        Text(option.displayName)
                        if isPolishingModelSelected(id: option.id) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            } label: {
                HStack {
                    Text(currentPolishingModelDisplayName())
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func bottomBar(for note: SmartScribeNote) -> some View {
        ControlSurface(cornerRadius: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    ModernRecordButton(
                        isRecording: audioRecorder.isRecording,
                        isDisabled: isTogglingRecording,
                        action: toggleRecording
                    )
                    .help(audioRecorder.isRecording ? generalSettingsStore.text(.stopRecording) : generalSettingsStore.text(.record))

                    AudioInputDeviceStatusPill(audioRecorder: audioRecorder, compact: true)
                        .frame(minWidth: 70, idealWidth: 150, maxWidth: 210)
                }

                InAppSpectrumMeter(
                    bands: audioRecorder.frequencyBands,
                    isRecording: audioRecorder.isRecording,
                    isTranscribing: isImportedAudioTranscribing(note),
                    isProcessing: isPolishing(note),
                    elapsedTime: audioRecorder.elapsedTime
                )
                .frame(minWidth: 60, idealWidth: 200, maxWidth: 260)
                .frame(height: 42)
                .layoutPriority(0)

                Spacer(minLength: 2)

                HStack(spacing: 5) {
                    toolbarIconButton(
                        systemImage: "square.and.arrow.down",
                        helpText: generalSettingsStore.text(.importAudio)
                    ) {
                        isShowingAudioImporter = true
                    }

                    toolbarIconButton(
                        systemImage: "translate",
                        helpText: generalSettingsStore.text(.translate)
                    ) {
                        onTranslateRequested()
                    }

                    toolbarIconButton(
                        systemImage: "wand.and.sparkles",
                        helpText: generalSettingsStore.text(.polish),
                        isDisabled: polishButtonDisabled
                    ) {
                        onPolishRequested(note.id)
                    }
                    
                    Divider()
                        .frame(height: 20)
                        .padding(.horizontal, 2)
                        
                    SettingsLink {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(SmartScribeToolbarButtonStyle(size: 34))
                    .labelStyle(.iconOnly)
                    .help(generalSettingsStore.text(.settings))
                }
                .layoutPriority(1)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.03))
                        .frame(width: 96, height: 96)
                    Circle()
                        .fill(.white.opacity(0.04))
                        .frame(width: 72, height: 72)
                    Image(systemName: audioRecorder.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(audioRecorder.isRecording ? .red : .accentColor)
                }

                Text(generalSettingsStore.text(.noNoteSelected))
                    .smartScribeFont(.title2, weight: .semibold)

                Text(generalSettingsStore.text(.createOrSelectNote))
                    .smartScribeFont(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            HStack(spacing: 0) {
                emptyStateActionButton(
                    title: audioRecorder.isRecording
                        ? generalSettingsStore.text(.stopRecording)
                        : generalSettingsStore.text(.record),
                    systemImage: audioRecorder.isRecording ? "stop.circle.fill" : "record.circle.fill",
                    tint: .red,
                    isDisabled: isTogglingRecording
                ) {
                    toggleRecording()
                }

                emptyStateDivider

                emptyStateActionButton(
                    title: generalSettingsStore.text(.blankNote),
                    systemImage: "square.and.pencil",
                    isDisabled: audioRecorder.isRecording
                ) {
                    onBlankNoteRequested()
                }

                emptyStateDivider

                emptyStateActionButton(
                    title: generalSettingsStore.text(.importAudio),
                    systemImage: "square.and.arrow.down",
                    isDisabled: audioRecorder.isRecording
                ) {
                    isShowingAudioImporter = true
                }
            }
            .padding(5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.07), lineWidth: 0.5))

            AudioInputDeviceStatusPill(audioRecorder: audioRecorder)
                .frame(maxWidth: 360)

            if audioRecorder.isRecording {
                InAppSpectrumMeter(
                    bands: audioRecorder.frequencyBands,
                    isRecording: true,
                    isTranscribing: false,
                    isProcessing: false,
                    elapsedTime: audioRecorder.elapsedTime
                )
                .frame(width: 320, height: 44)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            Spacer()

            if let errorMessage = audioRecorder.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .smartScribeFont(.caption)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 16)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyStateActionButton(
        title: String,
        systemImage: String,
        tint: Color? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .smartScribeFont(.caption, weight: .medium)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(minWidth: 120)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? .primary)
        .opacity(isDisabled ? 0.3 : 1)
        .contentShape(Capsule())
        .disabled(isDisabled)
    }

    private var emptyStateDivider: some View {
        Divider()
            .frame(height: 22)
            .padding(.horizontal, 2)
    }

    private var downloadedTranscriptionModels: [TranscriptionModelDescriptor] {
        transcriptionModelStore.models.filter {
            transcriptionModelStore.installationState(for: $0).isDownloaded
        }
    }

    private var transcriptionMenuLabel: String {
        switch transcriptionModelStore.settings.backend {
        case .geminiCloud:
            return TranscriptionBackend.geminiCloud.displayName
        case .localWhisper:
            if let id = transcriptionModelStore.settings.activeModelID,
               let name = downloadedTranscriptionModels.first(where: { $0.id == id })?.displayName {
                return name
            }
            return generalSettingsStore.text(.noLocalModelSelected)
        }
    }

    private var downloadedPolishingModels: [PolishingModelDescriptor] {
        let downloadedCatalog = polishingEngineStore.models.filter {
            polishingEngineStore.installationState(for: $0).isDownloaded
        }
        // Custom models always exist locally — no download needed
        return downloadedCatalog + polishingEngineStore.customModels
    }

    private var apiPolishingDescriptors: [PolishingEngineDescriptor] {
        polishingEngineStore.descriptors.filter {
            $0.id != PolishingEngineStore.disabledEngineID
                && $0.id != PolishingEngineStore.mlxSwiftEngineID
                && $0.id != "local-rule-based-polish"
        }
    }

    private var transcriptionSelection: Binding<String> {
        Binding(
            get: { transcriptionModelStore.settings.activeModelID ?? "" },
            set: { modelID in
                guard !modelID.isEmpty,
                      let model = transcriptionModelStore.models.first(where: { $0.id == modelID })
                else {
                    transcriptionModelStore.deactivate()
                    return
                }

                // Picking a Whisper model always switches back to local backend.
                transcriptionModelStore.setBackend(.localWhisper)
                transcriptionModelStore.activate(model)
            }
        )
    }

    private var polishingSelection: Binding<String> {
        Binding(
            get: {
                if polishingEngineStore.selectedEngineID == PolishingEngineStore.mlxSwiftEngineID,
                   let modelID = polishingEngineStore.activeModel?.id {
                    return Self.localPolishingTag(for: modelID)
                }

                return polishingEngineStore.selectedEngineID
            },
            set: { selection in
                if selection == PolishingEngineStore.disabledEngineID {
                    polishingEngineStore.selectedEngineID = selection
                } else if let modelID = Self.localPolishingModelID(from: selection),
                          let model = polishingEngineStore.allModels.first(where: { $0.id == modelID }) {
                    polishingEngineStore.activate(model)
                } else {
                    polishingEngineStore.selectedEngineID = selection
                }
            }
        )
    }

    private static func localPolishingTag(for modelID: String) -> String {
        "local-polishing:\(modelID)"
    }

    private static func localPolishingModelID(from tag: String) -> String? {
        guard tag.hasPrefix("local-polishing:") else { return nil }
        return String(tag.dropFirst("local-polishing:".count))
    }

    private func polishingDescriptorTitle(for descriptor: PolishingEngineDescriptor) -> String {
        switch descriptor.id {
        case "local-rule-based-polish":
            generalSettingsStore.text(.quickLocalCleanup)
        case PolishingEngineStore.mlxSwiftEngineID:
            generalSettingsStore.text(.localMLXModel)
        default:
            descriptor.displayName
        }
    }

    @ViewBuilder
    private func transcriptionStatus(for status: TranscriptionStatus) -> some View {
        switch status.phase {
        case .idle:
            EmptyView()
        case .pending:
            statusPill(
                text: generalSettingsStore.text(.waitingToTranscribe),
                systemImage: "clock",
                foregroundStyle: AnyShapeStyle(.secondary)
            )
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(generalSettingsStore.formattedText(.transcribingWith, status.backendName ?? generalSettingsStore.text(.localEngine)))
                    .foregroundStyle(.secondary)
            }
            .smartScribeFont(.caption)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        case .completed:
            statusPill(
                text: generalSettingsStore.formattedText(.transcribedWith, status.backendName ?? generalSettingsStore.text(.localEngine)),
                systemImage: "checkmark.circle",
                foregroundStyle: AnyShapeStyle(.secondary)
            )
        case .failed:
            statusPill(
                text: status.message ?? generalSettingsStore.text(.transcriptionFailed),
                systemImage: "exclamationmark.triangle",
                foregroundStyle: AnyShapeStyle(.orange)
            )
        }
    }

    private func statusPill(
        text: String,
        systemImage: String,
        foregroundStyle: AnyShapeStyle
    ) -> some View {
        Label(text, systemImage: systemImage)
            .smartScribeFont(.caption)
            .foregroundStyle(foregroundStyle)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func polishingOverview(for note: SmartScribeNote) -> some View {
        HStack(spacing: 8) {
            ForEach([ProcessingVariant.variantOne, .variantTwo]) { variant in
                let status = note.polishingStatus(for: variant)

                Button {
                    selectedVariant = variant
                } label: {
                    Label(
                        "\(variantTitle(variant)): \(status.shortLabel(textProvider: generalSettingsStore.text))",
                        systemImage: status.systemImage
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(status.foregroundStyle)
                .help(generalSettingsStore.formattedText(.showVariant, variant.title))
            }
        }
    }

    private func isPolishing(_ note: SmartScribeNote) -> Bool {
        [ProcessingVariant.variantOne, .variantTwo].contains { variant in
            note.polishingStatus(for: variant).phase == .polishing
        }
    }

    private func isImportedAudioTranscribing(_ note: SmartScribeNote) -> Bool {
        note.transcriptionStatus.phase == .transcribing
            && note.audioRecording?.source == .importedFile
    }

    @ViewBuilder
    private func polishingStatus(for note: SmartScribeNote, variant: ProcessingVariant) -> some View {
        if variant != .raw {
            let status = note.polishingStatus(for: variant)

            switch status.phase {
            case .idle:
                EmptyView()
            case .pending:
                statusPill(
                    text: generalSettingsStore.formattedText(.waitingToPolish, variantTitle(variant)),
                    systemImage: "clock",
                    foregroundStyle: AnyShapeStyle(.secondary)
                )
            case .polishing:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(generalSettingsStore.formattedText(.polishingWith, variantTitle(variant), status.backendName ?? generalSettingsStore.text(.localEngine)))
                        .foregroundStyle(.secondary)
                }
                .smartScribeFont(.caption)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            case .completed:
                statusPill(
                    text: generalSettingsStore.formattedText(.polishedWith, status.backendName ?? generalSettingsStore.text(.localEngine)),
                    systemImage: "checkmark.circle",
                    foregroundStyle: AnyShapeStyle(.secondary)
                )
        case .failed:
            statusPill(
                text: status.message ?? generalSettingsStore.text(.polishingFailed),
                systemImage: "exclamationmark.triangle",
                foregroundStyle: AnyShapeStyle(.orange)
            )
            }
        }
    }

    private var copyButtonDisabled: Bool {
        guard let note else { return true }
        return text(for: note, variant: selectedVariant)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var polishButtonDisabled: Bool {
        guard let note else { return true }
        guard polishingEngineStore.selectedEngineID != PolishingEngineStore.disabledEngineID else {
            return true
        }
        guard !note.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }

        return [.variantOne, .variantTwo].contains { variant in
            note.polishingStatus(for: variant).phase == .polishing
        }
    }

    private func markdownButtonDisabled(for note: SmartScribeNote, variant: ProcessingVariant) -> Bool {
        guard variant != .raw else { return true }
        guard !text(for: note, variant: variant).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        guard polishingEngineStore.selectedEngineID != PolishingEngineStore.disabledEngineID else {
            return true
        }
        guard polishingEngineStore.selectedEngineID != "local-rule-based-polish" else {
            return true
        }

        return note.polishingStatus(for: variant).phase == .polishing
    }

    private func placeholderText(for note: SmartScribeNote, variant: ProcessingVariant) -> String {
        switch variant {
        case .raw:
            if note.transcriptionStatus.phase == .transcribing {
                return generalSettingsStore.text(.transcribing)
            }
            return generalSettingsStore.text(.noTranscriptYet)
        case .variantOne, .variantTwo:
            let status = note.polishingStatus(for: variant)
            switch status.phase {
            case .idle:
                return generalSettingsStore.text(.noPolishedTextYet)
            case .pending:
                return generalSettingsStore.text(.waitingToPolishShort)
            case .polishing:
                return generalSettingsStore.text(.polishing)
            case .completed:
                return generalSettingsStore.text(.noPolishedTextReturned)
            case .failed:
                return status.message ?? generalSettingsStore.text(.polishingFailed)
            }
        }
    }

    private func text(for note: SmartScribeNote, variant: ProcessingVariant) -> String {
        switch variant {
        case .raw:
            note.rawText
        case .variantOne:
            note.polishedVariantOne
        case .variantTwo:
            note.polishedVariantTwo
        }
    }

    private func bindingText(for note: SmartScribeNote, variant: ProcessingVariant) -> Binding<String> {
        Binding(
            get: { text(for: note, variant: variant) },
            set: { newValue in
                onTextChanged(note.id, variant, newValue)
            }
        )
    }

    private func copyToPasteboard(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func beginGlossaryDraft(
        selectedText: String,
        note: SmartScribeNote,
        variant: ProcessingVariant
    ) {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return }
        glossaryDraft = NoteGlossaryDraft(
            noteID: note.id,
            variant: variant,
            selectedText: selected,
            side: .source
        )
    }

    private func saveGlossaryDraft(
        _ request: GlossaryDraftSaveRequest,
        draft: NoteGlossaryDraft
    ) {
        if let existingEntryID = request.existingEntryID {
            glossaryStore.addGlossaryVariants(
                to: existingEntryID,
                variants: [request.selectedText]
            )
        } else {
            glossaryStore.createGlossaryEntryFromReview(
                selectedText: request.selectedText,
                source: request.source,
                translation: request.translation,
                category: request.category,
                side: request.side
            )
        }

        glossaryDraft = nil

        guard let note, note.id == draft.noteID else { return }
        let target: GlossaryTextRewriter.Target = request.side == .translation ? .translation : .source
        let rewritten = glossaryStore.apply(
            to: text(for: note, variant: draft.variant),
            target: target
        )
        guard rewritten.count > 0 else { return }
        onTextChanged(draft.noteID, draft.variant, rewritten.text)
    }

    private var modelOptionsProvider: PolishingModelOptionsProvider {
        PolishingModelOptionsProvider(apiSettings: polishingEngineStore.apiSettings)
    }

    private var activeProviderKind: APIProviderKind? {
        if transcriptionModelStore.settings.backend == .geminiCloud {
            return .google
        }
        return APIProviderKind(polishingEngineID: polishingEngineStore.selectedEngineID)
    }

    private var isPolishingModelPickerAvailable: Bool {
        if transcriptionModelStore.settings.backend == .geminiCloud {
            return true
        }
        if activeProviderKind != nil { return true }
        if polishingEngineStore.selectedEngineID == PolishingEngineStore.mlxSwiftEngineID && !downloadedPolishingModels.isEmpty {
            return true
        }
        return false
    }

    private func currentPolishingProviderDisplayName() -> String {
        if transcriptionModelStore.settings.backend == .geminiCloud {
            return "Google"
        }
        let currentId = polishingSelection.wrappedValue
        if currentId == PolishingEngineStore.disabledEngineID {
            return generalSettingsStore.text(.polishingDisabled)
        }
        if currentId == "local-rule-based-polish" {
            return generalSettingsStore.text(.quickLocalCleanup)
        }
        if polishingEngineStore.selectedEngineID == PolishingEngineStore.mlxSwiftEngineID {
            return generalSettingsStore.text(.localMLXModel)
        }
        if let descriptor = apiPolishingDescriptors.first(where: { $0.id == currentId }) {
            return descriptor.displayName
        }
        return generalSettingsStore.text(.provider)
    }

    private func currentPolishingModelDisplayName() -> String {
        if let kind = activeProviderKind {
            let currentID = polishingEngineStore.apiSettings.configuration(for: kind).textModel
            let name = modelOptionsProvider.modelDisplayName(id: currentID, kind: kind)
            return name.isEmpty ? generalSettingsStore.text(.defaultModelName) : name
        }
        if polishingEngineStore.selectedEngineID == PolishingEngineStore.mlxSwiftEngineID,
           let model = polishingEngineStore.activeModel {
            return model.displayName
        }
        return generalSettingsStore.text(.polishingModel)
    }

    private var currentProviderModelOptions: [PolishingModelOption] {
        if let kind = activeProviderKind {
            return modelOptionsProvider.providerModelOptions(for: kind, favorites: FavoriteModelsStore.loadFavorites())
        }
        if polishingEngineStore.selectedEngineID == PolishingEngineStore.mlxSwiftEngineID {
            return downloadedPolishingModels.map { PolishingModelOption(id: $0.id, displayName: $0.displayName) }
        }
        return []
    }

    private func isPolishingModelSelected(id: String) -> Bool {
        if let kind = activeProviderKind {
            return polishingEngineStore.apiSettings.configuration(for: kind).textModel == id
        }
        if polishingEngineStore.selectedEngineID == PolishingEngineStore.mlxSwiftEngineID {
            return polishingEngineStore.activeModel?.id == id
        }
        return false
    }

    private func selectPolishingModel(id: String) {
        if let kind = activeProviderKind {
            var config = polishingEngineStore.apiSettings.configuration(for: kind)
            config.textModel = id
            polishingEngineStore.updateAPIConfiguration(config, for: kind)
        } else if polishingEngineStore.selectedEngineID == PolishingEngineStore.mlxSwiftEngineID {
            if let model = polishingEngineStore.allModels.first(where: { $0.id == id }) {
                polishingEngineStore.activate(model)
            }
        }
    }


    private func toggleRecording() {
        guard !isTogglingRecording else { return }

        isTogglingRecording = true
        Task { @MainActor in
            defer { isTogglingRecording = false }

            if audioRecorder.isRecording {
                if let recording = audioRecorder.stop() {
                    AudioCuePlayer.shared.play(.finish, settings: generalSettingsStore.settings.overlay)
                    onRecordingCompleted(recording)
                }
            } else {
                await audioRecorder.start()
                if audioRecorder.isRecording {
                    AudioCuePlayer.shared.play(.start, settings: generalSettingsStore.settings.overlay)
                }
            }
        }
    }

    private func recordingSummary(for recording: AudioRecording) -> String {
        let channels = recording.channelCount == 1
            ? generalSettingsStore.text(.monoChannel)
            : generalSettingsStore.formattedText(.channelsCount, recording.channelCount)
        return "\(durationString(recording.duration)) · \(Int(recording.sampleRate)) Hz · \(channels)"
    }

    private func durationString(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func variantTitle(_ variant: ProcessingVariant) -> String {
        switch variant {
        case .raw:
            generalSettingsStore.text(.raw)
        case .variantOne:
            generalSettingsStore.text(.variantOne)
        case .variantTwo:
            generalSettingsStore.text(.variantTwo)
        }
    }

    @ViewBuilder
    private func toolbarIconButton(
        systemImage: String,
        helpText: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(SmartScribeToolbarButtonStyle())
        .labelStyle(.iconOnly)
        .disabled(isDisabled)
        .help(helpText)
    }
}

private struct ResultTextPanel: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var promptTemplateStore: PromptTemplateStore
    let variant: ProcessingVariant
    let title: String
    @Binding var text: String
    @Binding var selectedText: String
    let placeholder: String
    let copyTitle: String
    let isEditable: Bool
    let showsMarkdownAction: Bool
    let markdownActionDisabled: Bool
    let addToGlossaryTitle: String
    let onMarkdown: () -> Void
    let onAddToGlossary: (String) -> Void
    let textScale: Double
    let textFont: TextFontPreference
    let onCopy: () -> Void

    @State private var isCopied = false

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label(title, systemImage: variant.systemImage)
                    .smartScribeFont(.headline, weight: .semibold)

                Spacer()

                if variant != .raw {
                    ResultPromptSlotSelector(
                        variant: variant,
                        selectedSlot: Binding(
                            get: { promptTemplateStore.activeSlot(for: variant) },
                            set: { promptTemplateStore.setActiveSlot($0, for: variant) }
                        )
                    )
                }

                if showsMarkdownAction {
                    Button(action: onMarkdown) {
                        Text("M")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .buttonStyle(SmartScribeToolbarButtonStyle(size: 28))
                    .disabled(markdownActionDisabled)
                    .help(generalSettingsStore.text(.generateMarkdown))
                }

                Button {
                    onCopy()
                    withAnimation(.easeInOut(duration: 0.15)) { isCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.15)) { isCopied = false }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundStyle(isCopied ? .green : .primary)
                        .animation(.easeInOut(duration: 0.15), value: isCopied)
                }
                .buttonStyle(SmartScribeToolbarButtonStyle(size: 28))
                .labelStyle(.iconOnly)
                .disabled(isEmpty && !isCopied)
                .help(isCopied ? generalSettingsStore.text(.copied) : copyTitle)
            }

            SelectableTextView(
                text: $text,
                selectedText: $selectedText,
                placeholder: placeholder,
                isEditable: isEditable,
                selectionActionTitle: addToGlossaryTitle,
                onSelectionAction: onAddToGlossary,
                textScale: textScale,
                textFont: textFont
            )
            .frame(maxWidth: .infinity, minHeight: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.06), lineWidth: 0.5)
            }
        }
    }
}

private struct NoteGlossaryDraft: Identifiable, Equatable {
    let id = UUID()
    var noteID: SmartScribeNote.ID
    var variant: ProcessingVariant
    var selectedText: String
    var side: GlossaryDraftSide
}

private struct ResultPromptSlotSelector: View {
    @EnvironmentObject private var promptTemplateStore: PromptTemplateStore
    let variant: ProcessingVariant
    @Binding var selectedSlot: PromptSlot

    var body: some View {
        HStack(spacing: 3) {
            ForEach(PromptSlot.allCases) { slot in
                Button {
                    selectedSlot = slot
                } label: {
                    Text(slot.shortTitle)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedSlot == slot ? .green : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selectedSlot == slot ? Color.green.opacity(0.16) : Color.white.opacity(0.04))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(selectedSlot == slot ? Color.green.opacity(0.55) : Color.white.opacity(0.10), lineWidth: 0.75)
                }
                .help(promptTemplateStore.slotName(in: slot, for: variant))
            }
        }
        .padding(.trailing, 2)
    }
}

private struct VariantSegmentControl: View {
    let note: SmartScribeNote
    @Binding var selectedVariant: ProcessingVariant
    let titleProvider: (ProcessingVariant) -> String
    @Namespace private var tabAnimation

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ProcessingVariant.allCases) { variant in
                Button {
                    withAnimation(.snappy(duration: 0.3)) {
                        selectedVariant = variant
                    }
                } label: {
                    Label(titleProvider(variant), systemImage: systemImage(for: variant))
                        .smartScribeFont(.caption, weight: .medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .frame(minWidth: 104)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedVariant == variant ? .primary : .secondary)
                .background {
                    if selectedVariant == variant {
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .matchedGeometryEffect(id: "activeVariantTab", in: tabAnimation)
                    }
                }
                .foregroundStyle(selectedVariant == variant ? .green : .secondary)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.15), in: Capsule())
        .overlay(
            Capsule().stroke(.white.opacity(0.04), lineWidth: 0.5)
        )
    }

    private func systemImage(for variant: ProcessingVariant) -> String {
        switch variant {
        case .raw:
            note.transcriptionStatus.phase == .completed ? "checkmark.circle.fill" : note.transcriptionStatus.systemImage
        case .variantOne, .variantTwo:
            note.polishingStatus(for: variant).systemImage
        }
    }
}

private struct InAppSpectrumMeter: View {
    let bands: [Float]
    let isRecording: Bool
    let isTranscribing: Bool
    let isProcessing: Bool
    let elapsedTime: TimeInterval

    private var isActive: Bool {
        isRecording || isTranscribing || isProcessing
    }

    private var tint: Color {
        if isProcessing {
            return .green
        }
        if isTranscribing {
            return .blue
        }
        return isRecording ? .red : .secondary
    }

    private var usesSyntheticWave: Bool {
        isProcessing || isTranscribing
    }

    private var elapsedLabel: String {
        let totalSeconds = max(0, Int(elapsedTime.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: 10) {
            DotSpectrumView(
                bands: bands,
                color: tint,
                isActive: isActive,
                isProcessing: usesSyntheticWave,
                dotCount: 30,
                noiseFloor: 0.08,
                amplitude: 0.96,
                sensitivity: 1.45,
                silenceThreshold: 0.035
            )
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)

            if isRecording {
                Text(elapsedLabel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .smartScribeFont(.caption, weight: .medium)
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
        }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 0.8)
            }
    }
}

private extension PolishingStatus {
    func shortLabel(textProvider: (AppTextKey) -> String) -> String {
        switch phase {
        case .idle:
            textProvider(.idleStatus)
        case .pending:
            textProvider(.pendingStatus)
        case .polishing:
            textProvider(.runningStatus)
        case .completed:
            textProvider(.doneStatus)
        case .failed:
            textProvider(.failedStatus)
        }
    }

    var systemImage: String {
        switch phase {
        case .idle:
            "circle"
        case .pending:
            "clock"
        case .polishing:
            "wand.and.sparkles"
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var foregroundStyle: Color {
        switch phase {
        case .idle, .pending:
            .secondary
        case .polishing:
            .accentColor
        case .completed:
            .green
        case .failed:
            .orange
        }
    }
}

private extension TranscriptionStatus {
    var systemImage: String {
        switch phase {
        case .idle:
            "circle"
        case .pending:
            "clock"
        case .transcribing:
            "waveform"
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }
}
