import NativeSmartScribeCore
import SwiftUI

/// API Providers tab — Redesigned VaniScript-style minimalist & compact layout:
/// 1) Provider dropdown with active status indicator
/// 2) OpenRouter balance banner (green/yellow/red) + budget slider
/// 3) Qwen subscription text model gating (6 text models)
/// 4) Equal-width (142px) fixed action buttons (no jittering or size jumps on click)
/// 5) Dynamic model context length and token pricing chips
/// 6) Token usage statistics section
@MainActor
struct APIProvidersSettingsView: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var polishingEngineStore: PolishingEngineStore
    @EnvironmentObject private var usageStatisticsStore: UsageStatisticsStore

    /// Selected provider kind in the UI dropdown.
    @State private var selectedProviderKind: APIProviderKind = .google

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard

                ProviderDetailCard(
                    kind: selectedProviderKind,
                    configuration: configurationBinding(for: selectedProviderKind)
                )

                UsageInlineCard(
                    providerKind: selectedProviderKind,
                    activeModelID: polishingEngineStore.apiSettings.configuration(for: selectedProviderKind).textModel
                )
            }
            .padding(16)
        }
        .onAppear {
            if let kind = APIProviderKind(polishingEngineID: polishingEngineStore.selectedEngineID),
               APIProviderKind.polishingUICases.contains(kind) {
                selectedProviderKind = kind
            } else {
                selectedProviderKind = .google
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(generalSettingsStore.text(.cloudProvider))
                        .font(.system(size: 13, weight: .semibold))
                    Text(generalSettingsStore.text(.cloudProviderSubtitle))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("", selection: $selectedProviderKind) {
                    ForEach(APIProviderKind.polishingUICases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)

                if isCurrentEngineSelected {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(generalSettingsStore.text(.active))
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.14), in: Capsule())
                    .foregroundStyle(.green)
                }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        }
    }

    private var isCurrentEngineSelected: Bool {
        polishingEngineStore.selectedEngineID == selectedProviderKind.polishingEngineID
    }

    private func configurationBinding(for kind: APIProviderKind) -> Binding<APIProviderConfiguration> {
        Binding(
            get: { polishingEngineStore.apiSettings.configuration(for: kind) },
            set: { polishingEngineStore.updateAPIConfiguration($0, for: kind) }
        )
    }
}

// MARK: - Provider Detail Card

private struct ProviderDetailCard: View {
    let kind: APIProviderKind
    @Binding var configuration: APIProviderConfiguration

    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var polishingEngineStore: PolishingEngineStore

