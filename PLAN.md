# Photo2PDF — build plan

A small, offline-first utility that turns a set of photos into one PDF, on
**desktop (Linux/Windows/macOS)** and **Android**, from a single Flutter codebase
with a Material 3 interface.

---

## 1. Product scope

| In scope (v1) | Out of scope (v1) |
| --- | --- |
| Pick photos in any format we can decode | OCR / text extraction |
| Reorder pages, remove one, clear all | Editing or cropping photos |
| Page size: A4, Letter, or match the photo | Merging existing PDFs |
| Page orientation: auto, vertical, horizontal | Printing, sharing |
| Clear the whole photo list in one tap, with undo | Batch renaming, watermarks |
| PDF → photos: one JPEG per page at 150 / 200 / 300 DPI | Scanning, OCR, sharing |
| Compress photos on the way in (original / balanced / small) | Editing, cropping |
| Password-protect the PDF | Watermarks, signatures |
| Photos from the gallery (default) or the file browser | Camera capture, cloud drives |
| Adjustable white margin | Cloud upload / accounts |
| Save the PDF to disk | Printing, in-app sharing |

Everything runs on the device. No network access, no telemetry, no uploads.

## 2. Supported photo formats

| Format | How it is handled |
| --- | --- |
| JPEG/JPG | Embedded byte-for-byte (`DCTDecode`), no re-encode — smallest output |
| PNG, WebP, GIF, BMP, TIFF | Decoded by the `image` package and stored as pixels |
| HEIC/HEIF, AVIF | Decoded by the platform codec (`dart:ui`), transcoded to PNG once |
| TGA, ICO, PSD, PNM, EXR, PVR | Decoded by the `image` package (reachable when a file arrives, e.g. via a future drag-and-drop) |

Anything undecodable is skipped with a message, never silently dropped or
written as a broken page. Page orientation is a choice: `Auto` turns each sheet
to follow its photo (a landscape photo gets a landscape sheet), while `Vertical`
and `Horizontal` keep every page the same way up.

## 3. Why Flutter

- One widget tree for desktop and Android; only the file picker and the save
  path differ per platform.
- Material 3 comes from the `material_ui` package shipped with Flutter 3.50
  (`ColorScheme.fromSeed`, `FilledButton`, `ChoiceChip`, adaptive density).
- The `pdf` package writes PDFs in pure Dart, passes JPEG through untouched and
  rasterises everything else via `package:image`.

## 4. Architecture

```
UI (Material 3)                    lib/src/screens, lib/src/widgets
      │
      ▼
Services (platform edges)          lib/src/services
      │
      ▼
Core (pure Dart, no plugins)       lib/src/core
```

- **Core** — `photo_info.dart` sniffs the format and reads width/height (JPEG
  from its SOFn header, everything else through `image`); `platform_decoder.dart`
  is the `dart:ui` fallback for HEIC/AVIF; `pdf_builder.dart` lays one photo per
  page on A4 / Letter / photo-sized pages, upright or on its side as chosen.
- **Services** — `image_picker_service.dart` (the system photo picker by
  default, the file browser with an extension filter on request; validates and
  transcodes when needed), `pdf_saver.dart`
  (writes into the chosen folder, `Downloads/Photo2PDF` on Android through
  MediaStore, real folder on desktop) and `settings_store.dart` /
  `save_location.dart` (the remembered setup and the folder helpers).
- **UI** — one responsive screen: two columns from 840 px (desktop), stacked
  below (phones), options capped at 55% of the height so nothing is clipped.

### Data flow

1. `Add photos` → picker returns bytes → format sniffed → HEIC transcoded if
   needed → `SelectedImage` list (id, name, bytes, width, height).
2. User reorders / removes; page size and margin live in screen state.
3. `Create PDF` → `buildPdf()` → bytes → `PdfSaver.save()` → the file lands in
   the save folder (`Downloads/Photo2PDF` on Android, `~/Downloads/Photo2PDF`
   or the folder picked in Settings on desktop) → snackbar with that location.
   `Ask each time` in Settings swaps the folder for a system save dialog.

