# Refresher

A personal iOS flashcard app for short study bursts. It reads Obsidian Spaced Repetition decks (`?` cards) straight from a vault folder in iCloud Drive and has a built-in tutor that answers questions about each card.

- **Review:** quick sessions of 3–20 cards. Swipe right for "got it", left for "again", up for "easy". The app keeps its own SM-2 schedule on the device and copies it to `.refresher-progress.json` in the vault after each session. A blank install restores from that copy. It never edits notes or decks. A daily goal and a streak keep it a habit, and a banner warns two days before a free-signing install expires.
- **Activity log:** every grade and every tutor exchange (the card, what was asked, the reply) is appended to `.refresher-activity.jsonl` in the vault, one JSON object per line, for spotting weak areas from the laptop. Events wait on the device until the vault write succeeds.
- **Tutor:** shows on each card once the answer is revealed, plus a separate Tutor tab. It sends the card plus all notes and decks to the OpenAI Chat Completions API and asks for a short answer. The API key lives in the device Keychain.
- **Rendering:** markdown and LaTeX via bundled marked + KaTeX in a WKWebView, so it works offline. Controls use Liquid Glass (iOS 26+).

## Build

```bash
brew install xcodegen
xcodegen generate
open Refresher.xcodeproj   # set your signing team, then run on a device
```

The core logic (card parsing, scheduling, session planning, tutor request building) is a Swift package with its own tests:

```bash
cd Core && swift test
```

To regenerate the app icon: `swift tools/make_icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.
