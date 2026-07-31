import XCTest

@testable import NativeSmartScribeCore

final class ProviderQuickSwitcherModelTests: XCTestCase {
  private let threeProviders = [
    ProviderQuickSwitcherModel.Provider(id: "google", displayName: "Google"),
    ProviderQuickSwitcherModel.Provider(id: "openai", displayName: "OpenAI"),
    ProviderQuickSwitcherModel.Provider(id: "qwen", displayName: "Qwen")
  ]

  func testCannotCycleWithFewerThanTwoProviders() {
    var model = ProviderQuickSwitcherModel(
      providers: [threeProviders[0]], activeID: "google")
    XCTAssertFalse(model.canCycle)
    XCTAssertNil(model.applyScroll(deltaY: -100, now: 1))
  }

  func testActiveIndexResolvesFromActiveID() {
    let model = ProviderQuickSwitcherModel(providers: threeProviders, activeID: "openai")
    XCTAssertEqual(model.activeIndex, 1)
    XCTAssertEqual(model.activeProvider?.id, "openai")
  }

  func testScrollBelowThresholdDoesNotStep() {
    var model = ProviderQuickSwitcherModel(
      providers: threeProviders, activeID: "google", stepThreshold: 24)
    XCTAssertNil(model.applyScroll(deltaY: -10, now: 1))
    XCTAssertEqual(model.activeIndex, 0)
  }

  func testNegativeScrollAdvancesToNextProvider() {
    var model = ProviderQuickSwitcherModel(
      providers: threeProviders, activeID: "google", stepThreshold: 24)
    let selected = model.applyScroll(deltaY: -24, now: 1)
    XCTAssertEqual(selected?.id, "openai")
    XCTAssertEqual(model.activeIndex, 1)
  }

  func testPositiveScrollMovesToPreviousProviderAndWraps() {
    var model = ProviderQuickSwitcherModel(
      providers: threeProviders, activeID: "google", stepThreshold: 24)
    let selected = model.applyScroll(deltaY: 24, now: 1)
    XCTAssertEqual(selected?.id, "qwen", "scrolling up from the first entry wraps to the last")
    XCTAssertEqual(model.activeIndex, 2)
  }

  func testCooldownSuppressesImmediateSecondStep() {
    var model = ProviderQuickSwitcherModel(
      providers: threeProviders, activeID: "google", stepThreshold: 24, stepCooldown: 0.12)
    XCTAssertNotNil(model.applyScroll(deltaY: -24, now: 1.0))
    XCTAssertNil(model.applyScroll(deltaY: -24, now: 1.05), "within cooldown window")
    XCTAssertEqual(model.activeIndex, 1)
    XCTAssertNotNil(model.applyScroll(deltaY: -24, now: 1.20), "after cooldown window")
    XCTAssertEqual(model.activeIndex, 2)
  }

  func testSmallTrackpadDeltasAccumulateIntoOneStep() {
    var model = ProviderQuickSwitcherModel(
      providers: threeProviders, activeID: "google", stepThreshold: 24, stepCooldown: 0)
    XCTAssertNil(model.applyScroll(deltaY: -8, now: 1))
    XCTAssertNil(model.applyScroll(deltaY: -8, now: 1.01))
    let selected = model.applyScroll(deltaY: -8, now: 1.02)
    XCTAssertEqual(selected?.id, "openai")
  }

  func testSelectSetsActiveAndResetsAccumulator() {
    var model = ProviderQuickSwitcherModel(
      providers: threeProviders, activeID: "google", stepThreshold: 24)
    let selected = model.select(id: "qwen")
    XCTAssertEqual(selected?.id, "qwen")
    XCTAssertEqual(model.activeIndex, 2)
  }

  func testSetActiveResyncsExternalChanges() {
    var model = ProviderQuickSwitcherModel(providers: threeProviders, activeID: "google")
    model.setActive(id: "openai")
    XCTAssertEqual(model.activeIndex, 1)
    model.setActive(id: "unknown")
    XCTAssertEqual(model.activeIndex, 1, "unknown id leaves the active index untouched")
  }