## 5. File map

```
lib/main.dart                              app entry, MaterialApp with themes
lib/src/theme.dart                         Material 3 palette + component themes
lib/src/screens/home_screen.dart           bottom bar: to PDF / to photos
lib/src/screens/converter_screen.dart      photos to PDF and its state
lib/src/screens/pdf_to_images_screen.dart  PDF to photos and its state
lib/src/screens/settings_screen.dart       photo source + save folder
lib/src/widgets/output_panel.dart          page size, orientation, margin, password
lib/src/widgets/empty_state.dart           first-run empty state
lib/src/widgets/image_card.dart            thumbnail row with drag handle
lib/src/widgets/notices.dart               one snackbar style for both screens
lib/src/core/photo_info.dart               JPEG header parser + decoder probe
lib/src/core/platform_decoder.dart         dart:ui fallback for HEIC/AVIF
lib/src/core/pdf_builder.dart              page sizing, compression + PDF assembly
lib/src/core/pdf_encryption.dart           RC4 128-bit password protection
lib/src/models/selected_image.dart         photo model + size formatting
lib/src/services/image_picker_service.dart file picking, validation, transcoding
lib/src/services/pdf_saver.dart            platform-aware saving
lib/src/services/pdf_page_renderer.dart    PDFium page rendering to JPEG
lib/src/services/page_saver.dart           writes rendered pages
lib/src/services/save_location.dart        save folder, unique names, labels
lib/src/services/settings_store.dart       remembered page size, margin, folder
test/photo_info_test.dart                  format/size parsing tests
test/pdf_builder_test.dart                 PDF output tests (6 formats)
test/photo_normalizer_test.dart            EXIF rotation tests
test/save_location_test.dart               folder, free name, saving tests
test/settings_store_test.dart              persisted settings tests
test/fixtures/                             jpg, png, webp, gif, bmp, tiff, heic
```

## 6. Milestones

### M0 — Foundation (done)

- [x] Flutter project for Android + Linux + Windows + macOS, app id
      `com.sysnefo.photo2pdf`
- [x] Material 3 theme (light + dark, seeded palette, adaptive density)
- [x] Pick photos, validate them, show a thumbnail list
- [x] Reorder, remove, clear all
- [x] Page size (A4 / Letter / fit photo) + margin
- [x] PDF → photos mode (PDFium through `pdfrx`), JPEG per page
- [x] Clear all photos from the list header or the app bar: a confirmation
      when three or more photos would go, one tap of undo either way
- [x] Page orientation (auto / vertical / horizontal)
- [x] On-the-fly compression (original / balanced / small)
- [x] Password-protected PDFs
- [x] PDF generation, JPEG passthrough, multi-format decode
- [x] Save to disk per platform, into `Downloads/Photo2PDF` by default
- [x] Unit tests for format parsing and PDF output (30 tests)
- [x] Android debug APK, tested on an emulator
- [ ] Signed Android release build (needs a keystore + store setup)

### M1 — Everyday usability

- [x] Show the output file name in the options panel.
- [x] Remember the last page size and margin (`shared_preferences`).
- [x] Bake EXIF orientation, so phone photos never come out sideways.
- [x] Keep raster photos from bloating the PDF: anything that is not a JPEG is
      resampled to 300 DPI for the page (measured: a 4032×3024 PNG page went
      from 31.1 MB to 17.2 MB, while the same JPEG stayed at 1.26 MB).
- [x] Choose where PDFs go in a Settings screen (`Downloads/Photo2PDF` by
      default, any folder on desktop, "ask each time" for a system dialog).
- [x] Gallery by default, with a Gallery / Files switch in Settings.
- [x] Desktop drag & drop of photos onto the window (`desktop_drop`): a
      highlight covers the window while a file hovers, dropped paths go through
      the same checks as picked ones, and only the visible tab takes drops.

### M2 — Release readiness

- Launcher icon + adaptive icon, splash colour, store metadata.
- Android: review `minSdk`, keystore-backed `signingConfig`, `appbundle`;
  listing text and screenshots.
