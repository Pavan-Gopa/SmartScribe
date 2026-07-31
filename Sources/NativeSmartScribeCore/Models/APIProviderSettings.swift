import Foundation

public enum APIProviderKind: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
  case google
  case openAI
  case anthropic  // kept for migration of stored settings; hidden in UI
  case qwen
  case openRouter
  case custom

  public var id: String { rawValue }

  /// Providers shown in Settings > API Providers (fixed order).
  /// Google → OpenAI → Qwen → OpenRouter → Custom.
  public static let polishingUICases: [APIProviderKind] = [.google, .openAI, .qwen, .openRouter, .custom]

  public var displayName: String {
    switch self {
    case .google: "Google"
    case .openAI: "OpenAI"
    case .anthropic: "Anthropic"
    case .qwen: "Qwen"
    case .openRouter: "OpenRouter"
    case .custom: "Custom"
    }
  }

  public var polishingEngineID: String {
    switch self {
    case .google: "cloud-google"
    case .openAI: "cloud-openai"
    case .anthropic: "cloud-anthropic"
    case .qwen: "cloud-qwen"
    case .openRouter: "cloud-openrouter"
    case .custom: "cloud-custom"
    }
  }

  public var getAPIKeyURL: URL? {
    switch self {
    case .google: URL(string: "https://aistudio.google.com/app/apikey")
    case .openAI: URL(string: "https://platform.openai.com/api-keys")
    case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
    case .qwen: URL(string: "https://modelstudio.console.alibabacloud.com/")
    case .openRouter: URL(string: "https://openrouter.ai/keys")
    case .custom: nil
    }
  }

  public var defaultTextModel: String {
    switch self {
    case .google: "gemini-3.5-flash"
    case .openAI: "gpt-4o-mini"
    case .anthropic: "claude-3-haiku-20240307"
    case .qwen: "qwen3.7-plus"
    case .openRouter: "openai/gpt-4o-mini"
    case .custom: ""
    }
  }

  public var defaultBaseURL: String {
    switch self {
    case .openAI: "https://api.openai.com/v1"
    case .qwen: "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
    case .openRouter: "https://openrouter.ai/api/v1"
    case .custom: ""
    case .google, .anthropic: ""
    }
  }

  public var supportsBalance: Bool {
    self == .openRouter
  }

  public var supportsPricing: Bool {
    self == .openRouter
  }

  /// OpenAI-compatible chat providers that use baseURL + Bearer auth.
  public var isOpenAICompatible: Bool {
    switch self {
    case .openAI, .qwen, .openRouter, .custom: true
    case .google, .anthropic: false
    }
  }

  public init?(polishingEngineID: String) {
    guard let kind = Self.allCases.first(where: { $0.polishingEngineID == polishingEngineID })
    else {
      return nil
    }
    self = kind
  }
}

public struct APIProviderConfiguration: Codable, Equatable, Sendable {
  public static let disabledPrefix = "#DISABLED#"

  public var apiKeys: [String]
  public var textModel: String
  public var baseURL: String
  public var name: String

  public init(
    apiKeys: [String] = [],
    apiKey: String = "",
    textModel: String = "",
    baseURL: String = "",
    name: String = ""
  ) {
    if !apiKeys.isEmpty {
      self.apiKeys = apiKeys
    } else if !apiKey.isEmpty {
      self.apiKeys = [apiKey]
    } else {
      self.apiKeys = []
    }
    self.textModel = textModel
    self.baseURL = baseURL
    self.name = name
  }

  /// Backwards-compatible primary key getter/setter.
  public var apiKey: String {
    get {
      sanitizedAPIKeys.first ?? cleanKey(apiKeys.first ?? "")
    }
    set {
      let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
      if apiKeys.isEmpty {
        if !trimmed.isEmpty {
          apiKeys = [newValue]
        }
      } else {
        let disabled = isKeyDisabled(at: 0)
        let clean = cleanKey(trimmed)
        apiKeys[0] = disabled ? "\(Self.disabledPrefix)\(clean)" : clean
      }
    }
  }

  /// Helper to get clean key value without #DISABLED# prefix
  public func cleanKey(at index: Int) -> String {
    guard apiKeys.indices.contains(index) else { return "" }
    return cleanKey(apiKeys[index])
  }

  public func cleanKey(_ raw: String) -> String {
    var key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if key.hasPrefix(Self.disabledPrefix) {
      key = String(key.dropFirst(Self.disabledPrefix.count))
    }
    return key
  }

  /// Check if key at index is disabled
  public func isKeyDisabled(at index: Int) -> Bool {
    guard apiKeys.indices.contains(index) else { return false }
    return apiKeys[index].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(
      Self.disabledPrefix)
  }

