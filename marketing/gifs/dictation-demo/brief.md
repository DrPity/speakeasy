# Speakeasy — hold, speak, release

Asset: `dictation-demo` · Template: `synthetic` · Format: 16:9 (960×540)

## Where it plays

README hero and anywhere Speakeasy is introduced (repo page, portfolio, a post).

## Copy (this is the script)

One message: **hold a key, speak, let go — the words are typed for you, on-device.**

- Headline: none on screen; the hint chip carries the three steps.
- Hint chip per beat:
  1. Hold fn + F5 (the default talk key on a MacBook keyboard)
  2. Speak
  3. Let go — it types for you

## Story beats

1. A note is open with the caret after "Today:"; the coupe sits in the menu bar.
2. The key goes down: the capsule overlay appears, its glass fills with the voice, words stream in (the newest still grey).
3. The key comes up: the capsule shows a mint ✓ "Typed" and the sentence types into the note.
4. The overlay fades; the note resets so the loop is seamless.

## Product context

On-device push-to-talk dictation for macOS (menu-bar app). Apple's local SpeechAnalyzer; no network code.

## Why synthetic

Speakeasy is a native macOS app driven by a global key and a real voice; a browser can't record it. The scene
rebuilds the real UI from the design canvas (https://claude.ai/artifact/96LkhEdT5rGvEboiGTB77X) and the app's own
tokens (`Sources/LocalSTT/Theme.swift`) and coupe geometry/motion (`CoupeGlyph.swift`, `CoupeAnimation.swift`).

## Style references

Mint on Ink: ink #0C0F15, panel #141922, raised #232936, glass #E8FFF5, grey #8FA19A / #B8C6C0, mint #3BEFA6.
Desktop #3A4150. System font (SF Pro).
