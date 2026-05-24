# Samantha Key

Premium iOS voice translation keyboard with a companion SwiftUI app, StoreKit subscription gating, Supabase token broker, and OpenAI Realtime speech-to-translated-text.

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
