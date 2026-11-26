# EncoreSheets

An offline sheet music reader for Android and iPad, built with Flutter. Import
PDF scores, mark them up, and organize them into setlists for rehearsal and
performance.

[Build from source](#build-from-source) · [File formats](#file-formats) · [Report an issue](https://github.com/zero-is-one/encoresheets/issues)

## What works

- **Read and perform.** Open a score at its last page, jump with the page slider,
  or turn pages by tapping, swiping, or using a keyboard or compatible pedal.
  Use facing pages, half-page turns, or performance mode when you need a
  different view of the music.
- **Mark up a score.** Draw, highlight, add text or notation stamps, and organize
  annotations into layers. Copy a passage from the PDF and place it on the same
  page or another page. The app saves markup separately from the source PDF.
- **Organize your music.** Browse by title or metadata, search scores and
  bookmarks, and arrange setlists in performance order. Add bookmarks, page
  flags, and repeat or coda links to navigate within a score.
- **Rehearse.** Attach a local audio track, record takes, or use the metronome,
  tuner, and virtual piano. Set practice goals and export practice reports as PDFs.
- **Play together.** Share page turns and score changes over local Wi-Fi or use
  a second device to show the facing page.
- **Move and back up your library.** Share editable scores and setlists, export
  PDFs with flattened markup, or save a library backup. Import and export files
  through the system picker or browse Dropbox and Box with a session access token.

## Build from source

Requires Flutter 3.50 or later. Android development requires the Android SDK.
To run on an iPad or iPad simulator, use macOS with Xcode.

```sh
git clone https://github.com/zero-is-one/encoresheets.git
cd encoresheets
flutter pub get
flutter devices
flutter run -d <device-id>
```

Run `flutter run -d edge` on Windows for a browser preview. The browser library
lasts for the current session. The app opens with a bundled sample score.
On an installed device, open **Score library → Import PDF** to add your own music.

```sh
flutter analyze
flutter test
```

## File formats

| Format | Use |
| --- | --- |
| PDF | Import a score, export the original, or export a PDF with annotations flattened into the pages. |
| `.encorescore.zip` | Share an editable score with its EncoreSheets annotations and metadata. |
| `.encoreset.zip` | Share an editable setlist with scores or placeholders. |
| Library backup ZIP | Save the catalog with its PDFs, or export just the catalog for use with separately stored scores. |

The library also imports scanned pages and creates PDFs from templates or
from TXT, RTF, DOC, and DOCX documents.

## Desktop backup utility

Use [the backup utility](tools/library_backups.py) with Python 3 on Windows,
macOS, or Linux. Export a ZIP from **Score library → Tools → Backup & restore** in the
app first. The copy command verifies the destination and preserves an existing
file with the same name.

```sh
python tools/library_backups.py inspect "EncoreSheets backup.zip"
python tools/library_backups.py verify "EncoreSheets backup.zip"
python tools/library_backups.py copy "EncoreSheets backup.zip" "Backups"
```
