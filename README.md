# TranslateInstantly

A macOS menu-bar app that translates selected text between English and
Chinese using Gemini or DeepSeek.

## Setup

1. Get an API key for whichever provider you want to use:
   [Gemini](https://aistudio.google.com/apikey) and/or
   [DeepSeek](https://platform.deepseek.com/api_keys).

2. Build the app:

   ```
   ./build_app.sh
   ```

3. Launch it:

   ```
   open TranslateInstantly.app
   ```

4. On first launch, macOS will ask you to grant **Accessibility** permission
   (System Settings → Privacy & Security → Accessibility → enable TranslateInstantly).
   This is required so the app can read your text selection.

5. Click the "译" icon in the menu bar → **Set Gemini API Key…** and/or
   **Set DeepSeek API Key…**, and paste the corresponding key. Keys are stored
   securely in the macOS Keychain, one per provider.

6. Pick the active provider from the menu bar: **Use Gemini** or
   **Use DeepSeek** (checkmark shows which is active). The choice is
   remembered between launches.

## Usage

1. Select any English or Chinese text in any app.
2. Press **⌥⇧T** (Option+Shift+T).
3. A popup appears near your cursor:
   - English selection → a plain-English rewrite, a General American IPA
     transcription of the original text, its Simplified Chinese translation, and
     a short grammar explanation in simple English of the key structures used.
   - Chinese selection → its English translation.
   - Click **▶ Play** next to a section title (including your selected text)
     to hear it read aloud (click **■ Stop** to stop). For the most natural voice, download a Premium or
     Enhanced voice in System Settings › Accessibility › Spoken Content.

   The direction is picked automatically based on which script the
   selected text is mostly written in.

## Notes

- No dock icon — it only lives in the menu bar (background app).
- To change the hotkey, edit `kVK_ANSI_T` / modifiers in
  `Sources/TranslateInstantly/HotKeyManager.swift` and rebuild.
- To launch automatically at login, drag `TranslateInstantly.app` into
  System Settings → General → Login Items.
- Move `TranslateInstantly.app` to `/Applications` for a permanent install
  (re-grant Accessibility permission after moving, since macOS ties it to the app's path).

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