    @State private var isAPIKeyVisible = false
    @State private var availableModels: [CloudRemoteModel] = []
    @State private var isLoadingModels = false
    @State private var modelsError: String?
    @State private var modelsFetchTask: Task<Void, Never>?
    @State private var openRouterBalance: CloudProviderModelCatalog.OpenRouterBalance?
    @State private var isLoadingBalance = false
    @State private var showModelPicker = false
    @State private var budgetLimit: Double = 5.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title Header
            HStack {
                Text(kind.displayName)
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                if let url = kind.getAPIKeyURL {
                    Link(destination: url) {
                        Label(generalSettingsStore.text(.getAPIKey), systemImage: "key")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                }
            }

            Divider()

            // OpenRouter Balance Card
            if kind == .openRouter {
                openRouterBalanceSection
                Divider()
            }

            // Qwen Banner
            if kind == .qwen {
                qwenBannerSection
                Divider()
            }

            // Custom Base URL / Endpoint
            if kind == .custom {
                VStack(alignment: .leading, spacing: 4) {
                    Text(generalSettingsStore.text(.baseURLLabel))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(generalSettingsStore.text(.baseURLPlaceholder), text: $configuration.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
            } else if kind == .openRouter {
                HStack {
                    Text(generalSettingsStore.text(.endpoint))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(resolvedBaseURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            // API Key Row
            apiKeyRow

            if let keyIssue {
                Text(keyIssue)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            // Model Selection & Action Row
            modelAndActionRow

            if let modelsError {
                Text(modelsError)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Model Metadata Chips Row
            modelMetaRow
        }
        .padding(14)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        }
        .sheet(isPresented: $showModelPicker) {
            SmartModelPickerSheet(
                providerName: kind.displayName,
                models: availableModels,
                selectedModelID: $configuration.textModel,
                isPresented: $showModelPicker
            )
            .frame(minWidth: 480, minHeight: 420)
        }
        .onAppear {
            scheduleModelsFetch(force: true)
            refreshBalance()
        }
        .onChange(of: kind) { _, _ in
            availableModels = []
            modelsError = nil
            openRouterBalance = nil
            scheduleModelsFetch(force: true)
            refreshBalance()
        }
        .onChange(of: configuration.apiKey) { _, _ in
            scheduleModelsFetch()
            refreshBalance()
        }
        .onChange(of: configuration.apiKeys) { _, _ in
            scheduleModelsFetch()
            refreshBalance()
        }
        .onChange(of: configuration.baseURL) { _, _ in
            if kind == .custom { scheduleModelsFetch() }
        }
        .onDisappear {
            modelsFetchTask?.cancel()
        }
    }

    private var resolvedBaseURL: String {
        let configured = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty { return configured }
        return kind.defaultBaseURL
    }

    // MARK: - OpenRouter Balance Section

    private var openRouterBalanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(generalSettingsStore.text(.accountBalance))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if isLoadingBalance {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(generalSettingsStore.text(.fetchingBalance))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    } else if let balance = openRouterBalance {
                        Text(String(format: generalSettingsStore.text(.balanceRemaining), balance.remainingUSD))
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(balanceColor(for: balance.remainingUSD))
                    } else {
                        Text("—")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Button {
                    refreshBalance()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(isLoadingBalance || !canFetchModels)
                .help(generalSettingsStore.text(.refreshOpenRouterBalance))
            }

            // Budget Slider Control
            HStack(spacing: 12) {
                Text(generalSettingsStore.text(.budgetLimit))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Slider(value: $budgetLimit, in: 1...100, step: 1)
                    .controlSize(.small)

                Text(String(format: "$%.0f.00", budgetLimit))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, alignment: .trailing)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
    }

    private func balanceColor(for remainingUSD: Double) -> Color {
        if remainingUSD > 5.0 {
            return .green
        } else if remainingUSD > 0 {
            return .yellow
        } else {
            return .red
        }
    }

    // MARK: - Qwen Subscription Banner

    private var qwenBannerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 14))
            Text(generalSettingsStore.text(.qwenSubscriptionBanner))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - API Key Row

    private var apiKeyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(configuration.apiKeys.count > 1 ? generalSettingsStore.formattedText(.apiKeysCountLabel, "\(configuration.apiKeys.count)") : generalSettingsStore.text(.apiKeyLabel))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if configuration.apiKeys.count > 1 {
                    Menu {
                        Button {
                            configuration.enableAllKeys()
                        } label: {
                            Label(generalSettingsStore.text(.enableAllKeys), systemImage: "checkmark.circle")
                        }

                        Divider()

                        ForEach(0..<configuration.apiKeys.count, id: \.self) { idx in
                            Button {
                                configuration.disableAllKeysExcept(at: idx)
                            } label: {
                                let keyPreview = String(configuration.cleanKey(at: idx).suffix(6))
                                Label(generalSettingsStore.formattedText(.testOnlyKey, "\(idx + 1)") + (keyPreview.isEmpty ? "" : " (…\(keyPreview))"), systemImage: "bolt.fill")
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11))
                            Text(generalSettingsStore.text(.manageKeys))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Color.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .help(generalSettingsStore.text(.manageKeysHelp))
                }

                if configuration.apiKeys.count < 10 {
                    Button {
                        if configuration.apiKeys.isEmpty {
                            configuration.apiKeys = ["", ""]
                        } else {
                            configuration.addKey("")
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text(generalSettingsStore.text(.addKey))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                    .help(generalSettingsStore.text(.addKeyHelp))
                }
            }

            let keyCount = max(1, configuration.apiKeys.count)
            ForEach(0..<keyCount, id: \.self) { index in
                let isDisabled = configuration.isKeyDisabled(at: index)
                HStack(spacing: 8) {
                    // Enable/Disable Toggle Power Button
                    Button {
                        configuration.toggleKeyDisabled(at: index)
                    } label: {
                        Image(systemName: isDisabled ? "circle.slash" : "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isDisabled ? Color.secondary.opacity(0.5) : Color.green)
                    }
                    .buttonStyle(.borderless)
                    .help(isDisabled ? generalSettingsStore.text(.keyDisabledHelp) : generalSettingsStore.text(.keyActiveHelp))

                    Group {
                        if isAPIKeyVisible {
                            TextField(
                                keyCount > 1 ? (index == 0 ? generalSettingsStore.formattedText(.apiKeyNumberPrimary, "\(index + 1)") : generalSettingsStore.formattedText(.apiKeyNumber, "\(index + 1)")) : generalSettingsStore.text(.enterAPIKey),
                                text: keyBinding(at: index)
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                        } else {
                            SecureField(
                                keyCount > 1 ? (index == 0 ? generalSettingsStore.formattedText(.apiKeyNumberPrimary, "\(index + 1)") : generalSettingsStore.formattedText(.apiKeyNumber, "\(index + 1)")) : generalSettingsStore.text(.enterAPIKey),
                                text: keyBinding(at: index)
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        }
                    }
                    .opacity(isDisabled ? 0.45 : 1.0)

                    if isDisabled {
                        Text(generalSettingsStore.text(.disabled))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    }

                    Button {
                        isAPIKeyVisible.toggle()
                    } label: {
                        Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(isAPIKeyVisible ? generalSettingsStore.text(.hideAPIKey) : generalSettingsStore.text(.showAPIKey))

                    if keyCount > 1 {
                        Button {
                            configuration.removeKey(at: index)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.borderless)
                        .help(generalSettingsStore.text(.removeAPIKey))
                    }
                }
            }
        }
    }

    private func keyBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                if configuration.apiKeys.indices.contains(index) {
                    return configuration.cleanKey(at: index)
                }
                return ""
            },
            set: { newValue in
                if configuration.apiKeys.isEmpty {
                    configuration.apiKeys = [newValue]
                } else if configuration.apiKeys.indices.contains(index) {
                    configuration.updateKey(newValue, at: index)
                }
            }
        )
    }

    // MARK: - Model Row & Fixed-Width Action Button

    private var modelAndActionRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(generalSettingsStore.text(.polishingModelField))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if kind == .qwen {
                    // Qwen subscription inline picker
                    Picker("", selection: $configuration.textModel) {
                        ForEach(CloudProviderModelCatalog.qwenSubscriptionModels) { model in
                            Text(model.id).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                } else if !availableModels.isEmpty {
                    Button {
                        showModelPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentModelID.isEmpty ? generalSettingsStore.text(.selectModel) : currentModelID)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(currentModelID.isEmpty ? .secondary : .primary)

                            Spacer(minLength: 4)

                            Text("\(availableModels.count)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                                .foregroundStyle(.secondary)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    TextField(kind.defaultTextModel.isEmpty ? generalSettingsStore.text(.modelID) : kind.defaultTextModel, text: $configuration.textModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }

                if isLoadingModels {
                    ProgressView().controlSize(.small)
                }

                if kind != .qwen {
                    Button {
                        scheduleModelsFetch(force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canFetchModels || isLoadingModels)
                    .help(generalSettingsStore.text(.refreshModelList))
                }

                Spacer(minLength: 4)

                // Fixed Width Action Button (142px) — Prevents any shift / jittering on click!
                Button {
                    polishingEngineStore.selectAPIProvider(kind)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isSelectedEngine ? "checkmark.circle.fill" : "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                        Text(isSelectedEngine ? generalSettingsStore.text(.active) : generalSettingsStore.text(.useForPolishing))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(width: 142, height: 26)
                }
                .buttonStyle(.borderedProminent)
                .tint(isSelectedEngine ? .green : .accentColor)
                .disabled(!isConfigured || isSelectedEngine)
            }
        }
    }

    private var isSelectedEngine: Bool {
        polishingEngineStore.selectedEngineID == kind.polishingEngineID
    }

    // MARK: - Model Specs Chip Row

    @ViewBuilder
    private var modelMetaRow: some View {
        let model = availableModels.first(where: { $0.id == currentModelID })
            ?? CloudRemoteModel(id: currentModelID)

        HStack(spacing: 14) {
            metaChip(icon: "brain", title: generalSettingsStore.text(.modelSpecContext), value: model.resolvedContextLabel)
            metaChip(icon: "arrow.down.circle", title: generalSettingsStore.text(.modelSpecInput), value: model.resolvedInputPriceLabel)
            metaChip(icon: "arrow.up.circle", title: generalSettingsStore.text(.modelSpecOutput), value: model.resolvedOutputPriceLabel)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func metaChip(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
            Text("\(title):")
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }

    private var currentModelID: String {
        configuration.textModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canFetchModels: Bool {
        let key = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.unicodeScalars.allSatisfy(\.isASCII) else { return false }
        if kind == .custom {
            return !configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private var isConfigured: Bool {
        let config = configuration
        let modelOK = !config.textModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard config.hasAPIKey, modelOK else { return false }
        if kind == .custom {
            return !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private var keyIssue: String? {
        let key = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if key.unicodeScalars.contains(where: { !$0.isASCII }) {
            return generalSettingsStore.text(.keyNonLatinError)
        }
        return nil
    }

    private func scheduleModelsFetch(force: Bool = false) {
        modelsFetchTask?.cancel()
        guard canFetchModels else {
            availableModels = kind == .qwen ? CloudProviderModelCatalog.qwenSubscriptionModels : []
            modelsError = nil
            isLoadingModels = false
            return
        }
        let delay: UInt64 = force ? 0 : 400_000_000
        let snapshot = configuration
        let providerKind = kind
        isLoadingModels = true
        modelsFetchTask = Task {
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    NativeSmartScribeLog.models.error(
                        "Model fetch debounce interrupted: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            guard !Task.isCancelled else { return }
            let result = await CloudProviderModelCatalog.fetchModels(
                kind: providerKind,
                configuration: snapshot
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isLoadingModels = false
                if let error = result.errorMessage, result.models.isEmpty {
                    modelsError = error
                    return
                }
                modelsError = result.errorMessage
                availableModels = result.models
                applyFetchedModelsIfNeeded(result.models)
            }
        }
    }

    private func applyFetchedModelsIfNeeded(_ models: [CloudRemoteModel]) {
        guard !models.isEmpty else { return }
        let current = configuration.textModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || !models.contains(where: { $0.id == current }) {
            if let preferred = preferredModel(in: models) {
                configuration.textModel = preferred.id
            } else {
                configuration.textModel = models[0].id
            }
        }
    }

    private func preferredModel(in models: [CloudRemoteModel]) -> CloudRemoteModel? {
        let prefs: [String]
        switch kind {
        case .openRouter:
            prefs = ["openai/gpt-4o-mini", "google/gemini-2.0-flash-001", "anthropic/claude-3.5-haiku"]
        case .openAI:
            prefs = ["gpt-4o-mini", "gpt-4.1-mini", "gpt-4o"]
        case .google:
            // Prefer newest Flash ids first when the catalog returns them.
            prefs = [
                "gemini-3.6-flash", "gemini-3.5-flash", "gemini-3-flash",
                "gemini-2.5-flash", "gemini-2.0-flash"
            ]
        case .qwen:
            prefs = ["qwen3.7-plus", "qwen3.7-max", "qwen3.6-flash", "qwen3.8-max-preview"]
        case .custom:
            prefs = ["qwen3.7-plus", "qwen3.7-max"]
        case .anthropic:
            prefs = ["claude-3-haiku-20240307"]
        }
        for id in prefs {
            if let model = models.first(where: { $0.id == id }) { return model }
        }
        for token in ["flash", "mini", "haiku", "plus"] {
            if let model = models.first(where: { $0.id.localizedCaseInsensitiveContains(token) }) {
                return model
            }
        }
        return models.first
    }

    private func refreshBalance() {
        guard kind.supportsBalance else {
            openRouterBalance = nil
            return
        }
        let key = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.unicodeScalars.allSatisfy(\.isASCII) else {
            openRouterBalance = nil
            return
        }
        isLoadingBalance = true
        Task {
            let balance = await CloudProviderModelCatalog.fetchOpenRouterBalance(apiKey: key)
            await MainActor.run {
                isLoadingBalance = false
                openRouterBalance = balance
            }
        }
    }
}

// MARK: - Searchable Model Picker Sheet with Favorites

enum FavoriteModelsStore {
    private static let key = "favorite.cloud.model.ids"

    static func loadFavorites() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(array)
    }

    static func isFavorite(_ modelID: String) -> Bool {
        loadFavorites().contains(modelID)
    }

    static func toggleFavorite(_ modelID: String) -> Set<String> {
        var set = loadFavorites()
        if set.contains(modelID) {
            set.remove(modelID)
        } else {
            set.insert(modelID)
        }
        UserDefaults.standard.set(Array(set), forKey: key)
        return set
    }
}

private struct SmartModelPickerSheet: View {
    let providerName: String
    let models: [CloudRemoteModel]
    @Binding var selectedModelID: String
    @Binding var isPresented: Bool

    @State private var searchText = ""
    @State private var showFavoritesOnly = false
    @State private var favoriteIDs: Set<String> = FavoriteModelsStore.loadFavorites()

    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore

    private var filteredModels: [CloudRemoteModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = models

        if !query.isEmpty {
            result = result.filter { $0.id.localizedCaseInsensitiveContains(query) }
        }

        if showFavoritesOnly {
            result = result.filter { favoriteIDs.contains($0.id) }
        }

        // Sort favorited models to the top, then alphabetically
        return result.sorted { a, b in
            let aFav = favoriteIDs.contains(a.id)
            let bFav = favoriteIDs.contains(b.id)
            if aFav != bFav { return aFav }
            return a.id.localizedCaseInsensitiveCompare(b.id) == .orderedAscending
        }
    }

    private var favoriteCount: Int {
        models.filter { favoriteIDs.contains($0.id) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sheet Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(generalSettingsStore.formattedText(.selectPolishingModelTitle, providerName))
                        .font(.system(size: 14, weight: .bold))
                    HStack(spacing: 8) {
                        Text(generalSettingsStore.formattedText(.modelsCount, "\(filteredModels.count)", "\(models.count)"))
                        if favoriteCount > 0 {
                            Text("•")
                            Text(generalSettingsStore.formattedText(.favoritesCount, "\(favoriteCount)"))
                                .foregroundStyle(.yellow)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // Search & Favorites Filter Bar
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                    TextField(generalSettingsStore.text(.searchModelsPlaceholder), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Favorites Filter Toggle Button
                Button {
                    showFavoritesOnly.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                            .font(.system(size: 11, weight: .semibold))
                        Text(showFavoritesOnly ? generalSettingsStore.text(.favoritesFilter) : generalSettingsStore.text(.allFilter))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        showFavoritesOnly ? Color.yellow.opacity(0.18) : Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .foregroundStyle(showFavoritesOnly ? .yellow : .secondary)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(showFavoritesOnly ? Color.yellow.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .help(showFavoritesOnly ? generalSettingsStore.text(.showAllModels) : generalSettingsStore.text(.filterByFavorites))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Models List
            if filteredModels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: showFavoritesOnly ? "star.slash" : "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text(showFavoritesOnly ? generalSettingsStore.formattedText(.noFavoriteModels, providerName) : generalSettingsStore.formattedText(.noMatchingModels, searchText))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if showFavoritesOnly {
                        Button(generalSettingsStore.text(.showAllModels)) {
                            showFavoritesOnly = false
                        }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.borderless)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredModels) { model in
                    let isFav = favoriteIDs.contains(model.id)
                    let isSelected = model.id == selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines)

                    HStack(alignment: .center, spacing: 10) {
                        // Star Favorite Button
                        Button {
                            favoriteIDs = FavoriteModelsStore.toggleFavorite(model.id)
                        } label: {
                            Image(systemName: isFav ? "star.fill" : "star")
                                .font(.system(size: 14))
                                .foregroundStyle(isFav ? .yellow : Color.secondary.opacity(0.35))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(isFav ? generalSettingsStore.text(.removeFromFavorites) : generalSettingsStore.text(.addToFavorites))

                        // Select Model Content
                        Button {
                            selectedModelID = model.id
                            isPresented = false
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(model.id)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)

                                        let badgeInfo = CloudProviderModelCatalog.badgeInfo(for: model.id, groupModelIDs: filteredModels.map(\.id))
                                        if badgeInfo.isRecommended {
                                            Text(generalSettingsStore.text(.badgeRecommended))
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                                                .foregroundStyle(.green)
                                        }
                                        if badgeInfo.isNew {
                                            Text(generalSettingsStore.text(.badgeNew))
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.cyan.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                                                .foregroundStyle(.cyan)
                                        }
                                        if isFav {
                                            Text(generalSettingsStore.text(.badgeFavorite))
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                                                .foregroundStyle(.yellow)
                                        }
                                    }

                                    HStack(spacing: 10) {
                                        Text(generalSettingsStore.formattedText(.contextLengthChip, model.resolvedContextLabel))
                                        Text(generalSettingsStore.formattedText(.inputPriceChip, model.resolvedInputPriceLabel))
                                        Text(generalSettingsStore.formattedText(.outputPriceChip, model.resolvedOutputPriceLabel))
                                    }
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 4)

                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Usage Inline Card

private struct UsageInlineCard: View {
    let providerKind: APIProviderKind
    let activeModelID: String

    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var usageStatisticsStore: UsageStatisticsStore
    @State private var selectedModelID: String?

    private var availableModelIDs: [String] {
        usageStatisticsStore.modelIDs()
    }

    private var currentSelectedModelKey: String? {
        if let selectedModelID, availableModelIDs.contains(selectedModelID) {
            return selectedModelID
        }
        if let matched = findBestMatchingModelKey(for: activeModelID, in: availableModelIDs) {
            return matched
        }
        return availableModelIDs.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(generalSettingsStore.text(.usageStatistics))
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                Button {
                    resetProviderStats()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .bold))
                        Text(generalSettingsStore.formattedText(.resetProviderStats, providerKind.displayName))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(generalSettingsStore.formattedText(.resetProviderStatsHelp, providerKind.displayName))
            }

            Divider()

            // Last Usage — the most recent request
            let lastTx = usageStatisticsStore.settings.lastTransaction
            let lastModelID = currentSelectedModelKey ?? activeModelID
            let lastCostStr = CloudProviderModelCatalog.formattedCostUSD(
                modelID: lastModelID,
                promptTokens: lastTx.promptTokens,
                completionTokens: lastTx.completionTokens
            )

            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9, weight: .semibold))
                Text(generalSettingsStore.text(.lastUsage))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                tokenStatChip(
                    title: generalSettingsStore.text(.promptTokens),
                    value: "\(lastTx.promptTokens)",
                    icon: "arrow.down.doc"
                )

                tokenStatChip(
                    title: generalSettingsStore.text(.completionTokens),
                    value: "\(lastTx.completionTokens)",
                    icon: "arrow.up.doc"
                )

                tokenStatChip(
                    title: generalSettingsStore.text(.totalTokens),
                    value: "\(lastTx.totalTokens)",
                    icon: "sum"
                )

                tokenStatChip(
                    title: generalSettingsStore.text(.estCost),
                    value: lastCostStr,
                    icon: "dollarsign.circle",
                    accentColor: .green
                )
            }

            if !availableModelIDs.isEmpty {
                Divider()

                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text(generalSettingsStore.text(.totalUsageLabel))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Text(generalSettingsStore.text(.selectedModel))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Picker("", selection: selectedModelBinding) {
                        ForEach(availableModelIDs, id: \.self) { key in
                            Text(usageStatisticsStore.modelName(for: key))
                                .tag(Optional(key))
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    if let key = currentSelectedModelKey {
                        let total = usageStatisticsStore.total(for: key)
                        let spentStr = CloudProviderModelCatalog.formattedCostUSD(
                            modelID: key,
                            promptTokens: total.promptTokens,
                            completionTokens: total.completionTokens
                        )

                        HStack(spacing: 6) {
                            Text(generalSettingsStore.formattedText(.totalLabel, "\(total.totalTokens)"))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))

                            Text("•")
                                .foregroundStyle(.tertiary)

                            HStack(spacing: 3) {
                                Image(systemName: "dollarsign.circle.fill")
                                    .font(.system(size: 11))
                                Text(generalSettingsStore.formattedText(.spentLabel, spentStr))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(.green)
                        }

                        Button {
                            usageStatisticsStore.reset(modelID: key)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .disabled(total.totalTokens == 0)
                        .help(generalSettingsStore.text(.resetStats))
                    }
                }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        }
        .onAppear {
            syncSelectedModel(with: activeModelID)
        }
        .onChange(of: activeModelID) { _, newActive in
            syncSelectedModel(with: newActive)
        }
    }

    private func syncSelectedModel(with active: String) {
        if let matched = findBestMatchingModelKey(for: active, in: availableModelIDs) {
            selectedModelID = matched
        }
    }

    private var providerModelIDs: [String] {
        availableModelIDs.filter { modelID in
            let lower = modelID.lowercased()
            switch providerKind {
            case .google:
                return lower.contains("gemini") || lower.contains("google")
            case .openAI:
                return lower.contains("gpt") || lower.contains("openai") || lower.contains("whisper")
            case .anthropic:
                return lower.contains("claude") || lower.contains("anthropic")
            case .qwen:
                return lower.contains("qwen") || lower.contains("deepseek") || lower.contains("glm")
            case .openRouter:
                return lower.contains("openrouter") || lower.contains("/")
            case .custom:
                return true
            }
        }
    }

    private func resetProviderStats() {
        let targets = providerModelIDs.isEmpty ? availableModelIDs : providerModelIDs
        usageStatisticsStore.reset(modelIDs: targets)
    }

    private func findBestMatchingModelKey(for active: String, in availableKeys: [String]) -> String? {
        let cleanActive = active.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanActive.isEmpty else { return nil }

        if let exact = availableKeys.first(where: { $0.lowercased() == cleanActive }) {
            return exact
        }
        if let partial = availableKeys.first(where: { key in
            let lowerKey = key.lowercased()
            return lowerKey.contains(cleanActive) || cleanActive.contains(lowerKey)
        }) {
            return partial
        }
        return nil
    }

    private func tokenStatChip(title: String, value: String, icon: String, accentColor: Color = Color.accentColor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(accentColor)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(accentColor == Color.accentColor ? Color.primary : accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var selectedModelBinding: Binding<String?> {
        Binding(
            get: { currentSelectedModelKey },
            set: { selectedModelID = $0 }
        )
    }
}

#Preview {
    APIProvidersSettingsView()
        .environmentObject(GeneralSettingsStore.live())
        .environmentObject(PolishingEngineStore.live())
        .environmentObject(UsageStatisticsStore.live())
}
