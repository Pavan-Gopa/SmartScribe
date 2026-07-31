# SmartScribe

**Native macOS dictation for Apple Silicon** — speak, get clean text, and drop it into any app.

SmartScribe is a **pure Swift / SwiftUI** desktop app (AppKit only where the OS requires it). No Electron, no browser shell, no cloud dependency for the core path. You can work fully offline with local models, or optionally plug in cloud APIs when you want higher-end polishing or Gemini dictation.

> **Apple Silicon only** (M1 and later) · **macOS 14+** · Private repository · Current package: **v1.0.1**

---

## Why SmartScribe

| Advantage | What it means in practice |
|-----------|---------------------------|
| **Local-first** | WhisperKit, Parakeet, and MLX polishing run on your Mac. Audio and text stay on-device unless you deliberately choose a cloud engine. |
| **Two-stage pipeline** | **Transcription** (speech → text) is separate from **polishing** (text → cleaner text). You always keep a faithful **Raw** transcript. |
| **System-wide hotkeys** | Dictate from Slack, browser, IDE, or Notes. A floating **HUD** shows recording / processing without stealing keyboard focus. |
| **Provider flexibility** | Local MLX models *and* Gemini / OpenAI / Anthropic / Qwen / OpenRouter / custom OpenAI-compatible endpoints — with multi-key rotation. |
| **Real workspace** | Notes history, Raw / Variant 1 / Variant 2, Markdown, glossary, translation, prompt templates, usage stats, built-in Help. |
| **Native quality** | Developer ID signed, Apple notarized DMG, menu-bar status item, Accessibility insertion, dark/light UI, 12 interface languages. |

---

## What's new in v1.0.1

### HUD provider & model quick switcher (headline feature)

Dictate in **any app** with the floating HUD, then **without leaving that app**:

| Gesture | Result |
|---------|--------|
| **Scroll** over the HUD capsule | Opens the translucent **provider list** and steps through polishing providers — the engine switches **live**. |
| **Left-click** a provider row | Selects that provider. |
| **Right-click** a provider row | Opens a **model menu** for that provider (favorites + catalog). Choosing a model applies it immediately. |

![Scroll providers + right-click models on the HUD](docs/screenshots/18_hud_provider_switcher.png)

The panel is **non-activating** — keyboard focus stays in Telegram, the browser, your IDE, etc. Needs **two or more** polishing providers configured.

### Also in this release line

- Onboarding: full HUD explanation in an expandable panel; clearer model ordering.
- Packaging: notarized **1.0.1** DMG (Developer ID).
- Docs cleanup (no incorrect model claims).
- Stability from the 1.0.0 line: Parakeet audio normalization, Google polish retries, code-review hardening.

