import Foundation

/// Pure, testable model behind the HUD provider quick switcher.
///
/// Holds the ordered list of configured cloud providers, tracks the active one
/// and converts raw (already normalized) vertical scroll deltas into discrete
/// cycling steps. An accumulator plus a per-step cooldown make both notched
/// mouse wheels and smooth trackpads feel consistent: small trackpad deltas
/// build up until `stepThreshold` is reached, while a mouse notch is normalized
/// to roughly one threshold worth of delta so a single notch equals one step.
public struct ProviderQuickSwitcherModel: Equatable, Sendable {
  /// A configured cloud provider entry shown in the quick switcher.
  public struct Provider: Equatable, Sendable, Identifiable {
    /// Stable engine identifier used to activate the provider.
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
      self.id = id
      self.displayName = displayName
    }
  }

  /// Default scroll distance (in normalized units) that produces one step.
  public static let defaultStepThreshold: CGFloat = 24

  public private(set) var providers: [Provider]
  public private(set) var activeIndex: Int
  public var stepThreshold: CGFloat
  public var stepCooldown: TimeInterval

  private var accumulated: CGFloat
  private var lastStepTime: TimeInterval

  public init(
    providers: [Provider],
    activeID: String?,
    stepThreshold: CGFloat = ProviderQuickSwitcherModel.defaultStepThreshold,
    stepCooldown: TimeInterval = 0.12,
    now: TimeInterval = 0
  ) {
    self.providers = providers
    self.activeIndex = providers.firstIndex(where: { $0.id == activeID }) ?? 0
    self.stepThreshold = max(1, stepThreshold)
    self.stepCooldown = stepCooldown
    self.accumulated = 0
    self.lastStepTime = -stepCooldown - 1
  }

  /// The provider currently highlighted/active in the list, if any.
  public var activeProvider: Provider? {
    providers.indices.contains(activeIndex) ? providers[activeIndex] : nil
  }

  /// Cycling only makes sense with at least two configured providers.
  public var canCycle: Bool { providers.count >= 2 }

  /// Feeds a normalized vertical scroll delta.
  ///
  /// Convention: a positive delta (scroll up) moves the selection toward the
  /// start of the list (previous provider); a negative delta moves toward the
  /// end (next provider). Returns the newly selected provider when a step
  /// occurred, or `nil` while the gesture is still accumulating or cooling down.
  public mutating func applyScroll(deltaY: CGFloat, now: TimeInterval) -> Provider? {
    guard canCycle else { return nil }
    guard now - lastStepTime >= stepCooldown else { return nil }

    accumulated += deltaY
    guard abs(accumulated) >= stepThreshold else { return nil }

    let direction: Int = accumulated > 0 ? -1 : 1
    accumulated = 0
    lastStepTime = now
    activeIndex = (activeIndex + direction + providers.count) % providers.count
    return providers[activeIndex]
  }

  /// Explicitly selects a provider by id (e.g. hover/click) and returns it.
  @discardableResult
  public mutating func select(id: String) -> Provider? {
    guard let index = providers.firstIndex(where: { $0.id == id }) else { return nil }
    activeIndex = index
    accumulated = 0
    return providers[index]
  }

  /// Re-syncs the active index with an externally changed active provider.
  public mutating func setActive(id: String?) {
    guard let id, let index = providers.firstIndex(where: { $0.id == id }) else { return }
    activeIndex = index
  }
}
