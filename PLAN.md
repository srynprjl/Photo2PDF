# JPG to PDF — build plan

A small, offline-first utility that turns a set of JPG photos into one PDF, on
**desktop (Linux/Windows/macOS)** and **Android**, from a single Flutter codebase
with a Material 3 interface.

---

## 1. Product scope

| In scope (v1) | Out of scope (v1) |
| --- | --- |
| Pick multiple JPG/JPEG files | OCR / text extraction |
| Reorder pages, remove single images, clear all | Editing or cropping photos |
| Page size: A4, Letter, or match the photo | Merging existing PDFs |
| Adjustable white margin | Cloud upload / accounts |
| Save the PDF to disk | Printing, sharing targets |

Everything runs on the device. No network access, no telemetry, no uploads —
which also means no privacy policy or backend to maintain for a first release.

## 2. Why Flutter

- One widget tree for desktop and Android: the whole UI and the PDF logic are
  shared, only the file picker and the save path differ per platform.
- Material 3 comes from the `material_ui` package that Flutter 3.50 ships with
  (`ColorScheme.fromSeed`, `FilledButton`, `ChoiceChip`, adaptive visual
  density), so the UI follows Material guidance on both platforms.
- The `pdf` package writes PDFs in pure Dart and can **embed a JPEG byte-for-byte**
  (no decode/re-encode), so conversion is fast and output size stays close to the
  input.

## 3. Architecture

```
UI (Material 3)                    lib/src/screens, lib/src/widgets
      │
      ▼
Services (platform edges)          lib/src/services
      │
      ▼
Core (pure Dart, no plugins)       lib/src/core
```

- **Core** — `jpeg_info.dart` reads the SOFn segment of a JPEG for width, height
  and component count (no decode); `pdf_builder.dart` lays one image per page on
  A4 / Letter / photo-sized pages and returns PDF bytes. Pure Dart, unit-testable.
- **Services** — `image_picker_service.dart` (file_picker, validates each file,
  reports rejected ones) and `pdf_saver.dart` (save dialog on desktop via
  `file_selector`, shared Downloads on Android via `file_saver`).
- **UI** — one screen: image list with drag-to-reorder, options panel, progress
  and snackbar feedback. Responsive: a two-column layout from 840 px wide
  (desktop), a stacked layout below (phones).

### Data flow

1. `Add images` → picker returns bytes → JPEG header parsed → `SelectedImage`
   list (id, name, bytes, width, height).
2. User reorders / removes; page size and margin live in screen state.
3. `Create PDF` → `buildPdf()` → bytes → `PdfSaver.save()` → snackbar with the
   final path.

## 4. File map

```
lib/main.dart                              app entry, MaterialApp with themes
lib/src/theme.dart                         Material 3 palette + component themes
lib/src/screens/converter_screen.dart      the single screen and its state
lib/src/widgets/empty_state.dart           first-run empty state
lib/src/widgets/image_card.dart            thumbnail row with drag handle
lib/src/core/jpeg_info.dart                JPEG header parser
lib/src/core/pdf_builder.dart              page sizing + PDF assembly
lib/src/models/selected_image.dart         image model + size formatting
lib/src/services/image_picker_service.dart file picking + validation
lib/src/services/pdf_saver.dart            platform-aware saving
test/jpeg_info_test.dart                   parser tests
test/pdf_builder_test.dart                 PDF output tests
```

## 5. Milestones

### M0 — Foundation (this commit)

- [x] Flutter project for Android + Linux + Windows + macOS
- [x] Material 3 theme (light + dark, seeded palette, adaptive density)
- [x] Pick multiple JPGs, validate them, show thumbnail list
- [x] Reorder, remove, clear all
- [x] Page size (A4 / Letter / fit image) + margin
- [x] PDF generation with JPEG passthrough
- [x] Save to disk per platform
- [x] Unit tests for the parser and the PDF output
- [x] Android debug APK builds against the local SDK
- [ ] Signed Android release build (needs a keystore + Play/F-Droid setup)

### M1 — Everyday usability

- Desktop drag & drop of files onto the window (`desktop_drop`).
- Show the chosen output file name in the options panel.
- Page preview: render the first page as a thumbnail before saving.
- Remember the last page size and margin (`shared_preferences`).
- Keep EXIF orientation: read the Orientation tag and rotate the page.
- Accept PNG as well (needs a Flutter-side decode/encode via `image`).

### M2 — Release readiness

- Launcher icon + adaptive icon, splash colour, app metadata
  (`flutter_launcher_icons`, `flutter_native_splash`).
- Android: `minSdk` review, `signingConfig` with a keystore kept out of git,
  `flutter build appbundle`; F-Droid/Play listing text and screenshots.
- Desktop: `flutter build linux|windows|macos --release`, a `.desktop` entry and
  an AppImage/deb wrapper for Linux.
- CI: `flutter analyze` + `flutter test` on push, artifact builds per platform.
- Larger-batch safety: guard against out-of-memory on 50+ photos by streaming
  pages instead of holding every image in state.

## 6. Risks and limitations

- **CMYK JPEGs** — the PDF writer only passes through greyscale and YCbCr data,
  so four-component files are refused with a message instead of producing a
  broken page (`readJpegInfo(...).isCmyk`).
- **Memory** — picked files are held in memory (a few MB each). Fine for tens of
  photos, and the `cacheWidth` on thumbnails keeps previews cheap; M2 adds a cap.
- **EXIF rotation** — phone photos may be rotated. Until M1, rotate them with the
  page if they come out sideways.
- **Android saving** — there is no cross-platform "Save as" dialog on Android;
  the file is written to the shared Downloads folder and the snackbar shows the
  path. A share sheet (`share_plus`) is the natural follow-up.
- **Android build on this machine** — `/opt/android-sdk` has no platforms and is
  not writable; verification uses a project-local `.toolchain/android-sdk`
  (platforms 35/36, build-tools 36, NDK 28.2) referenced by
  `android/local.properties`. Install a normal SDK and update `sdk.dir` to drop
  the local one.

## 7. Verification

| Check | Command | Status |
| --- | --- | --- |
| Static analysis | `flutter analyze` | clean |
| Unit tests | `flutter test` | 6 passing |
| Desktop build | `flutter build linux --debug` | builds, app launches |
| Android build | `flutter build apk --debug` | builds (`build/app/outputs/flutter-apk/app-debug.apk`) |

Not yet exercised by hand: picking files, converting, and saving on a real
phone, and the GTK / Win32 save dialog on desktop.

## 8. Working with the project

```bash
flutter pub get
flutter run -d linux            # desktop
flutter run -d <android-device> # phone, USB debugging on

# Android needs an SDK with platforms + build-tools + NDK. On this machine the
# usable SDK lives in .toolchain/android-sdk (gitignored, ~2.6 GB), so point
# Flutter at it once -- the global config otherwise wins over local.properties:
flutter config --android-sdk "$PWD/.toolchain/android-sdk"
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
export ANDROID_SDK_ROOT="$PWD/.toolchain/android-sdk"
flutter build apk --debug

# With a normal SDK installed system-wide, skip the flutter config line and use
# `flutter config --android-sdk <path>` (or unset it) to match.
```

`flutter doctor -v` lists anything still missing for a platform.
