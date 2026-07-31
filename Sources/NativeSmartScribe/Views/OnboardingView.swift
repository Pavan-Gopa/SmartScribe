import AVFoundation
import AppKit
import NativeSmartScribeCore
import SwiftUI

extension Notification.Name {
  /// Posted when the user asks to replay the welcome tour (e.g. from Settings → Help).
  static let showOnboarding = Notification.Name("nativeSmartScribeShowOnboarding")
}

/// First-launch setup assistant. Every step either applies a setting or exposes
/// the real app action that the user will rely on after onboarding.
@MainActor
struct OnboardingView: View {
  @EnvironmentObject private var settingsStore: GeneralSettingsStore
  @EnvironmentObject private var glossaryStore: GlossaryStore
  @EnvironmentObject private var transcriptionModelStore: TranscriptionModelStore
  @EnvironmentObject private var polishingEngineStore: PolishingEngineStore
  @EnvironmentObject private var hotkeySettingsStore: HotkeySettingsStore
  @Environment(\.dismiss) private var dismiss

  @ObservedObject private var accessibility: AccessibilityPermissionStore
  @ObservedObject private var audioRecorder: AudioRecorder

  @State private var step = 0
  @State private var micGranted = false
  @State private var googleAPIKey = ""
  @State private var showsGoogleAPIKey = false
  @State private var showsAddGoogleKeyForm = false
  @State private var glossaryCreated = false
  @State private var expandedModeID: String?

  private let totalSteps = 6

  init(
    accessibility: AccessibilityPermissionStore,
    audioRecorder: AudioRecorder
  ) {
    self.accessibility = accessibility
    self.audioRecorder = audioRecorder
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()

      ScrollView {
        stepContent
          .frame(maxWidth: 680)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 26)
      }

