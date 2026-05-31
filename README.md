# Samantha Key

Premium iOS voice translation keyboard with a companion SwiftUI app, StoreKit subscription gating, Supabase token broker, and OpenAI Realtime speech-to-translated-text.

The repo now also includes **Samantha Mac**, a macOS voice assistant target inspired by the Clicky-style flow:

`voice in -> gpt-realtime-2 -> local tool call -> local Mac action -> spoken response`

## Product

- App name: Samantha Key
- Bundle ID: `com.alexmitre.samanthakey`
- Keyboard extension: `com.alexmitre.samanthakey.keyboard`
- App Group: `group.com.alexmitre.samanthakey`
- Product ID: `samantha_key_monthly`
- Trial: 3 days free, then MXN $149/month
- Supported UI languages: English, Spanish, French, Italian, Korean, Portuguese, Simplified Chinese, Japanese
- Data policy: no stored audio, transcripts, or translation history

## Structure

- `SamanthaKey/` - SwiftUI iOS app with native WebRTC Realtime audio
- `SamanthaKeyKeyboard/` - custom keyboard extension for translated text insertion
- `SamanthaMac/` - macOS voice assistant with Realtime speech, local tools, CUA Driver integration, and approval gates
- `Shared/` - App Group state and language model shared by app and keyboard
- `supabase/` - Edge Functions and database migration
- `web/` - Vercel support/privacy site

## iOS keyboard flow

iOS custom keyboards cannot record from the microphone directly. Samantha Key uses a compliant handoff:

1. The user taps the keyboard microphone.
2. The keyboard opens `samanthakey://record?source=keyboard&targetLanguage=<code>`.
3. The main app records audio, streams it to OpenAI Realtime through a Supabase-issued token, and writes translated text to the App Group.
4. The keyboard reads the pending translated text and inserts it into the active text field.

## Local iOS build

```bash
xcodegen generate
xcodebuild -project SamanthaKey.xcodeproj -scheme SamanthaKey -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Samantha Mac local assistant

Samantha Mac is a separate macOS target for hands-free local computer control. It does not embed or commit API keys.

Capabilities:

- Low-latency speech session with OpenAI `gpt-realtime-2`.
- Mic capture as 24 kHz PCM and realtime audio playback.
- Local function tools: `shell_exec`, `open_app`, `read_screen`, and `list_apps`.
- CUA Driver integration for app launch, app/window listing, and screen/accessibility-tree reading.
- Approval gate before risky shell commands or unknown tools.
- Menu bar control and Option-Command-Space hotkey.

Setup:

```bash
xcodegen generate
xcodebuild -project SamanthaKey.xcodeproj -scheme SamanthaMac -destination 'platform=macOS' build
```

Run the `SamanthaMac` scheme in Xcode, paste your OpenAI API key once, and press Save. The key is stored in local macOS Keychain under `com.alexmitre.samanthamac.openai`. You can also launch from a shell with `OPENAI_API_KEY` for development.

Local action requirements:

- Install and grant permissions to CUA Driver for screen/app automation.
- Grant Microphone permission to Samantha Mac.
- Grant Accessibility permission if you want the global hotkey and deeper UI inspection to work reliably.

Safety model:

- Read-only shell commands can run directly.
- Mutating shell commands require explicit approval in the app UI.
- `read_screen` is exposed as an explicit tool so screen reading happens only when the model asks for it.
- The assistant is instructed not to claim an action is complete until the local tool returns success.

## StoreKit testing

The shared Xcode scheme uses `StoreKit/SamanthaKey.storekit`. Run from Xcode with the `SamanthaKey` scheme to test the native Apple subscription sheet locally.

## Supabase secrets

Set these in Supabase, never in the iOS app:

```bash
supabase secrets set OPENAI_API_KEY=YOUR_OPENAI_API_KEY
supabase secrets set OPENAI_REALTIME_TRANSLATE_MODEL=gpt-realtime-translate
supabase secrets set OPENAI_CLIENT_SECRET_TTL_SECONDS=120
```

## Web

Production support site: https://samantha-key-support.vercel.app

```bash
cd web
npm install
npm run build
```

## Release checklist

1. Configure App Group and keyboard extension IDs in Apple Developer.
2. Create App Store app and subscription group/product in App Store Connect.
3. Deploy Supabase migration and Edge Functions.
4. Deploy the Vercel support site and use it in App Store metadata.
5. Generate polished App Store screenshots from verified app states.
6. Archive, upload, and submit after device testing.
