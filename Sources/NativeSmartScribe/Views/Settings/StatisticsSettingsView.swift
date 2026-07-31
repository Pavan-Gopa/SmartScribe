import NativeSmartScribeCore
import SwiftUI

@MainActor
struct StatisticsSettingsView: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var usageStatisticsStore: UsageStatisticsStore
    @State private var selectedModelID: String?

    var body: some View {
        Form {
            Section(generalSettingsStore.text(.lastUsage)) {
                UsageTokenRows(count: usageStatisticsStore.settings.lastTransaction)
                LabeledContent(
                    generalSettingsStore.text(.estCost),
                    value: CloudProviderModelCatalog.formattedCostUSD(
                        modelID: resolvedSelectedModelID ?? "",
                        promptTokens: usageStatisticsStore.settings.lastTransaction.promptTokens,
                        completionTokens: usageStatisticsStore.settings.lastTransaction.completionTokens
                    )
                )
            }

            Section(totalUsageTitle) {
                if usageStatisticsStore.modelIDs().isEmpty {
                    Text(generalSettingsStore.text(.noUsageData))
                        .foregroundStyle(.secondary)
                } else {
                    Picker(generalSettingsStore.text(.selectedModel), selection: selectedModelBinding) {
                        ForEach(usageStatisticsStore.modelIDs(), id: \.self) { modelID in
                            Text(usageStatisticsStore.modelName(for: modelID))
                                .tag(Optional(modelID))
                        }
                    }

                    UsageTokenRows(count: usageStatisticsStore.total(for: resolvedSelectedModelID))

                    Button {
                        usageStatisticsStore.reset(modelID: resolvedSelectedModelID)
                    } label: {
                        Label(generalSettingsStore.text(.resetStats), systemImage: "arrow.counterclockwise")
                    }
                    .disabled(resolvedSelectedModelID == nil)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            selectedModelID = resolvedSelectedModelID
        }
    }

    private var resolvedSelectedModelID: String? {
        if let selectedModelID, usageStatisticsStore.modelIDs().contains(selectedModelID) {
            return selectedModelID
        }
        return usageStatisticsStore.selectedModelID
    }

    private var selectedModelBinding: Binding<String?> {
        Binding(
            get: { resolvedSelectedModelID },
            set: { selectedModelID = $0 }
        )
    }

    private var totalUsageTitle: String {
        let modelName = resolvedSelectedModelID.map { usageStatisticsStore.modelName(for: $0) } ?? generalSettingsStore.text(.noValue)
        return generalSettingsStore.formattedText(.totalUsageFor, modelName)
    }
}

private struct UsageTokenRows: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    let count: UsageTokenCount

    var body: some View {
        LabeledContent(generalSettingsStore.text(.promptTokens), value: count.promptTokens.formatted())
        LabeledContent(generalSettingsStore.text(.completionTokens), value: count.completionTokens.formatted())
        LabeledContent(generalSettingsStore.text(.totalTokens), value: count.totalTokens.formatted())
    }
}

#Preview {
    StatisticsSettingsView()
        .environmentObject(GeneralSettingsStore.live())
        .environmentObject(UsageStatisticsStore.live())
}
