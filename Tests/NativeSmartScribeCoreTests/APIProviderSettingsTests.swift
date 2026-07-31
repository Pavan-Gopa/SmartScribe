import Foundation
import NativeSmartScribeCore
import Testing

@Test
func apiProviderSettingsExposeDefaultProviderModels() {
  let settings = APIProviderSettings()

  #expect(settings.google.textModel == "gemini-3.5-flash")
  #expect(settings.openAI.textModel == "gpt-4o-mini")
  #expect(settings.qwen.textModel == "qwen3.7-plus")
  #expect(settings.openRouter.textModel == "openai/gpt-4o-mini")
  #expect(settings.openRouter.baseURL == "https://openrouter.ai/api/v1")
}

@Test
func apiProviderSettingsUIOrderIsGoogleOpenAIQwenOpenRouterCustom() {
  #expect(
    APIProviderKind.polishingUICases == [
      .google, .openAI, .qwen, .openRouter, .custom,
    ])
  #expect(!APIProviderKind.polishingUICases.contains(.anthropic))
}

@Test
func apiProviderSettingsRequireCredentialsBeforeProviderIsAvailable() {
  var settings = APIProviderSettings()

  #expect(settings.availablePolishingProviders.isEmpty)

  settings.google.apiKey = "google-key"
  settings.openAI.apiKey = "openai-key"
  settings.qwen.apiKey = "qwen-key"
  settings.openRouter.apiKey = "or-key"
  settings.custom.name = "Private"
  settings.custom.apiKey = "custom-key"
  settings.custom.baseURL = "https://example.com/v1"
  settings.custom.textModel = "my-model"

  #expect(
    settings.availablePolishingProviders.map(\.kind) == [
      .google, .openAI, .qwen, .openRouter, .custom,
    ])
}

@Test
func apiProviderSettingsResolvePolishingEngineIDs() {
  #expect(APIProviderKind.google.polishingEngineID == "cloud-google")
  #expect(APIProviderKind.openAI.polishingEngineID == "cloud-openai")
  #expect(APIProviderKind.qwen.polishingEngineID == "cloud-qwen")
  #expect(APIProviderKind.openRouter.polishingEngineID == "cloud-openrouter")
  #expect(APIProviderKind.custom.polishingEngineID == "cloud-custom")
  #expect(APIProviderKind(polishingEngineID: "cloud-qwen") == .qwen)
}

@Test
func apiProviderSettingsDecodeWithoutQwenField() throws {
  let json = """
    {
      "google": {"apiKey":"","textModel":"gemini-2.5-flash","baseURL":"","name":""},
      "openAI": {"apiKey":"","textModel":"gpt-4o-mini","baseURL":"","name":""},
      "anthropic": {"apiKey":"","textModel":"claude-3-haiku-20240307","baseURL":"","name":""},
      "custom": {"apiKey":"","textModel":"","baseURL":"","name":""}
    }
    """.data(using: .utf8)!
  let settings = try JSONDecoder().decode(APIProviderSettings.self, from: json)
  #expect(settings.qwen.baseURL.contains("token-plan"))
  #expect(settings.qwen.textModel == "qwen3.7-plus")
  #expect(settings.openRouter.baseURL == "https://openrouter.ai/api/v1")
}

@Test
func apiProviderSettingsSupportsMultipleKeysAndBackwardsCompatibility() throws {
  var config = APIProviderConfiguration(apiKey: "key1")
  #expect(config.apiKeys == ["key1"])
  #expect(config.apiKey == "key1")

  config.addKey("key2")
  config.addKey("key3")
  #expect(config.apiKeys == ["key1", "key2", "key3"])
  #expect(config.sanitizedAPIKeys == ["key1", "key2", "key3"])
  #expect(config.apiKey == "key1")

  // Test max key limit (10)
  for i in 4...12 {
    config.addKey("key\(i)")
  }
  #expect(config.apiKeys.count == 10)

  // Test JSON encoding and decoding
  let encoder = JSONEncoder()
  let decoder = JSONDecoder()
  let data = try encoder.encode(config)
  let decoded = try decoder.decode(APIProviderConfiguration.self, from: data)

  #expect(decoded.apiKeys == config.apiKeys)
  #expect(decoded.apiKey == "key1")
}

@Test
func apiProviderSettingsSupportsTogglingDisabledKeys() {
  var config = APIProviderConfiguration(apiKeys: ["key1", "key2", "key3"])
  #expect(config.sanitizedAPIKeys == ["key1", "key2", "key3"])
  #expect(config.configuredAPIKeyCount == 3)

  // Disable key2
  config.toggleKeyDisabled(at: 1)
  #expect(config.isKeyDisabled(at: 1) == true)
  #expect(config.cleanKey(at: 1) == "key2")
  #expect(config.sanitizedAPIKeys == ["key1", "key3"])
  #expect(config.configuredAPIKeyCount == 3)

  // Test disable all except key3
  config.disableAllKeysExcept(at: 2)
  #expect(config.isKeyDisabled(at: 0) == true)
  #expect(config.isKeyDisabled(at: 1) == true)
  #expect(config.isKeyDisabled(at: 2) == false)
  #expect(config.sanitizedAPIKeys == ["key3"])
  #expect(config.apiKey == "key3")

  // Enable all keys
  config.enableAllKeys()
  #expect(config.sanitizedAPIKeys == ["key1", "key2", "key3"])
}

@Test
func apiProviderConfiguredKeyCountIgnoresBlankEntries() {
  let config = APIProviderConfiguration(
    apiKeys: ["key1", "  ", "\(APIProviderConfiguration.disabledPrefix)key2"]
  )

  #expect(config.configuredAPIKeyCount == 2)
  #expect(config.sanitizedAPIKeys == ["key1"])
}

@Test
func apiProviderSettingsDeduplicatesAvailablePolishingProviders() {
  var settings = APIProviderSettings()
  settings.qwen.apiKey = "qwen-key"
  settings.qwen.textModel = "qwen3.7-plus"

  // Custom provider with same display name or kind as Qwen
  settings.custom.name = "Qwen"
  settings.custom.apiKey = "custom-key"
  settings.custom.baseURL = "https://example.com/v1"
  settings.custom.textModel = "custom-model"

  let available = settings.availablePolishingProviders
  let names = available.map(\.displayName)
  #expect(names.count == Set(names).count)
}
