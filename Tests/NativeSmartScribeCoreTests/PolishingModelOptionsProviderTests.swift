import XCTest

@testable import NativeSmartScribeCore

final class PolishingModelOptionsProviderTests: XCTestCase {
  private func makeProvider(
    googleModel: String = "gemini-3.5-flash",
    openRouterModel: String = "openai/gpt-4o-mini",
    customModel: String = ""
  ) -> PolishingModelOptionsProvider {
    var settings = APIProviderSettings()
    settings.setConfiguration(
      APIProviderConfiguration(apiKey: "key", textModel: googleModel), for: .google)
    settings.setConfiguration(
      APIProviderConfiguration(apiKey: "key", textModel: openRouterModel), for: .openRouter)
    settings.setConfiguration(
      APIProviderConfiguration(apiKey: "key", textModel: customModel, baseURL: "https://x.test/v1"),
      for: .custom)
    return PolishingModelOptionsProvider(apiSettings: settings)
  }

  func testCleanModelDisplayNameStripsVendorPrefix() {
    let provider = makeProvider()
    XCTAssertEqual(provider.cleanModelDisplayName("google/gemini-2.5-flash"), "gemini-2.5-flash")
    XCTAssertEqual(provider.cleanModelDisplayName("anthropic/claude-3.5-haiku"), "claude-3.5-haiku")
  }

  func testCleanModelDisplayNameWithoutSlashIsUnchanged() {
    let provider = makeProvider()
    XCTAssertEqual(provider.cleanModelDisplayName("gpt-4o-mini"), "gpt-4o-mini")
    XCTAssertEqual(provider.cleanModelDisplayName(""), "")
  }

  func testMatchesProviderHeuristics() {
    let provider = makeProvider()
    XCTAssertTrue(provider.matchesProvider(modelID: "gemini-2.5-flash", kind: .google))
    XCTAssertTrue(provider.matchesProvider(modelID: "gpt-4o-mini", kind: .openAI))
    XCTAssertTrue(provider.matchesProvider(modelID: "qwen3.7-plus", kind: .qwen))
    XCTAssertTrue(provider.matchesProvider(modelID: "claude-3-5-haiku", kind: .anthropic))
    XCTAssertTrue(provider.matchesProvider(modelID: "literally-anything", kind: .custom))
    XCTAssertFalse(provider.matchesProvider(modelID: "gemini-2.5-flash", kind: .openAI))
  }

  func testMatchesProviderRejectsSlashedIDsForNonRouterProviders() {
    let provider = makeProvider()
    XCTAssertFalse(provider.matchesProvider(modelID: "google/gemini-2.5-flash", kind: .google))
    XCTAssertTrue(provider.matchesProvider(modelID: "google/gemini-2.5-flash", kind: .openRouter))
    XCTAssertFalse(provider.matchesProvider(modelID: "gpt-4o-mini", kind: .openRouter))
  }

  func testProviderModelOptionsFiltersToFavoritesAndKeepsCurrentFirst() {
    let provider = makeProvider(googleModel: "gemini-2.5-flash")
    let options = provider.providerModelOptions(for: .google, favorites: ["gemini-2.0-flash"])

    XCTAssertEqual(options.map(\.id), ["gemini-2.5-flash", "gemini-2.0-flash"])
  }

  func testProviderModelOptionsFallsBackToBuiltInListWhenNoFavorites() {
    let provider = makeProvider(googleModel: "gemini-3.5-flash")
    let options = provider.providerModelOptions(for: .google, favorites: [])

    XCTAssertEqual(options.count, provider.availableModels(for: .google).count)
    XCTAssertEqual(options.first?.id, "gemini-3.5-flash")
  }

  func testProviderModelOptionsAppendsUnknownFavoriteMatchingProvider() {
    let provider = makeProvider(googleModel: "gemini-3.5-flash")
    let options = provider.providerModelOptions(for: .google, favorites: ["gemini-9.9-ultra"])

    XCTAssertTrue(options.contains { $0.id == "gemini-9.9-ultra" })
    XCTAssertEqual(options.first?.id, "gemini-3.5-flash")
  }

  func testProviderModelOptionsForCustomProviderShowsCurrentModel() {
    let provider = makeProvider(customModel: "my-custom-model")
    let options = provider.providerModelOptions(for: .custom, favorites: [])

    XCTAssertEqual(options.map(\.id), ["my-custom-model"])
  }

