# Samantha Key App Store Screenshots

## iPhone 6.9" (APP_IPHONE_69, 1320x2868) — rebuilt 2026-10-08

- Source: real simulator captures of the shipping views on `SK 17 Pro Max QA` (iOS 27.0), app 1.1.1 (10) Debug, Xcode 27.1 RC.
- Composition: `marketing/index.html` rendered by `marketing/render_69.py` (Playwright WebKit).
- Raws: `raw/iphone-69/en-US/` (keyboard = real keyboard extension in Reminders).
- Ships with the next version (1.1.0 is in App Review).

1. Voice translation keyboard — real keyboard in Reminders.
2. Live translation — translator with a sample translation.
3. Keyboard handoff — recording screen plus the keyboard.
4. Private by design — keyboard setup screen.
5. 3-day free trial — real paywall with the storefront price.

## iPhone Duo (APP_IPHONE_DUO) — 2026-10-08

- Inner 2853x2007 (4) and cover 1398x2034 (1) from `raw/iphone-duo/en-US/`, composed by `marketing/duo.html` + `render_duo.py`. Uploaded with 1.1.0.

## Quality gate

- Dimensions and RGB (no alpha) verified with Pillow; Duo sizes checked against live App Store Connect specs.
- Copy reviewed against in-app claims (no fixed price, "no transcript history").