- Desktop: release bundles, `.desktop` entry, AppImage/deb wrapper.
- CI: `flutter analyze` + `flutter test` on push, artifact builds per platform.
- Guard against out-of-memory on 50+ photos by streaming pages.

## 7. Risks and limitations

- **HEIC/AVIF on desktop** — Skia on Linux/Windows/macOS usually cannot decode
  them, so those files are rejected there; Android handles them. A libheif-based
  decoder would close the gap.
- **Memory** — picked files are held in memory (a few MB each; HEIC transcodes
  to PNG). Fine for tens of photos; M2 adds a cap.
- **EXIF metadata** — a photo that needs rotation has its EXIF block dropped
  when the pixels are baked (which also removes GPS and device serial numbers).
  Photos that are already upright keep their original bytes.
- **Encrypted PDFs in** — password-protected PDFs cannot be opened in the
  PDF → photos mode yet (`pdfrx` takes a password provider; the dialog is not
  wired to it), so they fail with a message.
- **PDF password** — the standard security handler (RC4 128 bit, PDF 1.4) is
  used because every viewer accepts it; AES-256 would be stronger but is not
  what older Android viewers understand. The password is held in memory only
  and is never written to the app's preferences.
- **Compression cost** — `balanced` and `small` re-encode every photo as JPEG,
  which discards transparency and takes a moment per photo on a phone. Photos
  that are already small still get re-encoded; `original` leaves bytes alone.
- **Android saving** — an app may write into its own folder in Downloads
  without asking, so the default is `Downloads/Photo2PDF`; any other location
  needs the "Ask each time" dialog. A share sheet (`share_plus`) is the natural
  follow-up. iOS is untested.
- **Android picker** — Android redirects image file requests to its Photo Picker
  for gallery images; the file browser ("Downloads", "Images") is still
  reachable from the picker's drawer for files outside the gallery.

## 8. Verification

| Check | Command | Status |
| --- | --- | --- |
| Static analysis | `flutter analyze` | clean |
| Unit tests | `flutter test` | 48 passing |
| Desktop build | `flutter build linux --debug` | builds, app launches |
| Android build | `flutter build apk --debug` | builds, installs on emulator |
| Emulator run | Pixel 6, API 35 | PNG + WebP + BMP + HEIC → 4-page A4 PDF; rotated JPEG shows upright; page size, orientation, compression, photo source and save folder survive a restart; PDF lands in `Downloads/Photo2PDF`; "Ask each time" opens the system save dialog; Add photos opens the system photo picker by default and the file browser when Files is chosen; a Small + password PDF pulled off the device opens with `qpdf --password` and refuses the wrong one; the 4-page PDF from earlier converts back to 4 JPEGs (2338×1653 at 200 DPI) in `Downloads/Photo2PDF` |

Not yet exercised: a physical phone, the desktop folder picker and save dialog,
desktop HEIC, and drag-to-reorder on a device.

## 9. Working with the project

```bash
flutter pub get
flutter run -d linux            # desktop
flutter run -d emulator-5554    # Android emulator (AVD `jpg2pdf`)

# Android needs an SDK with platforms + build-tools + NDK. On this machine the
# usable SDK lives in .toolchain/android-sdk (gitignored), so point Flutter at
# it once — the global config otherwise wins over local.properties:
flutter config --android-sdk "$PWD/.toolchain/android-sdk"
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
flutter build apk --debug

# Emulator as a user unit so it outlives the shell that started it:
systemd-run --user --unit=jpg2pdf-emu --collect \
  --setenv=ANDROID_SDK_ROOT="$PWD/.toolchain/android-sdk" \
  /opt/android-sdk/emulator/emulator -avd jpg2pdf -no-window -no-snapshot -no-audio \
  -no-boot-anim -gpu swiftshader_indirect -memory 2048
```

The project folder is still named `jpg_to_pdf`; everything inside (package name,
app id, window titles, binary name) now says `photo2pdf` / Photo2PDF.
