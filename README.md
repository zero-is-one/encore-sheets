# EncoreSheets reader prototype

Requires Flutter 3.50 or later. Alongside the Android and iPad runners, the
project includes a browser target for quick reader checks.

```sh
flutter pub get
flutter run -d <device-id>
```

Run `flutter devices` to find a connected Android tablet or iPad. Local iPad
builds require macOS and Xcode. Use `flutter run -d edge` for a browser preview
on Windows.

The app opens with a bundled three-page demonstration score. Use the folder icon
to import a PDF into the offline library. Use the library icon to search by
title or reopen a score at its last page. The list is ordered by most recently
opened. Imported PDFs on Android and iPad are copied into app storage so moving
the original does not affect the library. The browser preview keeps its library
for the current session.

Swipe or tap the outer quarters to turn pages, and tap the
middle to show or hide controls. Pinch to zoom and use Fit page to reset the view.
The bottom slider jumps to a page when released. The reader accepts arrows,
Page Up, Page Down, Space, and Enter from a keyboard or keyboard-mode pedal.

Use the pen button or long-press the page to mark it up. A stylus or mouse draws
by default. Turn on Finger for touch-only input. Tap Done to resume pan and zoom.
Choose Pen, Highlighter, or Erase strokes. The eraser removes whole strokes it
touches. Undo reverses the latest edit on the current page. Completed edits to
imported scores are saved independently of the source PDF and restored when the
score reopens. Ink on the bundled sample is temporary. The browser preview
keeps imported scores and ink for the current session.

To check the offline library, import two PDFs and leave them on different
pages. Force-close the app, turn on airplane mode, then reopen each score from
the library and check that it resumes at the saved page.
Mark up both scores before switching between them, then check that their ink
reappears on the correct pages after restarting offline.

Open **Score library → Setlists** to name a setlist, add scores, and drag them
into performance order. Tap a setlist to start at page one of its first score.
At the end of a score, turn forward again to start the next score at page one.
Use the play icon in the reader to enter performance mode. It keeps the screen
awake and leaves page turning available with the editing controls hidden.

On both tablets, try a large scanned PDF in airplane mode, repeat page turns
with a pedal, and draw while resting your palm on the screen. Verify that ink
stays aligned after zooming and rotating, and check pedal input again after
returning from the file picker.
