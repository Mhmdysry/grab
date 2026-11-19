# Changelog — Grab Expressive

All notable changes in **Grab Expressive** (a Material 3 Expressive fork of [`Asta39/grab`](https://github.com/Asta39/grab)) are documented in this file.

---

## [Latest] — Release Notes

### Highlights
- **In-App About Screen — Fork Overview & What's New**: Added a dedicated **"About this fork"** card in **Settings → About** crediting [`Asta39/grab`](https://github.com/Asta39/grab) and highlighting all Material 3 Expressive & UX improvements introduced in **Grab Expressive**, plus a direct link to the upstream repository.
- **Automated Rich Release Notes**: Updated `.github/workflows/android.yml` to publish structured release notes from `CHANGELOG.md` and recent commits on every GitHub Release (visible both on GitHub and inside the in-app updater).
- **Updated `README.md` & App Screenshots**: Overhauled `README.md` with an **About This Fork** comparison table, updated architecture docs, a new 3-up banner, and 6 real Grab Expressive screenshots across AMOLED Mono Dark and Grab Amber Light themes.

---

## [v1.0.19] — 2026-11-19

### Fixed
- **Floating Share Window Transparency (`DecorView color=ff010102 d=null`)**: Prevented `ShareActivity.ensureViewsTransparent` from setting `decor.background = null` on the root `DecorView`, which caused Samsung One UI / Android `DecorView.setWindowBackground(null)` to fall back to an opaque `#FF010102` dark window background. Added `android:windowBackgroundFallback="@android:color/transparent"` to `Theme.Grab.Translucent`.
- **Zero-Window Silent Instant Grab Execution**:
  - Decoupled silent Instant Grab from widget lifecycle and `addPostFrameCallback` by running `initShareOverlayBridge` and `runSilentInstantGrab` directly on the root `ProviderContainer`.
  - Started `DownloadService` in the foreground via `EnginePlugin.beginSilentFetch` inside `ShareActivity.onCreate` prior to `finish()` so OEM background app freezers cannot suspend `yt-dlp` metadata extraction.
  - Inserted an active download row immediately on share and added cross-engine `"sync"` events in `EnginePlugin.kt` + `DownloadRepository` so downloads appear and update live in the main app.

---

## [v1.0.17] — 2026-11-19

### Added
- **Native `PackageInstaller.Session` In-App Updater**:
  - Added `UpdateInstallReceiver` and streamed downloaded APKs through Android's `PackageInstaller.Session` API (`MODE_FULL_INSTALL`) after verifying archive integrity with `PackageManager.getPackageArchiveInfo` and matching `Content-Length`.
  - Added exact installer failure reporting (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`, `INSTALL_FAILED_VERIFICATION_FAILURE`, etc.) and 1-tap fallback buttons in **Settings → About** (`Open with system package installer` and `Download APK in browser`).
- **Zero-Window Silent Instant Grab Toast Feedback**: When **Instant Grab** is enabled, sharing a link from any app shows a native Android `Toast` (`"Instant Grab: starting download…"`) and immediately closes `ShareActivity` with no floating window.

### Changed
- **Home Header Cleanup**: Removed the duplicate top-right paste button from the Home header while keeping the Companion Orb's 1-tap clipboard paste action.

---

## [v1.0.16] — 2026-11-19

### Added
- **In-App Debug & Crash Log Viewer (`Settings → About → Debug log`)**:
  - Added persistent rolling log capture (`AppLog`, 256 KB `grab_debug.log`) hooked into `FlutterError.onError` and `PlatformDispatcher.instance.onError` across both `main` and `shareMain` entrypoints.
  - Built a 3-tab viewer (`App Log`, `Errors Only`, `Android Logcat`) with 1-tap **Copy**, **Share**, **Refresh**, and **Clear** actions.
- **Persistent Library with Disk Recovery**:
  - Added `homeClearedJobIdsProvider` so **Clear finished** on the Home screen only hides finished cards from Home while preserving their database rows, metadata, and thumbnails in the **Library** tab.
  - Added `mergeDiskFiles` and `outputDirProvider` so media files on disk in `Download/Grab` remain visible and playable in the Library even if their history rows were previously removed.

### Fixed
- **`ShareActivity` `TextureView` Crash**: Fixed `UnsupportedOperationException: TextureView doesn't support displaying a background drawable` by setting `view.isOpaque = false` on `TextureView` instead of calling `setBackgroundColor`. Removed `AudioServicePlugin` from `grab_share_engine` so it never conflicts with `MainActivity`'s `AudioServiceActivity`.
- **Audio Download Detail & Player Crash**: Added a dedicated `_AudioPreview` in `DownloadDetailScreen` using `AudioPlayback` instead of initializing a platform-view `VideoPlayerController` on audio-only files, and fixed shared `ImageInfo` disposal in `extractArtworkSeed`.

---

## [v1.0.14] — 2026-11-19

### Added
- **Material 3 Expressive Redesign & Customization Studio**:
  - 9 curated M3 seed palettes (`Grab Amber`, `Coral`, `Violet`, `Emerald`, `Cobalt`, `Rose`, `Tangerine`, `Teal`, `Slate`), Android 12+ wallpaper Dynamic Color, 4 scheme variants (`Expressive`, `Vibrant`, `Tonal`, `Mono`), AMOLED Pure Black mode, and 3 contrast levels.
  - Physics-based M3 Expressive motion presets (`Expressive`, `Standard`, `Snappy`, `Off`), corner shape styles (`Expressive`, `Balanced`, `Crisp`), card density presets, configurable Library grid columns, and app-wide font scaling.
- **Koda-Style Floating Navigation & Shape-Morphing Companion Orb**:
  - Redesigned 3-tab floating pill dock (**Home**, **Library**, **Settings**) where labels expand smoothly only on the selected tab, with distinct per-tab selection animations (spring bounce on Home, wave-tilt on Library, 180° gear spin on Settings).
  - Unified active & completed Downloads directly onto the Home screen with filter chips (`All`, `Active`, `Completed`) and swipe gestures (swipe right to Pause/Resume/Retry, swipe left to Cancel/Remove).
  - Companion Orb that revolves through 6 Material 3 polygon shapes (`cookie9` → `sunny` → `clover` → `pentagon` → `pill` → `squircle`) with full-bleed rotating album art inside a fixed circular progress ring, freezing on its current polygon when paused.
- **Translucent Floating Share Card**:
  - Dedicated `ShareActivity` (`grab_share_engine`) that opens over the source app (TikTok, YouTube, Instagram, etc.) with quick Video/Audio/Quality chips, expandable Trim/Subtitles/Playlist controls, and 1-tap **Instant Grab** mode.
- **Dynamic Artwork Color Extraction & Wavy Audio Scrubber**:
  - Real-time dominant color extraction from video/audio artwork on Detail and Audio Player screens, paired with an M3 Expressive squiggly/wavy audio scrubber.
- **Persistent Release Signing**: Configured consistent release keystore signing so APK updates install cleanly in place without requiring a reinstall.
