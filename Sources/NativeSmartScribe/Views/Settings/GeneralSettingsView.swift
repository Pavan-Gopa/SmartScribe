import NativeSmartScribeCore
import SwiftUI

@MainActor
struct GeneralSettingsView: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore

    var body: some View {
        Form {
            // Consolidated Interface & Theme Section (2x more compact in height!)
            Section(generalSettingsStore.text(.theme)) {
                Picker(generalSettingsStore.text(.appearance), selection: themeSelection) {
                    ForEach(ThemePreference.allCases) { theme in
                        Text(themeTitle(theme))
                            .tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text(generalSettingsStore.text(.uiFontSize))
                    Spacer()
                    Slider(value: uiScale, in: 0.8...1.4, step: 0.05)
                        .frame(width: 265)
                    Text("\(generalSettingsStore.uiScalePercentage)%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }

                HStack {
                    Text(generalSettingsStore.text(.contentTextSize))
                    Spacer()
                    Slider(value: contentTextScale, in: 1.0...2.0, step: 0.05)
                        .frame(width: 265)
                    Text("\(Int(generalSettingsStore.settings.textScale * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }

                Picker(generalSettingsStore.text(.contentFont), selection: contentFontSelection) {
                    Text(generalSettingsStore.text(.fontSystem)).tag(TextFontPreference.system)
                    Text(generalSettingsStore.text(.fontSerif)).tag(TextFontPreference.serif)
                    Text(generalSettingsStore.text(.fontMonospaced)).tag(TextFontPreference.monospaced)
                }

                Picker(generalSettingsStore.text(.interfaceLanguage), selection: languageSelection) {
                    ForEach(UILanguagePreference.allCases) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
            }

            // Compact Overlay HUD Section with 2-column layout!
            Section(generalSettingsStore.text(.overlayHUD)) {
                HStack(alignment: .top, spacing: 20) {
                    // Left Column: Vertical HUD style selector buttons
                    VStack(alignment: .leading, spacing: 8) {
                        Text(generalSettingsStore.text(.hudStyle))
                            .font(.subheadline.weight(.semibold))

                        VStack(spacing: 6) {
                            ForEach(OverlayHUDStyle.allCases) { style in
                                HUDStyleCardView(
                                    style: style,
                                    isSelected: generalSettingsStore.settings.overlay.style == style,
                                    title: hudStyleTitle(style),
                                    action: { overlayStyle.wrappedValue = style }
                                )
                                .frame(height: 36)
                            }
                        }
                    }
                    .frame(width: 170)

                    Divider()

                    // Right Column: Sub-divided into Size/Transparency (top) and Sound (bottom)
                    VStack(alignment: .leading, spacing: 0) {
                        // Top part: Size and Transparency
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(generalSettingsStore.text(.size))
                                Spacer()
                                Slider(value: overlayScale, in: 0.8...1.6, step: 0.05)
                                    .frame(width: 265)
                                Text("\(generalSettingsStore.overlayScalePercentage)%")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 44, alignment: .trailing)
                            }

                            HStack {
                                Text(generalSettingsStore.text(.transparency))
                                Spacer()
                                Slider(value: overlayCapsuleOpacity, in: 0.12...1, step: 0.02)
                                    .frame(width: 265)
                                Text("\(generalSettingsStore.overlayTransparencyPercentage)%")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                        .padding(.top, 2)

                        Divider()
                            .opacity(0.5)
                            .padding(.vertical, 8)

                        // Bottom part: Play sound, Sound Volume, and Test HUD Sounds button
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(generalSettingsStore.text(.playSound), isOn: overlaySoundEnabled)

                            HStack {
                                Text(generalSettingsStore.text(.soundVolume))
                                Spacer()
                                Slider(value: overlayVolume, in: 0.1...2, step: 0.02)
                                    .frame(width: 265)
                                Text("\(generalSettingsStore.overlayVolumePercentage)%")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 44, alignment: .trailing)
                            }
                            .disabled(!generalSettingsStore.settings.overlay.soundEnabled)

                            Spacer(minLength: 4)

                            HStack {
                                Spacer()
                                Button {
                                    generalSettingsStore.testOverlayHUDSounds()
                                } label: {
                                    Label(generalSettingsStore.text(.testHUDSounds), systemImage: "speaker.wave.2")
                                }
                                .disabled(!generalSettingsStore.settings.overlay.soundEnabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 4)
            }

            // Consolidated Log Level & Troubleshooting side-by-side block!
            Section {
                HStack(alignment: .top, spacing: 20) {
                    // Left Column: Log Level
                    VStack(alignment: .leading, spacing: 8) {
                        Text(generalSettingsStore.text(.logLevel))
                            .font(.headline)

                        Picker(generalSettingsStore.text(.level), selection: logLevelSelection) {
                            ForEach(AppLogLevel.allCases) { level in
                                Text(logLevelTitle(level))
                                    .tag(level)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    // Right Column: Troubleshooting
                    VStack(alignment: .leading, spacing: 8) {
                        Text(generalSettingsStore.text(.troubleshooting))
                            .font(.headline)

                        HStack(spacing: 8) {
                            Button {
                                generalSettingsStore.exportSystemLogs()
                            } label: {
                                Label(generalSettingsStore.text(.exportSystemLogs), systemImage: "square.and.arrow.down")
                            }

                            Button {
                                generalSettingsStore.reset()
                            } label: {
                                Label(generalSettingsStore.text(.resetGeneral), systemImage: "arrow.counterclockwise")
                            }
                        }

                        if let message = generalSettingsStore.logExportMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    private func hudStyleTitle(_ style: OverlayHUDStyle) -> String {
        switch style {
        case .capsule:
            generalSettingsStore.text(.hudStyleCapsule)
        case .tech:
            generalSettingsStore.text(.hudStyleTech)
        case .vertical:
            generalSettingsStore.text(.hudStyleVertical)
        }
    }

    private var themeSelection: Binding<ThemePreference> {
        Binding(
            get: { generalSettingsStore.settings.theme },
            set: { theme in
                generalSettingsStore.update { $0.theme = theme }
            }
        )
    }

    private func themeTitle(_ theme: ThemePreference) -> String {
        switch theme {
        case .dark:
            generalSettingsStore.text(.themeDark)
        case .light:
            generalSettingsStore.text(.themeLight)
        case .system:
            generalSettingsStore.text(.themeSystem)
        }
    }

    private func logLevelTitle(_ level: AppLogLevel) -> String {
        switch level {
        case .error:
            generalSettingsStore.text(.levelError)
        case .warn:
            generalSettingsStore.text(.levelWarn)
        case .info:
            generalSettingsStore.text(.levelInfo)
        case .debug:
            generalSettingsStore.text(.levelDebug)
        }
    }

    private var uiScale: Binding<Double> {
        Binding(
            get: { generalSettingsStore.settings.uiScale },
            set: { scale in
                generalSettingsStore.update { $0.uiScale = scale }
            }
        )
    }

    private var contentTextScale: Binding<Double> {
        Binding(
            get: { generalSettingsStore.settings.textScale },
            set: { scale in
                generalSettingsStore.update { $0.textScale = scale }
            }
        )
    }

    private var contentFontSelection: Binding<TextFontPreference> {
        Binding(
            get: { generalSettingsStore.settings.textFont },
            set: { font in
                generalSettingsStore.update { $0.textFont = font }
            }
        )
    }

    private var languageSelection: Binding<UILanguagePreference> {
        Binding(
            get: { generalSettingsStore.settings.uiLanguage },
            set: { language in
                generalSettingsStore.update { $0.uiLanguage = language }
            }
        )
    }

    private var overlayScale: Binding<Double> {
        Binding(
            get: { generalSettingsStore.settings.overlay.scale },
            set: { scale in
                generalSettingsStore.update { $0.overlay.scale = scale }
            }
        )
    }

    private var overlayStyle: Binding<OverlayHUDStyle> {
        Binding(
            get: { generalSettingsStore.settings.overlay.style },
            set: { style in
                generalSettingsStore.update { $0.overlay.style = style }
            }
        )
    }

    private var overlayCapsuleOpacity: Binding<Double> {
        Binding(
            get: { generalSettingsStore.settings.overlay.capsuleOpacity },
            set: { opacity in
                generalSettingsStore.update { $0.overlay.capsuleOpacity = opacity }
            }
        )
    }

    private var overlaySoundEnabled: Binding<Bool> {
        Binding(
            get: { generalSettingsStore.settings.overlay.soundEnabled },
            set: { isEnabled in
                generalSettingsStore.update { $0.overlay.soundEnabled = isEnabled }
            }
        )
    }

    private var overlayVolume: Binding<Double> {
        Binding(
            get: { generalSettingsStore.settings.overlay.volume },
            set: { volume in
                generalSettingsStore.update { $0.overlay.volume = volume }
            }
        )
    }

    private var logLevelSelection: Binding<AppLogLevel> {
        Binding(
            get: { generalSettingsStore.settings.logLevel },
            set: { level in
                generalSettingsStore.update { $0.logLevel = level }
            }
        )
    }
}

private struct HUDStyleCardView: View {
    let style: OverlayHUDStyle
    let isSelected: Bool
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 14, height: 14)

                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                    }
                }

                Text(title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.15)
                            : Color.primary.opacity(isHovered ? 0.06 : 0.03)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected
                            ? Color.accentColor.opacity(0.6)
                            : Color.white.opacity(isHovered ? 0.15 : 0.05),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    GeneralSettingsView()
        .environmentObject(GeneralSettingsStore.live())
}