  /// Toggle disabled state of key at index
  public mutating func toggleKeyDisabled(at index: Int) {
    guard apiKeys.indices.contains(index) else { return }
    let current = apiKeys[index].trimmingCharacters(in: .whitespacesAndNewlines)
    if current.hasPrefix(Self.disabledPrefix) {
      apiKeys[index] = String(current.dropFirst(Self.disabledPrefix.count))
    } else {
      apiKeys[index] = "\(Self.disabledPrefix)\(current)"
    }
  }

  /// Enable all keys
  public mutating func enableAllKeys() {
    apiKeys = apiKeys.map { cleanKey($0) }
  }

  /// Disable all keys except at specific index
  public mutating func disableAllKeysExcept(at targetIndex: Int) {
    for i in apiKeys.indices {
      let clean = cleanKey(apiKeys[i])
      if i == targetIndex {
        apiKeys[i] = clean
      } else {
        apiKeys[i] = "\(Self.disabledPrefix)\(clean)"
      }
    }
  }

  /// All trimmed, non-empty, ENABLED ASCII valid API keys.
  public var sanitizedAPIKeys: [String] {
    apiKeys
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && !$0.hasPrefix(Self.disabledPrefix) && !$0.hasPrefix("disabled:") }
  }

  public var hasAPIKey: Bool {
    !sanitizedAPIKeys.isEmpty
  }

  /// Number of non-empty keys already stored for this provider, including
  /// temporarily disabled keys. Useful for setup UI that should not ask the
  /// user to configure credentials they have already added.
  public var configuredAPIKeyCount: Int {
    apiKeys
      .map(cleanKey)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .count
  }

  public mutating func addKey(_ key: String = "") {
    guard apiKeys.count < 10 else { return }
    apiKeys.append(key)
  }

  public mutating func removeKey(at index: Int) {
    guard apiKeys.indices.contains(index) else { return }
    apiKeys.remove(at: index)
  }

  public mutating func updateKey(_ key: String, at index: Int) {
    guard apiKeys.indices.contains(index) else { return }
    let disabled = isKeyDisabled(at: index)
    let clean = cleanKey(key)
    apiKeys[index] = disabled ? "\(Self.disabledPrefix)\(clean)" : clean
  }

  private enum CodingKeys: String, CodingKey {
    case apiKeys, apiKey, textModel, baseURL, name
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    textModel = try container.decodeIfPresent(String.self, forKey: .textModel) ?? ""
    baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""

    if let keys = try container.decodeIfPresent([String].self, forKey: .apiKeys), !keys.isEmpty {
      apiKeys = keys
    } else if let singleKey = try container.decodeIfPresent(String.self, forKey: .apiKey),
      !singleKey.isEmpty
    {
      apiKeys = [singleKey]
    } else {
      apiKeys = []
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(apiKeys, forKey: .apiKeys)
    try container.encode(apiKey, forKey: .apiKey)
    try container.encode(textModel, forKey: .textModel)
    try container.encode(baseURL, forKey: .baseURL)
    try container.encode(name, forKey: .name)
  }
}

public struct AvailableAPIProvider: Codable, Equatable, Sendable {
  public var kind: APIProviderKind
  public var displayName: String
  public var modelName: String

  public init(kind: APIProviderKind, displayName: String, modelName: String) {
    self.kind = kind
    self.displayName = displayName
    self.modelName = modelName
  }
}

/// One remote model offered by a provider (with optional OpenRouter-style pricing).
public struct CloudRemoteModel: Codable, Equatable, Sendable, Identifiable, Hashable {
  public var id: String
  /// Context window size in tokens, when known.
  public var contextLength: Int?
  /// USD per 1M prompt tokens, when known.
  public var promptPricePer1M: Double?
  /// USD per 1M completion tokens, when known.
  public var completionPricePer1M: Double?

  public init(
    id: String,
    contextLength: Int? = nil,
    promptPricePer1M: Double? = nil,
    completionPricePer1M: Double? = nil
  ) {
    self.id = id
    self.contextLength = contextLength
    self.promptPricePer1M = promptPricePer1M
    self.completionPricePer1M = completionPricePer1M
  }

  public var priceLabel: String? {
    guard let prompt = promptPricePer1M, let completion = completionPricePer1M else {
      return nil
    }
    return String(format: "$%.2f / $%.2f per 1M", prompt, completion)
  }

  public var inputPriceLabel: String {
    guard let prompt = promptPricePer1M else { return "—" }
    return String(format: "$%.3f / 1M", prompt)
  }

  public var outputPriceLabel: String {
    guard let completion = completionPricePer1M else { return "—" }
    return String(format: "$%.3f / 1M", completion)
  }

