# 🏛️ PlatoReader: AI Reading Companion for macOS (PDFs & Web)

A lightweight, native macOS companion designed for deep, context-aware reading. Originally created for classical philosophy texts in **Preview.app**, PlatoReader now features **Universal 4-Finger Tap Lookup** across all macOS applications (browsers like Chrome, Safari, Arc, Firefox, code editors, and notes).

Whenever you highlight a sentence anywhere on your Mac, PlatoReader summons instant, deep explanations powered by modern AI (Google Gemini, Groq, OpenRouter / Claude 3.5 / DeepSeek R1, or OpenAI).

---

## 🌟 Key Features

### 1. 🖐️ Four-Finger Tap Universal Web & Browser Lookup (New!)
- **Trackpad Gesture**: Highlight any word, sentence, or phrase in **Safari, Chrome, Arc, or any app** and simply **tap 4 fingers** together on your trackpad.
- **Privacy-First Architecture**: Outside Preview, PlatoReader **only reads your highlighted text selection**. It does **NOT** access, scrape, or read the rest of your browser window, background tabs, or web page content.
- **Live Internet Research**: Automatically searches online encyclopedias and internet knowledge to ground explanations in real-world context.
- **Customizable Four-Finger Prompt**: Personalize the prompt and template in **Preferences → 🖐️ 4-Finger Tap & Web**.
- **Keyboard Shortcut Alternative**: Press **`⌥ ⇧ Space`** (Option + Shift + Space) to trigger universal lookup anytime without a trackpad.

### 2. 📄 Context-Aware PDF Page Extraction (Preview.app)
- In **Preview.app**, PlatoReader uses macOS `PDFKit` to identify the exact page you are reading and extracts surrounding context.
- Perfect for dense philosophical texts (e.g. Allan Bloom's translation of Plato's *Republic*).
- **Floating "💡 Explain" Pill**: Appears gently above selected text.
- **Instant Hotkey**: Press **`⌥ Space`** (Option + Space) while text is highlighted.

### 3. 🛡️ Multi-Provider, Automatic Failover & Dynamic Model Discovery
- Supported providers: **Google Gemini**, **Groq (Ultra-Fast)**, **OpenRouter** (Claude 3.5 Sonnet, DeepSeek R1), and **OpenAI**.
- Automatic failover fallback: if your primary model hits a rate limit or network glitch, PlatoReader automatically falls over to your backup provider.
- Dynamic model fetcher: Click **"⚡ Test Key & Fetch Models"** to validate keys and auto-populate available models.

### 4. 💬 Follow-Up Intellectual Doubts
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

### 3. Configure Your Preferred AI Provider & Prompts
1. Click the `📖` icon in your menu bar and select **Preferences...** (or press `⌘ ,`).
2. Enter your API key (Google Gemini, Groq, OpenRouter, or OpenAI).
3. Switch to the **🖐️ 4-Finger Tap & Web** tab to view or customize your four-finger prompt.

---

## ⌨️ Shortcuts & Gestures Summary

| Action | Shortcut / Gesture | Target Scope |
| :--- | :--- | :--- |
| **Universal 4-Finger Lookup** | **4-Finger Tap** on Trackpad | Any app (Browsers, Web, Notes, Slack) |
| **Universal Internet Explain** | **`⌥ ⇧ Space`** (Option+Shift+Space) | Any app (Keyboard alternative) |
| **PDF Page Context Explain** | **`⌥ Space`** (Option+Space) | macOS Preview.app |
| **Floating Explain Pill** | Click **💡 Explain** above selection | Selection in Preview or Web |
| **Dismiss Popover** | **`Esc`** or click outside (when unpinned) | Popover Window |
| **Keep Card in Place** | Click **📌 Pin / 📍 Pinned** | Popover Window |

---

## 🛠️ Rebuilding / Modifying

To recompile the native Swift binary:
```bash
./build.sh
```

All configurations are stored locally at:
`~/.config/PlatoReader/config.json`