  // MARK: - Additional coverage for newly introduced behavior

  func testStepThresholdIsClampedToMinimumOfOne() {
    // A zero/negative threshold must be clamped to 1 so a single normalized
    // unit of scroll always produces a step instead of dividing by zero.
    var model = ProviderQuickSwitcherModel(
      providers: threeProviders, activeID: "google", stepThreshold: 0, stepCooldown: 0)
    XCTAssertEqual(model.stepThreshold, 1)
    let selected = model.applyScroll(deltaY: -1, now: 1)
    XCTAssertEqual(selected?.id, "openai")
  }

  func testEmptyProvidersCannotCycleAndExposeNoActiveProvider() {
    var model = ProviderQuickSwitcherModel(providers: [], activeID: nil)
    XCTAssertFalse(model.canCycle)
    XCTAssertNil(model.activeProvider)
    XCTAssertNil(model.applyScroll(deltaY: -100, now: 1))
    XCTAssertNil(model.select(id: "google"))
  }

  func testNilActiveIDDefaultsToFirstProvider() {
    let model = ProviderQuickSwitcherModel(providers: threeProviders, activeID: nil)
    XCTAssertEqual(model.activeIndex, 0)
    XCTAssertEqual(model.activeProvider?.id, "google")
  }

  func testUnknownActiveIDFallsBackToFirstProvider() {
    let model = ProviderQuickSwitcherModel(providers: threeProviders, activeID: "does-not-exist")
    XCTAssertEqual(model.activeIndex, 0)
    XCTAssertEqual(model.activeProvider?.id, "google")
  }

  func testSelectUnknownIDReturnsNilAndKeepsCurrentIndex() {
    var model = ProviderQuickSwitcherModel(providers: threeProviders, activeID: "google")
    XCTAssertNil(model.select(id: "does-not-exist"))
    XCTAssertEqual(model.activeIndex, 0)
  }

  func testSetActiveNilKeepsCurrentIndex() {
    var model = ProviderQuickSwitcherModel(providers: threeProviders, activeID: "openai")
    model.setActive(id: nil)
    XCTAssertEqual(model.activeIndex, 1, "nil id must not move the active index")
  }

  func testAccumulatorIsResetAfterStepWithoutCarryingResidual() {
    var model = ProviderQuickSwitcherModel(
      providers: threeProviders, activeID: "google", stepThreshold: 24, stepCooldown: 0)
    // A large delta steps once; the residual (30 - 24 = 6) is discarded, not
    // carried into the next gesture.
    XCTAssertNotNil(model.applyScroll(deltaY: -30, now: 1))
    XCTAssertEqual(model.activeIndex, 1)
    // A small follow-up delta below the threshold must not step on its own.
    XCTAssertNil(model.applyScroll(deltaY: -8, now: 1.01))
    XCTAssertEqual(model.activeIndex, 1)
  }

  func testOppositeDirectionDeltasCancelAccumulation() {
    var model = ProviderQuickSwitcherModel(
      providers: threeProviders, activeID: "google", stepThreshold: 24, stepCooldown: 0)
    XCTAssertNil(model.applyScroll(deltaY: -16, now: 1))
    XCTAssertNil(model.applyScroll(deltaY: 16, now: 1.01), "opposite delta cancels the build-up")
    XCTAssertEqual(model.activeIndex, 0)
    // After cancellation a full threshold in either direction steps again.
    XCTAssertNotNil(model.applyScroll(deltaY: -24, now: 1.02))
    XCTAssertEqual(model.activeIndex, 1)
  }

  func testRepeatedScrollCyclesThroughAllProvidersAndWraps() {
    var model = ProviderQuickSwitcherModel(
      providers: threeProviders, activeID: "google", stepThreshold: 24, stepCooldown: 0)
    var visited: [String] = []
    for tick in 0..<4 {
      if let selected = model.applyScroll(deltaY: -24, now: TimeInterval(tick)) {
        visited.append(selected.id)
      }
    }
    XCTAssertEqual(visited, ["openai", "qwen", "google", "openai"], "cycling wraps around the list")
  }
}
