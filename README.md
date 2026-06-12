# Manga Translator

Point it at a manga (or any comic) page and get every speech bubble translated
into natural English. Works with any source language — Japanese, Korean,
Chinese, French, anything.

Runs on **Android** and **Windows** from the same code. Translation is done by
Google Gemini using a **free** API key.

## How it works

1. Pick a page — take a photo or choose an image file.
2. Tap **Translate**.
3. You get the original text and an English translation for every speech
   bubble, thought bubble, narration box, sign, and sound effect — in the
   right reading order — plus a one-line summary of the page.

## Translate whole chapters from websites (Windows)

On Windows, **Translate from a website** opens a built-in browser with
shortcuts to MangaFire, Rawkuma (Japanese raws), and MangaDex (many
languages) — any other manga site works too via the address bar.

1. Browse to a chapter and scroll through it so all pages load.
2. Click **Translate this chapter**.
3. The app collects the page images and translates them one by one. Read
   with the arrow keys: page image on the left, translations on the right.

Pages are translated about one every 10–15 seconds to stay inside the free
Gemini limits; a chapter is typically done in a few minutes, and you can
start reading page 1 right away.

## One-time setup (free)

1. In the app, open **Settings** (gear icon).
2. Tap **Open Google AI Studio** and sign in with a Google account.
3. Click **Create API key** and copy the key.
4. Paste it into the app and tap **Save**.

No credit card needed. The free plan is far more than enough for reading.

## Getting the app

The apps are built automatically by GitHub Actions on every push:

- **Android**: download the `manga-translator-android` artifact, copy the APK
  to your phone, and install it (allow "install from unknown sources").
- **Windows**: download the `manga-translator-windows` artifact, unzip it
  anywhere, and run `manga_translator.exe`. If Windows shows a blue
  "protected your PC" warning, click **More info → Run anyway** (it appears
  because the app isn't signed, which costs money — the app is safe).
