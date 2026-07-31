import NativeSmartScribeCore
import SwiftUI

@MainActor
struct HotkeySettingsView: View {
    @EnvironmentObject private var hotkeySettingsStore: HotkeySettingsStore
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @EnvironmentObject private var accessibilityPermissionStore: AccessibilityPermissionStore
    @EnvironmentObject private var transcriptionModelStore: TranscriptionModelStore

    var body: some View {
        Form {
            Section(header: Text(generalSettingsStore.text(.globalHotkey))) {
                Toggle(generalSettingsStore.text(.enableHotkey), isOn: settingsEnabled)
                    .padding(.vertical, 2)

                if hotkeySettingsStore.settings.enabled {
                    // Row for Primary Hotkey
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(generalSettingsStore.text(.hotkeyPrimaryLabel))
                                .font(.body.weight(.medium))
                            Text(generalSettingsStore.text(.hotkeyPrimaryDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        hotkeyGlyphBadge(for: hotkeySettingsStore.settings.hotkey)

                        TextField("", text: hotkeyText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                            .multilineTextAlignment(.trailing)
                            .help(generalSettingsStore.formattedText(.hotkeyOptionHint, "Option+S"))

                        Button {
                            hotkeySettingsStore.settings.hotkey = HotkeySettings.defaultPrimaryHotkey
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .help(generalSettingsStore.text(.reset))
                    }
                    .padding(.vertical, 2)

                    // Row for Full Translation Window Hotkey (Option+1)
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(generalSettingsStore.text(.translationWindowLabel))
                                .font(.body.weight(.medium))
                            Text(generalSettingsStore.text(.translationWindowDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        hotkeyGlyphBadge(for: hotkeySettingsStore.settings.secondaryHotkey)

                        TextField("", text: secondaryHotkeyText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                            .multilineTextAlignment(.trailing)
                            .help(generalSettingsStore.formattedText(.hotkeyOptionHint, "Option+1"))

                        Button {
                            hotkeySettingsStore.settings.secondaryHotkey = HotkeySettings.defaultSecondaryHotkey
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .help(generalSettingsStore.text(.reset))
                    }
                    .padding(.vertical, 2)

                    // Row for Quick Translation Hotkey (Option+2)
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(generalSettingsStore.text(.quickTranslationLabel))
                                .font(.body.weight(.medium))
                            Text(generalSettingsStore.text(.quickTranslationDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        hotkeyGlyphBadge(for: hotkeySettingsStore.settings.tertiaryHotkey)

                        TextField("", text: tertiaryHotkeyText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                            .multilineTextAlignment(.trailing)
                            .help(generalSettingsStore.formattedText(.hotkeyOptionHint, "Option+2"))

                        Button {
                            hotkeySettingsStore.settings.tertiaryHotkey = HotkeySettings.defaultTertiaryHotkey
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .help(generalSettingsStore.text(.reset))
                    }
                    .padding(.vertical, 2)
                }

                // Row for Settings Hotkey (Option+~) - always visible
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(generalSettingsStore.text(.openSettingsLabel))
                            .font(.body.weight(.medium))
                        Text(generalSettingsStore.text(.openSettingsDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    hotkeyGlyphBadge(for: hotkeySettingsStore.settings.settingsHotkey)

                    TextField("", text: settingsHotkeyText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                        .multilineTextAlignment(.trailing)
                        .help(generalSettingsStore.formattedText(.hotkeyOptionHint, "Option+~"))

                    Button {
                        hotkeySettingsStore.settings.settingsHotkey = HotkeySettings.defaultSettingsHotkey
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .help(generalSettingsStore.text(.reset))
                }
                .padding(.vertical, 2)
            }

            // Side-by-side Recognition Language & Output block
            if hotkeySettingsStore.settings.enabled {
                Section {
                    HStack(alignment: .top, spacing: 20) {
                        // Left Column: Recognition Language
                        VStack(alignment: .leading, spacing: 8) {
                            Text(generalSettingsStore.text(.hotkeyTargetLanguage))
                                .font(.headline)

                            Picker(generalSettingsStore.text(.transcriptionLanguage), selection: languageSelection) {
                                Text(generalSettingsStore.text(.autoDetect)).tag("auto")
                                ForEach(TranscriptionLanguageOption.builtIn) { language in
                                    Text("\(language.displayName) (\(language.code))")
                                        .tag(language.code)
                                }
                                Text(generalSettingsStore.text(.customCode)).tag("custom")
                            }

                            if transcriptionModelStore.languageSelectionTag == "custom" {
                                TextField(generalSettingsStore.text(.languageCode), text: customLanguageCode)
                                    .textFieldStyle(.roundedBorder)
                            }

                            LabeledContent(generalSettingsStore.text(.resolvedLanguage), value: transcriptionModelStore.resolvedLanguageCode)

                            Text(generalSettingsStore.text(.transcriptionLanguageHint))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        // Right Column: Output
                        VStack(alignment: .leading, spacing: 8) {
                            Text(generalSettingsStore.text(.output))
                                .font(.headline)

                            Picker(generalSettingsStore.text(.target), selection: targetSelection) {
                                ForEach(HotkeyTarget.allCases) { target in
                                    Text(targetTitle(target))
                                        .tag(target)
                                }
                            }

                            Picker(generalSettingsStore.text(.mode), selection: outputModeSelection) {
                                ForEach(HotkeyOutputMode.allCases) { mode in
                                    Text(outputModeTitle(mode))
                                        .tag(mode)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Compact Accessibility Permission block at the bottom
            Section(generalSettingsStore.text(.accessibilityPermission)) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Label(
                            accessibilityPermissionStore.isTrusted
                                ? generalSettingsStore.text(.accessibilityTrusted)
                                : generalSettingsStore.text(.accessibilityNotTrusted),
                            systemImage: accessibilityPermissionStore.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(accessibilityPermissionStore.isTrusted ? .green : .orange)
                        .font(.body.weight(.medium))

                        Spacer()

                        HStack(spacing: 6) {
                            Button {
                                accessibilityPermissionStore.refresh()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)
                            .help(generalSettingsStore.text(.refreshPermissionStatus))

                            Button {
                                accessibilityPermissionStore.requestPermission()
                            } label: {
                                Image(systemName: "hand.raised")
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)
                            .help(generalSettingsStore.text(.requestAccessibilityPermission))
                            .disabled(accessibilityPermissionStore.isTrusted)

                            Button {
                                accessibilityPermissionStore.openSettings()
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)
                            .help(generalSettingsStore.text(.openAccessibilitySettings))
                        }
                    }

                    Text(generalSettingsStore.text(.accessibilityPermissionDescription))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            accessibilityPermissionStore.refresh()
        }
    }

    private var settingsEnabled: Binding<Bool> {
        Binding(
            get: { hotkeySettingsStore.settings.enabled },
            set: { hotkeySettingsStore.settings.enabled = $0 }
        )
    }

    private var hotkeyText: Binding<String> {
        Binding(
            get: { HotkeySettings.normalizeMacModifiers(hotkeySettingsStore.settings.hotkey) },
            set: { hotkeySettingsStore.settings.hotkey = HotkeySettings.normalizeMacModifiers($0) }
        )
    }

    private var secondaryHotkeyText: Binding<String> {
        Binding(
            get: { HotkeySettings.normalizeMacModifiers(hotkeySettingsStore.settings.secondaryHotkey) },
            set: { hotkeySettingsStore.settings.secondaryHotkey = HotkeySettings.normalizeMacModifiers($0) }
        )
    }

    private var tertiaryHotkeyText: Binding<String> {
        Binding(
            get: { HotkeySettings.normalizeMacModifiers(hotkeySettingsStore.settings.tertiaryHotkey) },
            set: { hotkeySettingsStore.settings.tertiaryHotkey = HotkeySettings.normalizeMacModifiers($0) }
        )
    }

    private var settingsHotkeyText: Binding<String> {
        Binding(
            get: { HotkeySettings.normalizeMacModifiers(hotkeySettingsStore.settings.settingsHotkey) },
            set: { hotkeySettingsStore.settings.settingsHotkey = HotkeySettings.normalizeMacModifiers($0) }
        )
    }

    /// Compact macOS glyph preview (e.g. ⌥S) next to the editable Option+S field.
    @ViewBuilder
    private func hotkeyGlyphBadge(for hotkey: String) -> some View {
        Text(HotkeySettings.displayString(for: hotkey))
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .help(HotkeySettings.displayString(for: hotkey))
    }

    private var targetSelection: Binding<HotkeyTarget> {
        Binding(
            get: { hotkeySettingsStore.settings.target },
            set: { hotkeySettingsStore.settings.target = $0 }
        )
    }

    private var outputModeSelection: Binding<HotkeyOutputMode> {
        Binding(
            get: { hotkeySettingsStore.settings.mode },
            set: { hotkeySettingsStore.settings.mode = $0 }
        )
    }

    private func targetTitle(_ target: HotkeyTarget) -> String {
        switch target {
        case .raw:
            generalSettingsStore.text(.raw)
        case .note:
            generalSettingsStore.text(.variantOne)
        case .x2:
            generalSettingsStore.text(.variantTwo)
        }
    }

    private func outputModeTitle(_ mode: HotkeyOutputMode) -> String {
        switch mode {
        case .clipboard:
            generalSettingsStore.text(.clipboardMode)
        case .typing:
            generalSettingsStore.text(.typeIntoActiveApp)
        }
    }

    private var languageSelection: Binding<String> {
        Binding(
            get: { transcriptionModelStore.languageSelectionTag },
            set: { transcriptionModelStore.setLanguageSelectionTag($0) }
        )
    }

    private var customLanguageCode: Binding<String> {
        Binding(
            get: { transcriptionModelStore.customLanguageCode },
            set: { transcriptionModelStore.setCustomLanguageCode($0) }
        )
    }
}

#Preview {
    HotkeySettingsView()
        .environmentObject(HotkeySettingsStore.live())
        .environmentObject(GeneralSettingsStore.live())
        .environmentObject(AccessibilityPermissionStore.live())
        .environmentObject(TranscriptionModelStore.live())
}