      Divider()
      footer
    }
    .frame(width: 760, height: 640)
    .onAppear(perform: refreshSetupState)
    .onReceive(
      NotificationCenter.default.publisher(
        for: NSApplication.didBecomeActiveNotification
      )
    ) { _ in
      refreshPermissions()
    }
  }

  // MARK: - Shell

  private var header: some View {
    HStack(spacing: 10) {
      SmartScribeLogoView(size: 30)
      Text("SmartScribe")
        .font(.headline)
      Spacer()
      stepIndicator
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 14)
  }

  private var stepIndicator: some View {
    HStack(spacing: 7) {
      ForEach(0..<totalSteps, id: \.self) { index in
        Capsule()
          .fill(
            index == step
              ? Color.accentColor
              : Color.secondary.opacity(0.28)
          )
          .frame(width: index == step ? 20 : 7, height: 7)
          .animation(.easeInOut(duration: 0.2), value: step)
      }
    }
  }

  @ViewBuilder
  private var stepContent: some View {
    switch step {
    case 0:
      languageStep
    case 1:
      transcriptionStep
    case 2:
      permissionsStep
    case 3:
      modesStep
    case 4:
      glossaryStep
    default:
      themeStep
    }
  }

  private var footer: some View {
    HStack {
      Button {
        finish()
      } label: {
        Text(settingsStore.text(.onboardingSkip))
          .font(.caption)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)

      Spacer()

      if step > 0 {
        Button {
          withAnimation { step -= 1 }
        } label: {
          Label(
            settingsStore.text(.onboardingBack),
            systemImage: "chevron.left"
          )
        }
      }

      if step < totalSteps - 1 {
        Button {
          withAnimation { step += 1 }
        } label: {
          Label(
            settingsStore.text(.onboardingNext),
            systemImage: "chevron.right"
          )
        }
        .buttonStyle(.borderedProminent)
        .disabled(step == 1 && !transcriptionSetupIsReady)
      } else {
        Button {
          finish()
        } label: {
          Label(
            settingsStore.text(.onboardingGetStarted),
            systemImage: "checkmark"
          )
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 14)
  }

  // MARK: - Step 0: Language

  private var languageStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(spacing: 7) {
        Text(settingsStore.text(.onboardingWelcomeTitle))
          .font(.largeTitle.bold())
        Text(settingsStore.text(.onboardingChooseLanguageTitle))
          .font(.title2.weight(.semibold))
        Text(settingsStore.text(.onboardingChooseLanguageHint))
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .multilineTextAlignment(.center)

      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 145))],
        spacing: 10
      ) {
        ForEach(UILanguagePreference.allCases, id: \.self) { language in
          LanguageChip(
            language: language,
            isSelected: settingsStore.settings.uiLanguage == language
          ) {
            settingsStore.update { $0.uiLanguage = language }
          }
        }
      }

      Text(
        settingsStore.formattedText(
          .onboardingLanguageNote,
          settingsStore.settings.uiLanguage.displayName
        )
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 28)
  }

  // MARK: - Step 1: Transcription

  private var transcriptionStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      stepHeader(
        icon: "waveform.and.magnifyingglass",
        title: settingsStore.text(.onboardingHowToTranscribe),
        subtitle: transcriptionModelStore.usesGeminiCloud
          ? settingsStore.text(.onboardingCloudBody)
          : settingsStore.text(.onboardingLocalBody)
      )

      HStack(spacing: 12) {
        backendButton(
          backend: .localWhisper,
          icon: "internaldrive",
          title: settingsStore.text(.onboardingLocalTitle),
          body: settingsStore.text(.onboardingLocalBody),
          tint: .blue
        )

        backendButton(
          backend: .geminiCloud,
          icon: "cloud",
          title: settingsStore.text(.onboardingCloudTitle),
          body: settingsStore.text(.onboardingCloudBody),
          tint: .green
        )
      }

      if transcriptionModelStore.usesGeminiCloud {
        cloudSetup
      } else {
        localModelSetup
      }
    }
    .padding(.horizontal, 28)
  }

  private func backendButton(
    backend: TranscriptionBackend,
    icon: String,
    title: String,
    body: String,
    tint: Color
  ) -> some View {
    let isSelected = transcriptionModelStore.settings.backend == backend

    return Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        transcriptionModelStore.setBackend(backend)
      }
    } label: {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: icon)
          .font(.title2)
          .foregroundStyle(tint)
          .frame(width: 30)

        VStack(alignment: .leading, spacing: 5) {
          HStack {
            Text(title)
              .font(.headline)
            Spacer()
            Image(
              systemName: isSelected
                ? "checkmark.circle.fill"
                : "circle"
            )
            .foregroundStyle(isSelected ? tint : .secondary)
          }
          Text(body)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(
            isSelected
              ? tint.opacity(0.12)
              : Color.secondary.opacity(0.05)
          )
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(
            isSelected ? tint : Color.secondary.opacity(0.18),
            lineWidth: isSelected ? 2 : 1
          )
      }
    }
    .buttonStyle(.plain)
  }

  private var localModelSetup: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(settingsStore.text(.onboardingLocalBody))
        .font(.subheadline)
        .foregroundStyle(.secondary)

      ForEach(onboardingModels) { model in
        onboardingModelRow(model)
      }
    }
    .padding(.top, 2)
  }

  /// Model shown with the green "RECOMMENDED" badge in the onboarding list.
  private static let recommendedOnboardingModelID = "parakeet-tdt-06b-v3"

  private var onboardingModels: [TranscriptionModelDescriptor] {
    let preferredIDs = [
      "parakeet-tdt-06b-v3",
      "whisperkit-medium-multilingual",
      "whisperkit-large-v3-full",
    ]
    let activeModel = transcriptionModelStore.activeModel
    let preferredModels = preferredIDs.compactMap { id in
      transcriptionModelStore.models.first { $0.id == id }
    }

    return ([activeModel].compactMap { $0 } + preferredModels)
      .uniqued(by: \.id)
      .prefix(3)
      .map { $0 }
  }

  private func onboardingModelRow(
    _ model: TranscriptionModelDescriptor
  ) -> some View {
    let installation = transcriptionModelStore.installationState(for: model)
    let isActive = transcriptionModelStore.settings.activeModelID == model.id

    return HStack(alignment: .top, spacing: 12) {
      Image(systemName: "waveform")
        .font(.title3)
        .foregroundStyle(.blue)
        .frame(width: 26)

      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 7) {
          Text(model.displayName)
            .font(.subheadline.weight(.semibold))

          if model.id == Self.recommendedOnboardingModelID {
            statusBadge(settingsStore.text(.badgeRecommended), tint: .blue)
          } else if let badge = model.badge {
            statusBadge(badge, tint: .blue)
          }

          if isActive {
            statusBadge(
              settingsStore.text(.active),
              tint: .green
            )
          }
        }

        Text(model.description)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Label(model.downloadSize, systemImage: "internaldrive")
          .font(.caption2)
          .foregroundStyle(.secondary)

        if installation.status == .downloading {
          ProgressView(value: installation.progressFraction)
            .frame(maxWidth: 240)
        } else if installation.status == .failed,
          let errorMessage = installation.errorMessage
        {
          Text(errorMessage)
            .font(.caption2)
            .foregroundStyle(.red)
            .lineLimit(2)
        }
      }

      Spacer(minLength: 12)
      modelAction(model, installation: installation, isActive: isActive)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(Color.secondary.opacity(0.05))
    )
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color.secondary.opacity(0.15))
    }
  }

  @ViewBuilder
  private func modelAction(
    _ model: TranscriptionModelDescriptor,
    installation: TranscriptionModelInstallationState,
    isActive: Bool
  ) -> some View {
    switch installation.status {
    case .notDownloaded:
      Button {
        Task {
          await transcriptionModelStore.download(model)
        }
      } label: {
        Label(
          settingsStore.text(.download),
          systemImage: "arrow.down.circle"
        )
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)

    case .downloading:
      Text(settingsStore.text(.downloading))
        .font(.caption)
        .foregroundStyle(.secondary)

    case .downloaded:
      if isActive {
        Image(systemName: "checkmark.circle.fill")
          .font(.title3)
          .foregroundStyle(.green)
          .accessibilityLabel(settingsStore.text(.active))
      } else {
        Button(settingsStore.text(.use)) {
          transcriptionModelStore.activate(model)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }

    case .failed:
      Button {
        Task {
          await transcriptionModelStore.download(model)
        }
      } label: {
        Label(
          settingsStore.text(.retry),
          systemImage: "arrow.clockwise"
        )
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
  }

  private var cloudSetup: some View {
    let google = polishingEngineStore.apiSettings.configuration(for: .google)
    let keyCount = configuredGoogleKeyCount

    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Google Gemini", systemImage: "key")
          .font(.headline)
        Spacer()
        Text(
          keyCount > 1
            ? settingsStore.formattedText(.apiKeysCountLabel, "\(keyCount)")
            : keyCount == 1
              ? settingsStore.text(.keyConfigured)
              : settingsStore.text(.noAPIKey)
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(google.hasAPIKey ? .green : .orange)
      }

      Text(settingsStore.text(.onboardingCloudBody))
        .font(.subheadline)
        .foregroundStyle(.secondary)

      if keyCount > 0 && !showsAddGoogleKeyForm {
        HStack(spacing: 10) {
          Label(
            keyCount > 1
              ? settingsStore.formattedText(.apiKeysCountLabel, "\(keyCount)")
              : settingsStore.text(.keyConfigured),
            systemImage: google.hasAPIKey
              ? "checkmark.shield.fill"
              : "exclamationmark.shield.fill"
          )
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(google.hasAPIKey ? .green : .orange)

          Spacer()

          if google.apiKeys.count < 10 {
            Button {
              showsAddGoogleKeyForm = true
            } label: {
              Label(settingsStore.text(.addKey), systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        }
        .padding(11)
        .background(
          RoundedRectangle(cornerRadius: 9)
            .fill(Color.green.opacity(0.08))
        )
      } else {
        googleAPIKeyForm
      }

      if let apiKeyURL = APIProviderKind.google.getAPIKeyURL {
        Link(destination: apiKeyURL) {
          Label(
            settingsStore.text(.getAPIKey),
            systemImage: "arrow.up.right.square"
          )
          .font(.caption)
        }
      }

      Text(settingsStore.text(.googleAPIBody))
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color.green.opacity(0.07))
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.green.opacity(0.25))
    }
  }

  private var googleAPIKeyForm: some View {
    HStack(spacing: 8) {
      Group {
        if showsGoogleAPIKey {
          TextField(
            settingsStore.text(.enterAPIKey),
            text: $googleAPIKey
          )
        } else {
          SecureField(
            settingsStore.text(.enterAPIKey),
            text: $googleAPIKey
          )
        }
      }
      .textFieldStyle(.roundedBorder)

      Button {
        showsGoogleAPIKey.toggle()
      } label: {
        Image(
          systemName: showsGoogleAPIKey
            ? "eye.slash"
            : "eye"
        )
      }
      .buttonStyle(.bordered)
      .accessibilityLabel(
        settingsStore.text(
          showsGoogleAPIKey ? .hideAPIKey : .showAPIKey
        )
      )

      if configuredGoogleKeyCount > 0 {
        Button {
          googleAPIKey = ""
          showsAddGoogleKeyForm = false
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(settingsStore.text(.cancel))
      }

      Button(settingsStore.text(.save)) {
        saveGoogleAPIKey()
      }
      .buttonStyle(.borderedProminent)
      .disabled(
        googleAPIKey
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty
      )
    }
  }

  private var configuredGoogleKeyCount: Int {
    polishingEngineStore.apiSettings
      .configuration(for: .google)
      .configuredAPIKeyCount
  }

  private var transcriptionSetupIsReady: Bool {
    if transcriptionModelStore.usesGeminiCloud {
      return polishingEngineStore.apiSettings
        .configuration(for: .google)
        .hasAPIKey
    }

    guard let activeModel = transcriptionModelStore.activeModel else {
      return false
    }

    return transcriptionModelStore.installationState(for: activeModel).isDownloaded
      || transcriptionModelStore.hasLocalFiles(for: activeModel)
  }

  // MARK: - Step 2: Permissions

  private var permissionsStep: some View {
    VStack(alignment: .leading, spacing: 14) {
      stepHeader(
        icon: "lock.shield",
        title: settingsStore.text(.onboardingPermissionsTitle),
        subtitle: settingsStore.text(.onboardingPermissionsBody)
      )

      permissionCard(
        icon: "waveform.circle",
        title: audioRecorder.inputDeviceStatus.deviceName
          ?? settingsStore.text(.onboardingMicrophone),
        detail: audioRecorder.inputDeviceStatus.isAvailable
          ? settingsStore.text(.audioInputReady)
          : settingsStore.text(.audioInputNoDevice),
        isGranted: audioRecorder.inputDeviceStatus.isAvailable,
        actionTitle: settingsStore.text(.refreshAudioInput)
      ) {
        audioRecorder.refreshInputDeviceStatus()
      }

      permissionCard(
        icon: "mic",
        title: settingsStore.text(.onboardingMicrophone),
        detail: micGranted
          ? settingsStore.text(.audioInputReady)
          : settingsStore.text(.microphoneAccessDisabled),
        isGranted: micGranted,
        actionTitle: settingsStore.text(.onboardingPermissionsGrant)
      ) {
        requestMicrophonePermission()
      }

      permissionCard(
        icon: "accessibility",
        title: settingsStore.text(.onboardingAccessibility),
        detail: accessibility.isTrusted
          ? settingsStore.text(.accessibilityTrusted)
          : settingsStore.text(.accessibilityNotTrusted),
        isGranted: accessibility.isTrusted,
        actionTitle: settingsStore.text(.onboardingPermissionsGrant)
      ) {
        accessibility.requestPermission()
      }
    }
    .padding(.horizontal, 28)
  }

  private func permissionCard(
    icon: String,
    title: String,
    detail: String,
    isGranted: Bool,
    actionTitle: String,
    action: @escaping () -> Void
  ) -> some View {
    HStack(alignment: .center, spacing: 13) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundStyle(isGranted ? .green : .orange)
        .frame(width: 32)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if isGranted {
        Image(systemName: "checkmark.circle.fill")
          .font(.title3)
          .foregroundStyle(.green)
      } else {
        Button(actionTitle, action: action)
          .buttonStyle(.bordered)
          .controlSize(.small)
      }
    }
    .padding(13)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(Color.secondary.opacity(0.05))
    )
  }

  // MARK: - Step 3: Modes and hotkeys

  private var modesStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      stepHeader(
        icon: "rectangle.3.group",
        title: settingsStore.text(.onboardingModesTitle),
        subtitle: settingsStore.text(.onboardingModesBody)
      )

      Toggle(
        settingsStore.text(.enableHotkey),
        isOn: $hotkeySettingsStore.settings.enabled
      )
      .toggleStyle(.switch)
      .padding(.vertical, 2)

      modeCard(
        id: "main",
        icon: "macwindow",
        title: settingsStore.text(.helpModeWindowTitle),
        body: settingsStore.text(.helpModeWindowBody),
        shortcut: nil
      )

      modeCard(
        id: "hotkey",
        icon: "keyboard",
        title: settingsStore.text(.helpModeHotkeyTitle),
        body: settingsStore.text(.helpModeHotkeyBody),
        shortcut: HotkeySettings.displayString(
          for: hotkeySettingsStore.settings.hotkey
        ),
        actionTitle: settingsStore.text(.record)
      ) {
        tryMode(notification: .nativeSmartScribeHotkeyTriggered)
      }

      modeCard(
        id: "floating",
        icon: "character.bubble",
        title: settingsStore.text(.helpModeFloatTitle),
        body: settingsStore.text(.helpModeFloatBody),
        shortcut: HotkeySettings.displayString(
          for: hotkeySettingsStore.settings.secondaryHotkey
        ),
        actionTitle: settingsStore.text(.translate)
      ) {
        tryMode(notification: .nativeSmartScribeTargetHotkeyTriggered)
      }

      modeCard(
        id: "quick",
        icon: "text.bubble.fill",
        title: settingsStore.text(.helpModeQuickTitle),
        body: settingsStore.text(.helpModeQuickBody),
        shortcut: HotkeySettings.displayString(
          for: hotkeySettingsStore.settings.tertiaryHotkey
        ),
        actionTitle: settingsStore.text(.translate)
      ) {
        tryMode(
          notification: .nativeSmartScribeQuickTranslationHotkeyTriggered
        )
      }
    }
    .padding(.horizontal, 28)
  }

  private func modeCard(
    id: String,
    icon: String,
    title: String,
    body: String,
    shortcut: String?,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
  ) -> some View {
    let isExpanded = expandedModeID == id

    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.title3)
          .foregroundStyle(.tint)
          .frame(width: 28)

        Text(title)
          .font(.subheadline.weight(.semibold))

        Spacer()

        if let shortcut {
          Text(shortcut)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }

        Image(systemName: "chevron.down")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .rotationEffect(.degrees(isExpanded ? 180 : 0))
      }
      .contentShape(Rectangle())
      .onTapGesture {
        withAnimation(.easeInOut(duration: 0.2)) {
          expandedModeID = isExpanded ? nil : id
        }
      }

      if isExpanded {
        HStack(alignment: .bottom, spacing: 12) {
          Text(body)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

          Spacer(minLength: 16)

          if let actionTitle, let action {
            Button(action: action) {
              Label(actionTitle, systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
          }
        }
        .padding(.top, 10)
        .padding(.leading, 40)
      }
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(Color.secondary.opacity(0.05))
    )
  }

  // MARK: - Step 4: Glossary

  private var glossaryStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      stepHeader(
        icon: "book.closed",
        title: settingsStore.text(.onboardingGlossaryTitle),
        subtitle: settingsStore.formattedText(
          .onboardingGlossaryBody,
          glossaryLanguageName(
            for: settingsStore.settings.uiLanguage
          )
        )
      )

      VStack(alignment: .leading, spacing: 10) {
        Text(settingsStore.text(.onboardingGlossaryExplanation))
          .font(.body)
          .fixedSize(horizontal: false, vertical: true)

        Label(
          settingsStore.text(.helpPrivacyLocal),
          systemImage: "lock.shield"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .padding(15)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(Color.blue.opacity(0.07))
      )

      if glossaryCreated {
        HStack {
          Label(
            settingsStore.text(.onboardingGlossaryCreated),
            systemImage: "checkmark.circle.fill"
          )
          .foregroundStyle(.green)

          Spacer()

          Text(glossaryStore.settings.authorTranscriptionLanguage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
      } else {
        Button {
          createGlossary()
        } label: {
          Label(
            settingsStore.text(.onboardingGlossaryCreate),
            systemImage: "plus.circle"
          )
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(.horizontal, 28)
  }

  // MARK: - Step 5: Theme

  private var themeStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      stepHeader(
        icon: "paintbrush",
        title: settingsStore.text(.onboardingThemeTitle),
        subtitle: settingsStore.text(.onboardingThemeBody)
      )

      HStack(spacing: 12) {
        themeCard(
          icon: "sun.max",
          label: settingsStore.text(.themeLight),
          theme: .light
        )
        themeCard(
          icon: "moon",
          label: settingsStore.text(.themeDark),
          theme: .dark
        )
        themeCard(
          icon: "circle.lefthalf.filled",
          label: settingsStore.text(.themeSystem),
          theme: .system
        )
      }
    }
    .padding(.horizontal, 28)
  }

  // MARK: - Shared components

  private func stepHeader(
    icon: String,
    title: String,
    subtitle: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: icon)
        .font(.largeTitle)
        .foregroundStyle(.tint)
      Text(title)
        .font(.title2.bold())
      Text(subtitle)
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func statusBadge(_ text: String, tint: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(tint.opacity(0.14), in: Capsule())
      .foregroundStyle(tint)
  }

  private func themeCard(
    icon: String,
    label: String,
    theme: ThemePreference
  ) -> some View {
    let isSelected = settingsStore.settings.theme == theme

    return Button {
      settingsStore.update { $0.theme = theme }
    } label: {
      VStack(spacing: 10) {
        Image(systemName: icon)
          .font(.largeTitle)
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        Text(label)
          .font(.subheadline.weight(.semibold))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 24)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(
            isSelected
              ? Color.accentColor.opacity(0.12)
              : Color.secondary.opacity(0.05)
          )
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(
            isSelected ? Color.accentColor : .clear,
            lineWidth: 2
          )
      }
    }
    .buttonStyle(.plain)
  }

  // MARK: - Actions

  private func refreshSetupState() {
    transcriptionModelStore.reconcileModelStates()
    glossaryCreated = glossaryStore.settings.enabled
    refreshPermissions()
  }

  private func refreshPermissions() {
    micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    audioRecorder.refreshInputDeviceStatus()
    accessibility.refresh()
  }

  private func requestMicrophonePermission() {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async {
          micGranted = granted
          audioRecorder.refreshInputDeviceStatus()
        }
      }
    case .denied, .restricted:
      if let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
      ) {
        NSWorkspace.shared.open(url)
      }
    case .authorized:
      refreshPermissions()
    @unknown default:
      refreshPermissions()
    }
  }

  private func saveGoogleAPIKey() {
    let trimmedKey =
      googleAPIKey
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedKey.isEmpty else { return }

    var configuration = polishingEngineStore.apiSettings
      .configuration(for: .google)
    if configuredGoogleKeyCount > 0 && showsAddGoogleKeyForm {
      configuration.addKey(trimmedKey)
    } else {
      configuration.apiKey = trimmedKey
    }
    if configuration.textModel
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty
    {
      configuration.textModel = APIProviderKind.google.defaultTextModel
    }
    polishingEngineStore.updateAPIConfiguration(
      configuration,
      for: .google
    )
    transcriptionModelStore.setBackend(.geminiCloud)
    if hotkeySettingsStore.settings.target == .raw {
      hotkeySettingsStore.settings.target = .note
    }
    googleAPIKey = ""
    showsAddGoogleKeyForm = false
  }

  private func tryMode(notification: Notification.Name) {
    hotkeySettingsStore.settings.enabled = true
    NotificationCenter.default.post(name: notification, object: nil)
  }

  private func createGlossary() {
    let languageName = glossaryLanguageName(
      for: settingsStore.settings.uiLanguage
    )
    glossaryStore.setAuthorTranscriptionLanguage(languageName)
    glossaryStore.setEnabled(true)
    withAnimation { glossaryCreated = true }
  }

  private func finish() {
    settingsStore.update { $0.hasCompletedOnboarding = true }
    dismiss()
  }

  private func glossaryLanguageName(
    for language: UILanguagePreference
  ) -> String {
    let code =
      language == .system
      ? language.resolvedLocaleIdentifier()
      : language.rawValue

    switch code {
    case "ru": return "Russian"
    case "es": return "Spanish"
    case "de": return "German"
    case "fr": return "French"
    case "it": return "Italian"
    case "pt": return "Portuguese"
    case "zh": return "Chinese"
    case "ja": return "Japanese"
    case "ko": return "Korean"
    case "ar": return "Arabic"
    case "hi": return "Hindi"
    default: return "English"
    }
  }
}

private struct LanguageChip: View {
  let language: UILanguagePreference
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(language.displayName)
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .fill(
              isSelected
                ? Color.accentColor.opacity(0.15)
                : Color.secondary.opacity(0.06)
            )
        )
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(
              isSelected ? Color.accentColor : .clear,
              lineWidth: 1.5
            )
        }
    }
    .buttonStyle(.plain)
  }
}

extension Array {
  fileprivate func uniqued<Value: Hashable>(
    by keyPath: KeyPath<Element, Value>
  ) -> [Element] {
    var seen = Set<Value>()
    return filter { seen.insert($0[keyPath: keyPath]).inserted }
  }
}
