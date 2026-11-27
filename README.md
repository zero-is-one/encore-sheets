<p align="center">
  <img src="assets/brand/app-icon-classic.png" width="96" height="96" alt="EncoreSheets" />
</p>

<h1 align="center">EncoreSheets</h1>

<p align="center">
  <strong>An offline sheet music reader for Android and iPad.</strong><br />
  Import PDF scores, mark them up, and organize them into setlists for rehearsal and performance.
</p>

<p align="center">
  <a href="#test-builds">Test builds</a> ·
  <a href="#what-works">Features</a> ·
  <a href="#build-from-source">Build from source</a> ·
  <a href="#file-formats">File formats</a> ·
  <a href="https://github.com/zero-is-one/encoresheets/issues">Report an issue</a>
</p>

<p align="center">
  <a href="https://github.com/zero-is-one/encoresheets/actions/workflows/checks.yml?query=branch%3Amain"><img src="https://github.com/zero-is-one/encoresheets/actions/workflows/checks.yml/badge.svg?branch=main" alt="Flutter checks" /></a>
</p>

## Test builds

Open a successful [Build test packages](https://github.com/zero-is-one/encoresheets/actions/workflows/builds.yml)
run and look under **Artifacts**. Sign in to GitHub to download a package while
its artifact is available.

- **Android** — The workflow can build a debug APK for testing.
- **iPad** — The unsigned device IPA requires signing before installation.
- **macOS and Windows** — The workflow produces preview ZIPs for testing the
  macOS app and the Windows x64 executable with its supporting files.

## What works

- **Read and perform.** Open a score at its last page, jump with the page slider,
  or turn pages by tapping, swiping, or using a keyboard or compatible pedal.
  Use facing pages, half-page turns, or performance mode when you need a
  different view of the music. Open **Display → Scrolling display** for
  continuous vertical scrolling with fit-page and fit-width scaling. Choose a
  library default or override it for the current score.
  In a vertical display, open **Display → Automatic scrolling** to set
  the speed and optionally continue to the next setlist score. Use **Input
  shortcuts** to assign a keyboard key or pedal to start and stop scrolling.
  On wide tablets, **Display → More display settings → Sidebar and lists**
  can show the library beside the score while you continue turning pages.
- **Mark up a score.** Draw, highlight, add text or notation stamps, and organize
  annotations into layers. Copy a passage from the PDF and place it on the same
  page or another page. The app saves markup separately from the source PDF.
- **Organize your music.** Browse by title or metadata, search scores and
  bookmarks, and arrange setlists in performance order. Add bookmarks, page
  flags, and repeat or coda links to navigate within a score.
  Add on-page buttons for websites, supported app links, or local files through
  **Score actions → On-page actions**. On Android and iPad, file buttons open the
  selected attachment with a compatible app. Attachments stay on the device
  where they were added.
- **Rehearse.** Attach a local audio track, record takes, or use the metronome,
  tuner, and virtual piano. Set practice goals and export practice reports as PDFs.
- **Play together.** Share page turns and score changes over local Wi-Fi or use
  a second device to show the facing page.
- **Move and back up your library.** Share editable scores and setlists, export
  PDFs with flattened markup, or save a library backup. Import and export files
  through the system picker, or browse and transfer PDFs directly with Dropbox,
  Box, Google Drive, and OneDrive using a session access token. Google Drive
  uses the `https://www.googleapis.com/auth/drive` scope and OneDrive uses
  delegated Microsoft Graph `Files.ReadWrite`.
- **Sync a shared library.** Use the same WebDAV folder on Android and iPad
  to sync scores, metadata, and setlists while keeping personal annotations on
  each device.

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

## Shared library setup

1. Create a dedicated HTTPS WebDAV folder and give each device read and write
   access. The server must support WebDAV folder listing and file writes.
2. On each device, open **Score library → Tools → Device sync**. Enter the
   same folder URL and your WebDAV credentials, then tap **Connect WebDAV**.
   Each connected device can publish its local scores and setlists to the folder.
3. Tap **Refresh now** to send and receive changes. EncoreSheets also checks
   periodically while the app is open and when you return to it. Reconnect
   after restarting the app.

Sync merges edits to different catalog fields, including individual metadata
fields. Same-field conflicts use the latest published revision. If two devices
publish the same revision concurrently, both pick the same winner by device ID.
Ink, page notes, reading position, and reader settings stay local. WebDAV sync
supports PDFs up to 50 MB and skips scores with an access deadline.

## Backup and recovery

Use **Score library → Tools → Backup & restore** to export a full library ZIP
with PDFs, annotations, setlists, and portable app settings. During restore,
choose whether to apply the saved settings. Device connections and linked audio
files stay on the original device.

EncoreSheets keeps two verified local catalog snapshots and uses the newest
usable one if the live catalog is missing or unreadable. These snapshots cover
catalog data and settings. Keep an exported full ZIP to recover missing score
files or move to another device.

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

## AI assistants (MCP)

EncoreSheets can connect to a self-hosted MCP server from the installed app.
It uploads score titles, composers, durations, and setlist membership while
connected. The PDFs and annotations stay in the local library.

1. On a server with Node.js 24 or later, set `ENCORESHEETS_ORIGIN` to its
   public HTTPS origin, `ENCORESHEETS_ENROLLMENT_KEY` to a secret generated by
   the command below, and `ENCORESHEETS_DB` to a writable SQLite path on a
   persistent volume. Run the service behind an HTTPS reverse proxy that
   forwards the origin's paths to port 8787. The service listens on loopback
   by default. Keep the enrollment key and database private.
2. Run `node tools/run_assistant_server.mjs enroll` in a second shell with
   the same origin and enrollment key. Give the resulting tablet token to
   the musician. Each enrollment creates a separate library.
3. In **Score library → Tools → AI Connections**, enter the server origin
   and tablet token. Add the displayed `/mcp` address to an assistant that
   supports remote Streamable HTTP MCP with OAuth and dynamic client
   registration. When its browser asks for a connection code, generate one
   in EncoreSheets and choose whether to allow setlist requests.
4. Ask the assistant to create a setlist and open the returned approval link
   in the browser used to connect that assistant. Review the score order and
   approve. EncoreSheets applies the request when next opened online, on a
   foreground sync, or when you tap **Sync now**. The setlist is then available
   offline. Revoke individual assistants from the same screen.

```sh
node -e "console.log(require('node:crypto').randomBytes(32).toString('base64url'))"
node tools/run_assistant_server.mjs
node --test tools/assistant_server.test.mjs
```

The service defaults to `http://127.0.0.1:8787` for local testing. Remote
assistants and physical tablets need a reachable HTTPS origin. Restrict
enrollment to the operator and configure reverse-proxy rate limits for public
OAuth endpoints before exposing a deployment.