  public var contextLabel: String {
    guard let contextLength, contextLength > 0 else { return "—" }
    if contextLength >= 1_000_000 {
      let m = Double(contextLength) / 1_000_000
      return String(format: "%.1fM", m)
    }
    if contextLength >= 1_000 {
      return "\(contextLength / 1_000)K"
    }
    return "\(contextLength)"
  }
}

public struct APIProviderSettings: Codable, Equatable, Sendable {
  public var google: APIProviderConfiguration
  public var openAI: APIProviderConfiguration
  public var anthropic: APIProviderConfiguration
  public var qwen: APIProviderConfiguration
  public var openRouter: APIProviderConfiguration
  public var custom: APIProviderConfiguration

  public init(
    google: APIProviderConfiguration = APIProviderConfiguration(textModel: "gemini-3.5-flash"),
    openAI: APIProviderConfiguration = APIProviderConfiguration(textModel: "gpt-4o-mini"),
    anthropic: APIProviderConfiguration = APIProviderConfiguration(
      textModel: "claude-3-haiku-20240307"),
    qwen: APIProviderConfiguration = APIProviderConfiguration(
      textModel: "qwen3.7-plus",
      baseURL: "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
    ),
    openRouter: APIProviderConfiguration = APIProviderConfiguration(
      textModel: "openai/gpt-4o-mini",
      baseURL: "https://openrouter.ai/api/v1"
    ),
    custom: APIProviderConfiguration = APIProviderConfiguration()
  ) {
    self.google = google
    self.openAI = openAI
    self.anthropic = anthropic
    self.qwen = qwen
    self.openRouter = openRouter
    self.custom = custom
  }

  private enum CodingKeys: String, CodingKey {
    case google, openAI, anthropic, qwen, openRouter, custom
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    google =
      try container.decodeIfPresent(APIProviderConfiguration.self, forKey: .google)
      ?? APIProviderConfiguration(textModel: "gemini-3.5-flash")
    openAI =
      try container.decodeIfPresent(APIProviderConfiguration.self, forKey: .openAI)
      ?? APIProviderConfiguration(textModel: "gpt-4o-mini")
    anthropic =
      try container.decodeIfPresent(APIProviderConfiguration.self, forKey: .anthropic)
      ?? APIProviderConfiguration(textModel: "claude-3-haiku-20240307")
    qwen =
      try container.decodeIfPresent(APIProviderConfiguration.self, forKey: .qwen)
      ?? APIProviderConfiguration(
        textModel: "qwen3.7-plus",
        baseURL: "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
      )
    openRouter =
      try container.decodeIfPresent(APIProviderConfiguration.self, forKey: .openRouter)
      ?? APIProviderConfiguration(
        textModel: "openai/gpt-4o-mini", baseURL: "https://openrouter.ai/api/v1")
    custom =
      try container.decodeIfPresent(APIProviderConfiguration.self, forKey: .custom)
      ?? APIProviderConfiguration()

    if qwen.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      qwen.baseURL = APIProviderKind.qwen.defaultBaseURL
    }
    if openRouter.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      openRouter.baseURL = APIProviderKind.openRouter.defaultBaseURL
    }
  }

  public var availablePolishingProviders: [AvailableAPIProvider] {
    var result: [AvailableAPIProvider] = []
    for kind in APIProviderKind.polishingUICases {
      let config = configuration(for: kind)
      guard config.hasAPIKey else { continue }
      let model = config.textModel.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !model.isEmpty else { continue }
      if kind == .custom || kind == .qwen {
        // Qwen needs its base URL; custom always needs a base URL.
        let base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .custom, base.isEmpty { continue }
      }
      let label: String
      if kind == .custom {
        let name = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
        label = name.isEmpty ? "Custom" : name
      } else {
        label = kind.displayName
      }
      if !result.contains(where: { $0.kind == kind || $0.displayName == label }) {
        result.append(AvailableAPIProvider(kind: kind, displayName: label, modelName: model))
      }
    }
    return result
  }

  public func configuration(for kind: APIProviderKind) -> APIProviderConfiguration {
    switch kind {
    case .google: google
    case .openAI: openAI
    case .anthropic: anthropic
    case .qwen: qwen
    case .openRouter: openRouter
    case .custom: custom
    }
  }

  public mutating func setConfiguration(
    _ configuration: APIProviderConfiguration, for kind: APIProviderKind
  ) {
    switch kind {
    case .google: google = configuration
    case .openAI: openAI = configuration
    case .anthropic: anthropic = configuration
    case .qwen: qwen = configuration
    case .openRouter: openRouter = configuration
    case .custom: custom = configuration
    }
  }
}