  func testProviderModelOptionsProducesUniqueCleanedDisplayNames() {
    let provider = makeProvider()
    let favoriteIDs = Set(provider.availableModels(for: .openRouter).map(\.id))
    let options = provider.providerModelOptions(for: .openRouter, favorites: favoriteIDs)

    let keys = options.map { provider.cleanModelDisplayName($0.displayName).lowercased() }
    XCTAssertEqual(keys.count, Set(keys).count, "expected de-duplicated display names")
  }

  func testModelDisplayNameReturnsEmptyForEmptyIDSoCallerCanLocalize() {
    let provider = makeProvider()
    XCTAssertEqual(provider.modelDisplayName(id: "", kind: .google), "")
    XCTAssertEqual(provider.modelDisplayName(id: "gemini-2.5-flash", kind: .google), "Gemini 2.5 Flash")
    XCTAssertEqual(
      provider.modelDisplayName(id: "google/gemini-2.5-flash", kind: .openRouter),
      "Gemini 2.5 Flash")
  }

  // MARK: - Additional coverage for newly introduced behavior

  func testMatchesProviderOpenAIReasoningAndVendorIDs() {
    let provider = makeProvider()
    XCTAssertTrue(provider.matchesProvider(modelID: "o3-mini", kind: .openAI))
    XCTAssertTrue(provider.matchesProvider(modelID: "o1-preview", kind: .openAI))
    XCTAssertTrue(provider.matchesProvider(modelID: "gpt-4o", kind: .openAI))
    // A slashed id is an OpenRouter-style route, never a native OpenAI model.
    XCTAssertFalse(provider.matchesProvider(modelID: "openai/gpt-4o", kind: .openAI))
  }

  func testMatchesProviderQwenCoversDeepSeekAndGLMFamilies() {
    let provider = makeProvider()
    XCTAssertTrue(provider.matchesProvider(modelID: "deepseek-v3", kind: .qwen))
    XCTAssertTrue(provider.matchesProvider(modelID: "glm-4-plus", kind: .qwen))
    XCTAssertTrue(provider.matchesProvider(modelID: "qwen-turbo", kind: .qwen))
    XCTAssertFalse(provider.matchesProvider(modelID: "gemini-2.5-flash", kind: .qwen))
  }

  func testMatchesProviderAnthropicRejectsSlashedIDs() {
    let provider = makeProvider()
    XCTAssertTrue(provider.matchesProvider(modelID: "claude-3-5-haiku-latest", kind: .anthropic))
    XCTAssertTrue(provider.matchesProvider(modelID: "anthropic/claude-x", kind: .openRouter))
    XCTAssertFalse(provider.matchesProvider(modelID: "anthropic/claude-3.5-haiku", kind: .anthropic))
  }

  func testModelDisplayNameFallsBackToCleanedIDForUnknownModel() {
    let provider = makeProvider()
    // Unknown OpenRouter route → vendor prefix stripped, raw id preserved.
    XCTAssertEqual(provider.modelDisplayName(id: "google/gemini-9.9-ultra", kind: .openRouter),
      "gemini-9.9-ultra")
    // Unknown native id is returned cleaned (no slash to strip).
    XCTAssertEqual(provider.modelDisplayName(id: "gemini-9.9-ultra", kind: .google),
      "gemini-9.9-ultra")
  }

  func testAvailableModelsAreNonEmptyForCuratedProviders() {
    let provider = makeProvider()
    XCTAssertFalse(provider.availableModels(for: .anthropic).isEmpty)
    XCTAssertFalse(provider.availableModels(for: .qwen).isEmpty)
    XCTAssertFalse(provider.availableModels(for: .openRouter).isEmpty)
  }

  func testProviderModelOptionsForCustomWithEmptyModelYieldsSingleEmptyOption() {
    let provider = makeProvider(customModel: "")
    let options = provider.providerModelOptions(for: .custom, favorites: [])
    // An unconfigured custom provider still surfaces exactly one (empty) row so
    // the UI can render a localized placeholder rather than an empty menu.
    XCTAssertEqual(options.count, 1)
    XCTAssertEqual(options.first?.id, "")
  }

  func testProviderModelOptionsIgnoresFavoritesFromOtherProviders() {
    let provider = makeProvider(googleModel: "gemini-3.5-flash")
    // "gpt-4o" belongs to OpenAI, not Google, so it must not leak into Google's
    // options even though it is favorited globally.
    let options = provider.providerModelOptions(for: .google, favorites: ["gpt-4o"])
    XCTAssertFalse(options.contains { $0.id == "gpt-4o" })
    XCTAssertEqual(options.map(\.id), Array(provider.availableModels(for: .google).map(\.id)))
  }
}
