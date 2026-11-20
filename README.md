# 🏛️ PlatoReader: AI Reading Companion for macOS (PDFs & Web)

A lightweight, native macOS companion designed for deep, context-aware reading. Originally created for classical philosophy texts in **Preview.app**, PlatoReader now features **Universal 3-Finger / 4-Finger Tap Lookup & Customizable Shortcuts** across all macOS applications (browsers like Chrome, Safari, Arc, Firefox, code editors, and notes).

Whenever you highlight a sentence anywhere on your Mac, PlatoReader summons instant, deep explanations powered by modern AI (Google Gemini, Groq, OpenRouter / Claude 3.5 / DeepSeek R1, or OpenAI).

---

## 🌟 Key Features

### 1. 🖐️ Customizable 3-Finger or 4-Finger Tap Universal Web & Browser Lookup
- **Trackpad Gesture**: Highlight any word, sentence, or phrase in **Safari, Chrome, Arc, or any app** and simply **tap with 3 fingers or 4 fingers** together on your trackpad. You can configure your preferred gesture mode (**3 Fingers**, **4 Fingers**, **3 or 4 Fingers**, or **Disabled**) in Preferences.
- **Privacy-First Architecture**: Outside Preview, PlatoReader **only reads your highlighted text selection**. It does **NOT** access, scrape, or read the rest of your browser window, background tabs, or web page content.
- **Instant AI Intelligence**: Uses the LLM's vast knowledge base to explain the meaning, philosophical depth, and context with zero search latency.
- **Customizable Prompt & Template**: Personalize the prompt and template in **Preferences → 🖐️ Gestures & Shortcuts**.

### 2. 📋 Explain Recently Copied Text (Instant Clipboard Explain)
- **Clipboard Intelligence**: Copy any word, sentence, or passage from anywhere (`⌘C`) and press your customizable shortcut (default: **`⌥ ⇧ C`** / Option + Shift + C). PlatoReader summons an instant explanation using the universal deep-context prompt.
- **Record Your Preferred Shortcut**: Choose from presets or click **"🎙️ Record Key"** in **Preferences → 🖐️ Gestures & Shortcuts** to record your own custom shortcut (e.g. `⌘⌥ C`, `⌃⌥ C`, `⌥ C`, etc.).
- **Zero Cross-Window Stale Selection**: Window switches and deselects automatically reset selection state so previously selected sentences are never memorized or repeated across windows.

### 3. ⌨️ Fully Customizable Keyboard Shortcuts
- Configure custom shortcuts for **Universal Lookup** (default: `⌥ ⇧ Space`), **Clipboard Explain** (default: `⌥ ⇧ C`), and **PDF Context Explain** (default: `⌥ Space`).
- Choose from standard ergonomic presets or click **"🎙️ Record Key"** to press and assign any custom key combination (e.g., `⌃⌥ Space`, `⌘⌥ Space`, `⌥ E`, etc.).

### 4. 📄 Context-Aware PDF Page Extraction (Preview.app)
- In **Preview.app**, PlatoReader uses macOS `PDFKit` to identify the exact page you are reading and extracts surrounding context.
- Perfect for dense philosophical texts (e.g. Allan Bloom's translation of Plato's *Republic*).
- **Floating "💡 Explain" Pill**: Appears gently above selected text.
- **Instant Hotkey**: Press your configured shortcut (default: **`⌥ Space`**) while text is highlighted.

### 5. 🛡️ Multi-Provider, Automatic Failover & Dynamic Model Discovery
- Supported providers: **Google Gemini**, **Groq (Ultra-Fast)**, **OpenRouter** (Claude 3.5 Sonnet, DeepSeek R1), and **OpenAI**.
- Automatic failover fallback: if your primary model hits a rate limit or network glitch, PlatoReader automatically falls over to your backup provider.
- Dynamic model fetcher: Click **"⚡ Test Key & Fetch Models"** to validate keys and auto-populate available models.

### 6. 💬 Follow-Up Intellectual Doubts
- Have a question or cross-examination about the explanation? Ask in the floating card's doubt input bar to get a live, research-grounded answer.

---

## 🚀 Quick Start

### 1. Launch PlatoReader
You can double-click **`PlatoReader.app`** in Applications, or run:
```bash
./start.sh
```
A book icon (`📖`) will appear in your macOS menu bar (top right).

### 2. Grant Accessibility Permission
To detect highlighted text and screen coordinates, macOS requires Accessibility permission:
1. Open **System Settings** → **Privacy & Security** → **Accessibility**.
2. Toggle **ON** for `PlatoReader` (or Terminal if running via script).

### 3. Configure Your Preferred AI Provider, Gestures & Shortcuts
1. Click the `📖` icon in your menu bar and select **Preferences...** (or press `⌘ ,`).
2. Enter your API key (Google Gemini, Groq, OpenRouter, or OpenAI).
3. Switch to the **🖐️ Gestures & Shortcuts** tab to set your trackpad gesture (3-finger, 4-finger, or either) and customize your keyboard shortcut.

---

## ⌨️ Shortcuts & Gestures Summary

| Action | Default Shortcut / Gesture | Target Scope | Customization |
| :--- | :--- | :--- | :--- |
| **Universal Lookup** | **3 or 4-Finger Tap** on Trackpad | Any app (Browsers, Web, Notes, Slack) | Configurable (3, 4, or 3/4 fingers) |
| **Universal Explain** | **`⌥ ⇧ Space`** (Option+Shift+Space) | Any app (Keyboard alternative) | Fully customizable in Preferences |
| **Explain Copied Text** | **`⌥ ⇧ C`** (Option+Shift+C) | Any app (Clipboard contents) | Fully customizable in Preferences |
| **PDF Page Context Explain** | **`⌥ Space`** (Option+Space) | macOS Preview.app | Fully customizable in Preferences |
| **Floating Explain Pill** | Click **💡 Explain** above selection | Selection in Preview or Web | Toggleable in Preferences |
| **Dismiss Popover** | **`Esc`** or click outside (when unpinned) | Popover Window | Fixed macOS standard |
| **Keep Card in Place** | Click **📌 Pin / 📍 Pinned** | Popover Window | Interactive toggle |

---

## 💾 Safe Updating & Data Persistence

When updating PlatoReader (e.g. copying and pasting a new `PlatoReader.app` into `/Applications`), **all your personal data, API keys, models, and custom prompts are 100% preserved**.

All configurations are stored independently in your user home directory:
`~/.config/PlatoReader/config.json`

Replacing the app bundle in `/Applications` will never delete or reset your keys.

---

## 🛠️ Rebuilding / Modifying

To recompile the native Swift binary:
```bash
./build.sh
```