Full changelog: [Changelog — v1.0.1](#changelog--v101) · [`docs/RELEASE_NOTES.md`](docs/RELEASE_NOTES.md).

---

## Screenshots

### Main workspace

![Main window](docs/screenshots/01_main_window.png)

Sidebar notes; transcription + polishing pickers; **Raw / Variant 1 / Variant 2**; record / import / translate / polish / settings.

### Floating HUD (global hotkey)

Dictate over any app — red capsule while recording, green while processing:

| Over another app | Recording | Processing |
|:---:|:---:|:---:|
| ![HUD over Telegram](docs/screenshots/08_hud_overlay.png) | ![Recording capsule](docs/screenshots/15_hud_recording.png) | ![Processing capsule](docs/screenshots/16_hud_processing.png) |

**Scroll the capsule → pick provider; right-click → pick model** (the 1.0.1 highlight):

![HUD provider and model switcher](docs/screenshots/18_hud_provider_switcher.png)

### Translation

| Full translation window | Quick translation |
|:---:|:---:|
| ![Full translation](docs/screenshots/09_translation.png) | ![Quick translation](docs/screenshots/17_quick_translation.png) |

### Settings

| General | Hotkeys |
|:---:|:---:|
| ![General](docs/screenshots/03_general_settings_language.png) | ![Hotkeys](docs/screenshots/07_hotkeys.png) |

| API Providers | Local Models |
|:---:|:---:|
| ![API Providers](docs/screenshots/04_api_keys.png) | ![Local Models](docs/screenshots/05_local_transcription_models.png) |

| Polishing (MLX) | Prompts |
|:---:|:---:|
| ![Polishing](docs/screenshots/06_local_polishing_models.png) | ![Prompts](docs/screenshots/13_prompts.png) |

| Glossary | Help |
|:---:|:---:|
| ![Glossary](docs/screenshots/10_glossary.png) | ![Help](docs/screenshots/14_help.png) |

---

## Feature overview

### 1. Core workflow

1. **Record** in-app, or **import / drag-and-drop** an audio file.  
2. **Transcribe** with a local model (WhisperKit Core ML or Parakeet FluidAudio) or optional Gemini cloud dictation.  
3. Review **Raw** text (closest to the audio).  
4. **Polish** into **Variant 1** (light cleanup), **Variant 2** (stronger rewrite), or **Markdown**.  
5. Optionally **translate**, apply the **glossary**, copy notes, or push text into another app with a hotkey.

### 2. Transcription engines

| Engine | Runtime | Notes |
|--------|---------|--------|
| **Parakeet TDT 0.6B v3** | FluidAudio · Core ML / ANE | Fast path; ~25 European languages (incl. EN/RU/UK/NL). ASR only. |
| **Whisper Small / Medium** | WhisperKit · Core ML | English-only and multilingual variants. |
| **Whisper Large v3 Turbo** | WhisperKit · Core ML | Strong multilingual quality, faster than full Large. |
| **Whisper Large v3 Full** | WhisperKit · Core ML | Highest accuracy; solid quality default. |
| **Google Gemini (cloud)** | Gemini API | Optional cloud dictation when keys are configured. |

Models download from **Settings → Local Models**. Storage prefers a shared root (`AI_LOCAL_MODELS_DIR` / `~/AI_LOCAL_MODELS`) with Application Support fallbacks.

### 3. Text polishing

Polishing rewrites **text** with prompts — it is not a second ASR pass.

**Local (MLX Swift / GPU):**

- Qwen 3.5 — 0.8B, 2B, **4B (recommended default)**, 9B (4-bit)  
- NVIDIA Nemotron-3 Nano 4B  
- Custom / scanned local MLX models from your folders or Hugging Face cache  

**Cloud polishing providers:**

Google Gemini · OpenAI · Anthropic · Qwen (OpenAI-compatible) · OpenRouter · custom OpenAI-compatible base URL  

Multi-key support, enable/disable keys, model pickers, retries for stalled cloud requests, optional “polishing disabled” mode.

### 4. Variants, prompts, Markdown

| Output | Role |
|--------|------|
| **Raw** | Unedited transcription |
| **Variant 1** | Light cleanup (fillers, repeats, self-corrections; same language/meaning) |
| **Variant 2** | Stronger structure and wording (no inventing facts) |
| **Markdown** | Structured export via a dedicated prompt |

Customizable prompt slots: default + slots `1`–`4` + Markdown (`M`) in **Settings → Prompts**.

### 5. Global hotkeys & HUD

| Shortcut | Action |
|----------|--------|
| **⌥S** (Option+S) | Start/stop hotkey dictation |
| **⇧⌥S** (Shift+Option+S) | Same, then auto-translate to the Glossary **Auto Translation Language** |

- Floating **HUD** (non-activating): red = recording, green = processing; draggable; position remembered  
- **Target:** Raw / Variant 1 / Variant 2  
- **Mode:** Clipboard, or **Type into Active App** (Accessibility)  
- Language control on the HUD (disabled for Parakeet / English-only Whisper where not applicable)  
- Start/finish sounds, volume, HUD size/opacity/style in General settings  
- **v1.0.1:** scroll / right-click on the provider switcher (see above)

### 6. Translation

- Modal translator from the main toolbar  
- Local MLX or cloud providers as engine  
- Dictate into the modal, paste from clipboard, copy result  
- Floating / quick translation windows  
- Auto-translation language for ⇧⌥S  

### 7. Glossary (local, deterministic)

- Post-ASR / post-translation term correction — **does not train or bias** models  
- Source form, translation form, categories, variant spellings  
- Import / export JSON & CSV  
- “Add to Glossary” from selected text  
- Stored under Application Support  

### 8. Notes & workspace

- Sidebar history with dates and previews  
- Per-note raw + polished variants  
- Copy one note or all notes  
- Blank note creation  
- Managed audio storage and cleanup of unreferenced files  

### 9. Settings surface

| Tab | Capabilities |
|-----|----------------|
| **General** | Theme, UI scale, fonts, interface language, HUD style/size/opacity, sounds, log level, export logs, reset |
| **Hotkeys** | Enable, shortcuts, language, Accessibility, output target/mode |
| **API Providers** | Keys, models, custom endpoints, multi-key rotation, per-provider usage stats |
| **Local Models** | Download / use / delete Whisper & Parakeet models |
| **Polishing** | MLX models, scan local folders, engine selection |
| **Prompts** | Variant 1 / 2 / Markdown templates and slots |
| **Glossary** | Entries, import/export, auto-translation language |
| **Help** | In-app guide + replay onboarding |

### 10. Onboarding, permissions, privacy

First-run flow covers backend/model choice, microphone, speech recognition, and Accessibility. Help can **replay onboarding**.

| Permission | Why |
|------------|-----|
| Microphone | Recording |
| Speech recognition | Apple Speech paths where used |
| Accessibility | Insert into focused apps |
| Apple Events | Paste automation where needed |

**Privacy model**

- Local engines run on-device  
- Cloud is opt-in; text leaves the machine only when you select a cloud engine  
- API keys stay in the app credential store  
- Release builds ship **without** bundled API keys or personal data  

---

## Changelog — v1.0.1

### Added

- **HUD provider quick switcher** — scroll the capsule to open the provider list and cycle polishing providers without leaving the dictation target app.  
- **Per-provider model context menu** — right-click a provider row to pick a concrete model (favorites + catalog); selection applies immediately.  
- Non-activating switcher panel (status-bar level) so focus stays in the destination app.  

### Improved

- Onboarding: HUD documentation expanded into an expandable panel; model list ordering cleaned up.  
- Release packaging defaults for **1.0.1** (signed + notarized DMG).  
- Repository presentation (README, release notes, GitHub About) rewritten for accuracy.  

### Fixed / carried forward

- Parakeet audio input normalization.  
- Retries for stalled Google polishing requests.  
- Broad code-review safety pass from the 1.0.0 hardening line.  

### Removed from docs (not product claims)

- Incorrect marketing of **Bonsai / Prism** as a supported shipping model. The app does **not** promote that model; local polish focuses on the Qwen 3.5 / Nemotron MLX catalog and user-scanned MLX trees.

### Install asset

- **`SmartScribe.dmg`** on the [v1.0.1 release](https://github.com/Pavan-Gopa/SmartScribe/releases/tag/v1.0.1).

---

## Requirements

- **Apple Silicon** Mac (M1 or later)  
- **macOS 14** Sonoma or later  
- Optional: network for model downloads and cloud providers  
- Optional: Accessibility for “Type into Active App”  

---

## Install (end users)

1. Download **`SmartScribe.dmg`** from the [v1.0.1 release](https://github.com/Pavan-Gopa/SmartScribe/releases/tag/v1.0.1) (sign in if the repo is private).  
2. Open the DMG → drag **SmartScribe** into **Applications**.  
3. Launch from Applications. Notarized Developer ID build — if Gatekeeper still prompts: right-click → Open.  

Developers / automation can still use `./script/install.sh` from a local checkout; it is **not** required for normal install.

---

## Build from source

```bash
git clone https://github.com/Pavan-Gopa/SmartScribe.git
cd SmartScribe   # this repository is the NativeAppleSilicon tree
./script/build_and_run.sh          # debug
./script/build_and_run.sh --verify
APP_VERSION=1.0.1 ./script/build_release_dmg.sh
# notarize (credentials stored once via notarytool):
NOTARIZE=1 APP_VERSION=1.0.1 ./script/build_release_dmg.sh
```

| Product | Role |
|---------|------|
| `NativeSmartScribe` | Main app (bundled as `SmartScribe.app`) |
| `NativeSmartScribePolishWorker` | Out-of-process MLX polishing worker |
| `NativeSmartScribeCore` | Shared models, stores, services |
| Tests | `NativeSmartScribeCoreTests` |

Architecture: SwiftUI-first UI; Whisper → WhisperKit Core ML; Parakeet → FluidAudio Core ML/ANE; polish → MLX Swift in a separate worker process.

Checklist: [`docs/RELEASE.md`](docs/RELEASE.md)

---

## Local paths

| Data | Location |
|------|----------|
| Transcription models | `AI_LOCAL_MODELS_DIR` → shared config → `~/AI_LOCAL_MODELS/whisperkit` → app-support legacy |
| MLX polish scan | `~/AI_LOCAL_MODELS/mlx`, HF cache, Documents, Downloads |
| Glossary | `~/Library/Application Support/NativeSmartScribe/glossary.json` |
| Logs export | `~/Library/Application Support/NativeSmartScribe/Logs/` |

---

## License & distribution

| Use case | Allowed? |
|----------|----------|
| **Personal / private** use (yourself, hobby, study, noncommercial) | **Free** under [PolyForm Noncommercial 1.0.0](LICENSE) |
| **Company / business** use (work devices, teams, commercial deployment) | **Paid commercial license** — see [COMMERCIAL.md](COMMERCIAL.md) |

This is **source-available**, not OSI “open source”: companies may not use SmartScribe for commercial purposes without a paid agreement.

Builds are signed with **Developer ID Application: Stichting Kadamba Foundation (438UQRF7JV)** and notarized by Apple.

---

## Support

- In-app **Help** and onboarding replay  
- **Export System Logs** from General settings  
- Commercial licensing: [COMMERCIAL.md](COMMERCIAL.md)  
