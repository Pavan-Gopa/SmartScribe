# SmartScribe 1.0.1

Native Apple Silicon release — local dictation, transcription, polishing, translation, and hotkey insertion into any app.

**Version:** 1.0.1 (build 2)  
**Package:** Developer ID signed · Apple notarized · `SmartScribe.dmg`

---

## What's new in 1.0.1

### HUD provider & model quick switcher

Dictate in any app with the floating HUD, then switch polishing **without leaving that app**.

| Gesture | What happens |
|---------|----------------|
| **Scroll** over the HUD capsule | Opens a translucent **provider list** next to the capsule and steps through polishing providers. The active engine switches **live**. |
| **Left-click** a provider | Selects that provider. |
| **Right-click** a provider | Opens a **model menu** (favorites + available models). Choosing a model updates the provider and activates it. |

Details:

- Non-activating panel — **keyboard focus stays** in Telegram, browser, IDE, Notes, etc.
- Needs **two or more** polishing providers configured (cloud and/or local).
- Documented in in-app Help and onboarding (expandable HUD section).

### Onboarding & clarity

- Full HUD explanation moved into an **expandable onboarding panel** (less clutter on first launch).
- Model list **ordering** cleaned up so recommended options are easier to find.
- Docs and packaging no longer mention removed / incorrect models.

### Packaging

- Marketing version **1.0.1**.
- Signed with Developer ID and **notarized by Apple**.
- Install: open `SmartScribe.dmg` → drag **SmartScribe** to Applications.

### Stability (carried / hardened)

- Parakeet audio input normalization.
- Retries when Google polishing requests stall.
- Broad code-review safety hardening from the 1.0.0 line.

---

## Highlights (full product)

- **Local transcription:** Parakeet TDT 0.6B v3 (FluidAudio / ANE) and WhisperKit Core ML (Small → Large v3)
- **Local polishing:** MLX Swift (Qwen 3.5 family, Nemotron-3 Nano); scan custom MLX trees from disk / HF cache
- **Cloud optional:** Gemini, OpenAI, Anthropic, Qwen, OpenRouter, custom OpenAI-compatible endpoints
- **Hotkeys:** ⌥S dictate, ⇧⌥S dictate + auto-translate; floating HUD; clipboard or type-into-active-app
- **HUD 1.0.1:** scroll = providers, right-click = models
- **Workspace:** notes sidebar, Raw / Variant 1 / Variant 2, Markdown, audio import, drag-and-drop
- **Glossary:** deterministic post-processing dictionary (JSON/CSV import-export)
- **Translation:** full window + quick translation
- **UI languages:** EN, RU, ES, DE, FR, IT, PT, ZH, JA, KO, AR, HI + system
- **Onboarding, Help, Statistics, log export**

---

## Requirements

- Apple Silicon Mac (M1 or later)
- macOS 14+
- Accessibility permission for “Type into Active App”

---

## Install

1. Download **`SmartScribe.dmg`** below.
2. Open the DMG → drag **SmartScribe** into **Applications**.
3. Launch from Applications. If Gatekeeper prompts: right-click → Open.

The app ships **without** API keys. Add providers under **Settings → API Providers**. Local models download on demand from Settings.

### Try the new HUD switcher

1. Enable **at least two** polishing providers (e.g. Local MLX + Google).
2. Press **Option+S** over any app so the HUD appears.
3. **Scroll** over the capsule → provider list.
4. **Right-click** a provider → model menu.
