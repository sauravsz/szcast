# szcast — MEMORY

Standalone root repository (detached from `abue-ammar/tinycast`). GitHub: `sauravsz/szcast`. Clone: `Github Repos/szcast` (`upstream` remote tracked for weekly audit via `skills/szcast-upstream-radar`).

## Layout
- Source root `szcast/`, Xcode package `szcast.xcodeproj`, scheme `szcast`, entry `szcast/App/szcastApp.swift`, icon `szcast/szcast.icon`.
- Display strings stay capitalised: `szcast`, `szcast Dev`, `szcast Dictation`; signing identity `szcast Self-Signed`.

## Identity map
- Bundle IDs: `com.sauravsz.szcast` (stable), `.beta`, dev config `.dev`. Helpers `com.sauravsz.szcast.*`.
- URL schemes: `szcast` / `szcast-dev` (plist key `SzcastURLScheme`, build vars `SZCAST_BUNDLE_IDENTIFIER` / `SZCAST_URL_SCHEME`).
- Updater: `ReleaseFeed.repository = sauravsz/szcast`; stable/beta channels are wired, but `SzcastUpdatePublicKey` now carries a real Ed25519 key (`IwtZDpOb…vac=`, private half out of the repo); no update feed is published, so nothing installs over itself yet. Releases are built and signed locally — CI needs a Developer ID, which this fork does not buy.
- Currency rates fetch directly from open CC0 exchange-api CDN (`latest.currency-api.pages.dev/v1/currencies/usd.min.json` with `cdn.jsdelivr.net` fallback) in a single unified GET covering fiat and crypto. Zero tinycast.dev or middleman dependency.
- Support/About/changelog links point at the fork repo; upstream Discord, funding URL and release team secrets removed.
- **KeePassXC & Ente Auth Strict Isolation**: Neither agents nor GitHub shall ever access, inspect, query, read, or export KeePassXC databases (`.kdbx`), keyfiles, master passwords, CLI queries, or entries, nor Ente Auth TOTP secrets, tokens, or `accounts.json`. `.gitignore` enforces exclusion of all database, key, and secret files.

## Web / deploy
- Static landing page in `site/` (`index.html`, `assets/*.webp` feature screenshots, `docs-images/icon.png`); `vercel.json` sets `outputDirectory: site`. Never add `"framework": "static"` — not a valid slug, it fails schema validation; omit the key for static. Screenshot slots are `<img>` inside `.row-shot` with a per-slot `--ratio` matching the file's true aspect ratio; all 10 slots are filled (`hero`, `clipboard`, `quicklinks`, `emoji`, `notes`, `calc`, `aichat`, `focus`, `file-search`, `window-management`, `dictation`). Replacing an image means overwriting `site/assets/<name>.webp` and updating that slot's `--ratio` if the aspect differs. The dictation pill has its own `<section>`: `pill-listening/preview/transcribing.webp` are alpha-keyed cutouts composited over a mock document by `.pill-stage`; the inline script cycles them (hover pauses, reduced-motion disables), and the *same three files* back the state cards below, so there is no second copy to keep in sync.
- Vercel project `szcast` (`prj_dxHc1UekHSnarwZdUH9xYsmeQJL0`, team `team_6BdgmeJhD8C2QlwQhVFkWTmk` / "Abhigha's projects"), linked to `sauravsz/szcast` via the GitHub integration: every push to `main` deploys. Live at https://szcast.vercel.app.
- `szcast.dev` is attached to the project but unregistered/unpurchased (Vercel registrar: available, $9.99 first year / $13 renewal). No DNS yet — README/About hand-written URLs must stay on `szcast.vercel.app` until it's bought.
- Local Vercel CLI is logged out and cannot log in here (network `EBADF` on login/`whoami`); use the REST API with a token instead of the CLI.

## Build / verify (macOS 27, Xcode 27.2)
- `xcodebuild -project Szcast.xcodeproj -scheme Szcast -configuration Release -derivedDataPath "build/DerivedData" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Szcast Self-Signed" OTHER_CODE_SIGN_FLAGS="--timestamp=none" -quiet build`
- `Scripts/run-tests.sh` — all 139 harnesses pass (276s).
- `node Scripts/check-settings-search.js` — 0 errors.
- `./Scripts/benchmark-dictation.sh --ci` — synthetic 30s DSP + Mel + NLP/hotword RTF & latency check.

- **5-Phase Dictation Architecture Overhaul (Phases 1-5 Complete, Installed to `/Applications/szcast.app`)**:
  - Phases 1-2: Pre-allocated tensor/vDSP inference (`ParakeetRecognizer`, `NemotronRecognizer`, `ParakeetCTCRecognizer`, `SileroVADProcessor`), hardware audio conditioning + 350ms warm `AVAudioEngine` pre-roll + CoreAudio device binding, Apple `SpeechAnalyzer`, Deepgram live WebSocket + Groq compressed upload failover, AI/ML & Finance `VocabularyPack` O(N) trie, failed-audio recovery/replay & async `.m4a` history.
  - Phase 3: Sentence-scoped `resolveBacktracks(_:)`, onset stutter collapse (`stutterPrefixRegex`), `applyDeterministicITN(_:)`, `formatSyntaxCommands(_:isCodeContext:isNotesContext:)`, `VoiceMetaCommand` (`undoLast`, `selectAll`, `copyThat`, `newTab`) & Ask AI routing, `AppStyleRouter` window/URL metadata with credential redaction, `isSafePolishEdit` diff circuit breaker + `<transcript>` XML isolation + `detectLocalOpenAIEndpoints()`.
  - Phase 4: Strict `shouldConvertMarkdownToRTF(_:)` + `plainTextOnly`, bundle-aware `pasteboardRestoreDelay(for:)` + `org.nspasteboard.TransientType`/`AutoGeneratedType`, layout-independent `commandVirtualKeyCode(for:fallback:)` (`UCKeyTranslate`), `isEventOnlyTarget(_:)` + AX direct insert readback + `isSecureInputActive` + `focusedCaretRect(in:)`, synchronous `0 ms` HUD `panel.show`, `DictationPillPosition`, compact pill, `fallback` Copy/Paste/Dismiss HUD card, `0.11s` bare hold threshold, inline Dictation Health Inspector.
  - Phase 5: Phonetic `acousticFold(_:)` + single-token/multi-word hotword matching in `DictationDictionaryStore`, incremental 60-item pagination (`loadMore()`) + FTS5 search + `dictationAudioRetentionDays` (`0/7/14/30`, default `14`), `StageTelemetry.rtf` & `redactedDiagnosticBundleJSON()` + `"Last Take Telemetry & Diagnostics"` disclosure, `--ci` RTF benchmark mode.
  - Verified clean: 139/139 test harnesses pass (`run-tests.sh`), zero warnings in modified dictation/insertion files, `codesign --verify --deep --strict "/Applications/szcast.app"` passes, live app running.

- **Weekly Upstream Tinycast Radar (Synced to 876b61dc)**:
  - Reviewed 22 upstream commits since baseline `6fa8ba12`.
  - **Calculator Satoshi Conversions (`08dda28d`)**: Added `satoshi` definition, `satoshisPerBitcoin = 100_000_000.0`, and rate conversion in `CalcCurrency.swift`.
  - **Suppressed HotKeys of Disabled Features (`6f479455`)**: Added `suppressedActions`, `applyAllowance()`, and registration guards in `HotKeyManager.swift` and `AppCore.swift` dynamically unregistering shortcuts when features or extensions are toggled off.
  - **Keyboard-Driven Snippet Argument Prompts (`c1eeb12f`)**: Added `SnippetArgumentsState.swift`, curly quotes delimiter parsing in `SnippetTemplateEngine.swift`, arrow/tab navigation across option lists and text fields, and removed deprecated `DialogChip.swift`.
  - **Universal Control Hyper Forwarding (`9e9be988`)**: Prevented forwarded Hyper chords from toggling Caps Lock via `PhysicalHyperKeyPress` and `ForwardedQuickPressMonitor` correlating physical HID releases with Quartz event taps.
  - **File Search Folder Matching & Hidden Files (`99d1d17a`)**: Enabled multi-term query matching through parent directory names, agent worktree ignore patterns (`.claude/worktrees`, `conductor/workspaces`), and added `includeHiddenFiles` setting in `AppSettings` with Settings search catalog synchronization.
  - Skipped out-of-scope commits: Dictation shortcut removal (violates single-shot and Fn/Globe invariants), iCloud sync (requires Developer ID), out-of-process Settings XPC architecture shift, and monochrome icon styling.

- **Raycast Store Extensions & Blazing Fast Performance Optimization**:
  - **8MB Stack JavaScriptCore Execution Thread (`ExtensionExecutionQueue`)**: Replaced default GCD worker thread dispatch (512KB stack limit) with a dedicated high-performance thread with an 8MB stack. Eliminates `RangeError: Maximum call stack size exceeded` crashes when loading heavy tokenizer libraries (such as `gpt-tokenizer` used across all 14 Groq commands).
  - **Runtime Source & JS Bundle In-Memory Caching**: Added `cachedRuntimeSource` in `ExtensionRuntime` to eliminate redundant disk reads of the 263KB `RaycastRuntime.generated.js` on command boots, and `ExtensionBundleCache` in `ExtensionManager` with mtime invalidation for instant repeat command execution.
  - **Manifest Memoization**: Added `manifestCache` in `ExtensionManifest.load(directory:)` caching parsed `package.json` models by modification date, reducing launcher manifest scanning overhead from ~20ms down to sub-1ms.
  - **Background Prewarming**: Integrated `prewarmRuntimeIfNeeded()` in `ExtensionManager.refresh()` and `stop()`, pre-evaluating the runtime in the background so that manual extension command launches execute with near-zero latency.
  - **Verification**: 20 of 20 installed store extensions (`brew`, `browser-bookmarks`, `coffee`, `design-skills`, `downloads-manager`, `easy-new-file`, `fetch-youtube-transcript`, `finder-file-actions`, `gif-search`, `groq`, `passphrase-generator`, `password-generator`, `pomodoro`, `raindrop-io`, `session`, `shutdown-timer`, `skills`, `skills-re`, `video-downloader`, `zen-browser`) pass automated harness testing. All 13 built-in feature test harnesses (`notes-test`, `calc-test`, `focus-timer-test`, `text-transformer-test`, `stats-feature-test`, `display-tweaks-test`, `clean-keyboard-test`, `screen-capture-test`, `calendar-test`, `duckduckgo-email-test`, `apple-shortcut-test`, `quick-action-test`, `hardware-test`) pass cleanly in sub-second times. Full Debug build succeeds (`xcodebuild -scheme Szcast`).


- **Raycast-Parity ⌘K Action Menu & Upstream Ports (Commits 1–7)**:
  - **⌘K Action Menu Overhaul & Bottom Bar Cleanup**: Cleared launcher shortcut strip from bottom bar (`Finder`, `Info`, `Pin` moved into `⌘K` popover actions). Added `Open With…` (`⌘O`) opening native `NSOpenPanel` across applications and files.
  - **Copy Shortcut Remapping**: Remapped file copy shortcuts across `PaletteShortcut.swift`, `FileSearchScreen.swift`, `AppActionsMenu.swift`, and `LauncherScreen.swift` so `⌘C` copies the file directly (`Paster.copyFile` / `PasteboardFiles.write`) and `⇧⌘C` copies the file path (`.copyPath`). Bare `⌘C` with text selection in the search field preserves standard NSTextView copying.
  - **Commit 1 (`ce2be6ec`)**: In `SzcastApp.swift`, `⌘,` triggers `launcherCoordinator.runCommand(.settings)` so the palette cleanly closes before opening Settings.
  - **Commit 2 (`9d19a6e5`)**: Stacked thirds vertically on portrait/vertical displays in Window Management (`WindowPlacementEngine.swift`, `WindowActionMemory.swift`, `WindowMover.swift`, `docs/features/window-management.md`, `Tests/window-command-test.swift`).
  - **Commit 3 (`970bf4e4`)**: Added `SlotChordReveal.swift` sliding ⌘-digit chords into rows without premature hold reveal; `PalettePanel.swift` and `PaletteState.swift` cancel reveal on chord key press; emoji grid arrow chord isolation.
  - **Commit 4 (`6c3d3b83`)**: Weighted system languages 20x in `TextTranslator.swift` to prevent single-word recognizer misidentifications, and explicitly named the missing translation language in `QuickActionCoordinator.swift`, `QuickActionPanelState.swift`, and `QuickActionResultView.swift`.
  - **Commit 5 (`b11b060d`)**: Added `IconStyle.swift` and `SystemIconTheme.swift` with dynamic system appearance observing, backup coverage in `SettingsBackup.swift`, and settings schema integration.
  - **Commit 6 (`a18de2a8`)**: Updated `docs/features/raycast-import.md` with Raycast 2.0 encrypted export passphrase guidance.
  - **Commit 7 (`e139ed4f`)**: Updated tagline in `AboutView.swift` and `Localizable.xcstrings` to "A native macOS launcher built for productivity. Fast, lightweight, and open source."
  - **Verification**: Debug build succeeded with zero errors (`xcodebuild -scheme Szcast`), `check-settings-search.js` passed with 0 errors, and all 134 test harnesses passed in `Scripts/run-tests.sh`.

- **Settings Typography Controls (v1.1.6)**:
  - Added configurable title (`settingsRowTitleFontSize`, default: 13pt) and subtitle (`settingsRowSubtitleFontSize`, default: 11pt) font sizes for Settings panes in General -> Appearance.
  - Bound `SettingsRowTitle`, `SettingsSectionHeader`, `SettingsRow`, `SettingsFeatureToggleLabel`, `SettingsDetailView`, and `ExtensionsSettingsView` to dynamic settings font size properties.
  - Added live Settings Preview card in `GeneralSettingsView.swift` and synchronized `SettingsSearchCatalog.swift` with 0 errors.
  - Signed release build packaged into `build/szcast-1.1.6.dmg` & `build/szcast-1.1.6.zip`, uploaded to GitHub Release `v1.1.6`, deployed to `origin/main` (Vercel), and installed locally to `/Applications/szcast.app`.

- **Exhaustive UI Padding, Spacing & Layout Margin Audit & Full Remediation**:
  - Conducted full automated & structural design system audit across all 491 presentation and interaction files in szcast.
  - Identified 6 Critical clipping/overlap defects, 77 High visual alignment issues, 137 Medium token drifts, and 144 Low style nits; 127 files conform cleanly to `Theme` tokens.
  - **Phase 1 Critical Remediation**:
    - **`AIModelChecklist.swift` & `AIProvidersPanel.swift`**: Removed negative 9pt bounds overhang (`bounds.insetBy(dx: 0, dy: -overhang)`) in `ChecklistContainer` that was bleeding into `SettingsFilterField` and clipping bottom checkboxes; mapped `table.frame = bounds` directly with exact `sizeThatFits` row calculation.
    - **`AIChatSidebarView.swift`**: Added `.padding(.horizontal, Theme.Spacing.lg)` inside `ChatSidebarRow`, preventing zero-inset conversation titles and pin icons from colliding with window edges while keeping full-bleed hover highlights.
    - **`DictationPanel.swift`**: Expanded SwiftUI `DictationPill` maxWidth from 192pt up to 360pt and implemented dynamic NSPanel width calculations in `DictationPanelController.show()` and `updatePreviewText()`, resolving command mode text truncation (`Rewrite: ...`).
    - **`AppleShortcutsSettingsView.swift`**: Isolated `Button("Open Shortcuts")` into its own discrete Form `Section`, eliminating table bottom overhang bleeding over the action button.
    - **`ExtensionDetailView.swift`**: Added `.padding(.horizontal, metrics.spacing.md)` to Markdown table cells, giving tabular numbers and text proper breathing room against cell borders.
  - **Phase 2 High Visual Alignment Remediation**:
    - **`RootPaletteView.swift`**: Migrated launcher category scope chips (`All`, `Apps`, `Commands`, etc.) to `metrics.spacing.xxs`, `metrics.spacing.sm`, `metrics.spacing.xs`.
    - **`AIChatDetailView.swift`**: Added `.padding(.horizontal, Theme.Spacing.sm)` on the composer attachment chips container, aligning staged images/files directly over composer input.
    - **`FocusTimerScreen.swift`**: Converted status chips from hardcoded 6pt/2pt to `Theme.Spacing.sm` and `Theme.Spacing.xxs`.
    - **`WeatherCardView.swift`**: Added `.fixedSize(horizontal: true, vertical: false)` on 4-hour forecast strip preventing column compression.
    - **`ChangelogSettingsView.swift`**: Standardized scroll insets and card paddings to `Theme.Spacing.xxl`, `Theme.Spacing.xl`, and `Theme.Spacing.sm`.
    - **`ClipboardView.swift`**: Replaced raw `12` with `metrics.spacing.xl` and added `.padding(.bottom, metrics.spacing.md)` on info pill row.
  - **Phase 3 Settings & Dashboard Harmonization**:
    - **`DictationInsightsDashboardView.swift`**: Standardized card container padding and metrics from `14pt` / `16pt` to `Theme.Spacing.xl` (12pt), `Theme.Spacing.md`, and `Theme.Spacing.xxl`.
    - **`QuicklinksSettingsView.swift`**: Added `header: { SettingsSectionHeader(.quicklinksQuicklinks) }` to `library` section, restoring standard Form section header spacing above the filter field.
    - **`KeePassXCScreen.swift`**: Constrained `KeePassXCSetupView` form width with `maxWidth: 420` preventing horizontal window stretching; unified `KeePassXCEntryDetailView` `ScrollView` by eliminating duplicate per-row horizontal padding and replacing double-padding with container insets and clean row spacing; tokenized `ShortcutBadge` geometry.
    - **`SettingsComponents.swift`**: Aligned `SettingsEditorTextArea` horizontal padding to `Theme.Spacing.lg` matching single-line text fields; rounded `SettingsTabIcon` scaled padding; added explicit spacing to `SettingsScopeRow`; added vertical breathing room to `SettingsFilterField`.
  - **Phase 4 Token & Hairline Hygiene**:
    - Converted literal `Rectangle().frame(height: 1)` and `.frame(width: 1)` dividers to `Theme.Size.hairline` across `MeetingDetailsView.swift`, `ExtensionDetailView.swift`, `ExtensionListView.swift`, `ClipboardScreen.swift`, `DictionaryEntryView.swift`, and `OnboardingCard.swift`.
    - Cleaned magic numbers in `CleanKeyboardSettingsView.swift`, `EnteAuthSettingsView.swift`, and `ExtensionsSettingsView.swift`.
  - Verified across compiler diagnostics, `node Scripts/check-settings-search.js` (0 errors), and full test suite harness execution.

- **Full Codebase Audit & Hardening**:
  - **Accessibility Type Safety**: Added `CFGetTypeID(focusedElement) == AXUIElementGetTypeID()` verification in `AgenticToolService.swift` preventing crashes on non-AXUIElement system objects.
  - **Calculator UTF-8 Boundary Parsing**: Refactored `CalcFormatter.swift` grouping to Unicode scalar/character boundaries, eliminating byte-slicing crashes and forced unwrap traps on non-ASCII numerals.
  - **CoreML Tensor Safety**: Guarded `[0]` index access on Parakeet encoder, token, and duration output tensors in `ParakeetRecognizer.swift`.
  - **Settings Search Catalog Synchronization**: Cleaned up 15 dead search targets across `SettingsSearchCatalog.swift`, `SettingsAnchor.swift`, `DictationSettingsView.swift`, `ExtendedFeaturesSettingsView.swift`, and `ChangelogSettingsView.swift`.
  - **Writing Tools Window Isolation**: Disabled Writing Tools popup affordances (`writingToolsBehavior = .none`) in `NoteEditorView.swift` preventing dismissed notes from repeatedly reviving.
  - **Calendar XPC Reconnect Throttling**: Fixed `lastReloadAt` timestamp recording prior to access guards in `CalendarStore.swift`, eliminating 60s XPC reconnect storms to `remindd` and `CalendarAgent`.
  - **System Actions Defaults Read/Write**: Migrated preference inspection to `CFPreferencesGetAppBooleanValue` in `SystemActionRunner.swift` for clean handling of unset preference keys.
  - **SQLite Non-Destructive Migrations**: Replaced raw `ALTER TABLE` statements in `QuicklinkStore.swift` with `PRAGMA table_info` checks, eliminating duplicate column errors on launch.
  - **Clipboard Deleted File Handling**: Handled `CocoaError.fileReadNoSuchFile` in `ClipboardTextExtractor.swift` to complete immediately with empty text rather than exhausting 3-stage retry loops.
  - **In-Memory Cache Boundaries**: Enforced a 50-entry FIFO eviction cap across `FlightTrackerService`, `WeatherService`, and `TravelTimeService`.

- **Raycast AI & Kerlig AI Modernization Suite**:
  - **Headless In-Place Selection Replacement**: Secondary return (`⌘↵`) on Quick Action launcher items executes with `forceInPlace: true`, reading the selection via Accessibility/synthesized ⌘C and immediately typing the AI result back into the target application with zero intermediate popups or diff confirmation windows.
  - **5-Tone Writing Matrix**: Added discrete, dedicated quick actions `.toneProfessional`, `.toneCasual`, `.toneDirect`, `.toneAcademic`, and `.toneDiplomatic` with custom prompt framing, localized resources, and distinct SF Symbols (`briefcase`, `face.smiling`, `arrow.forward.to.line`, `graduationcap`, `hand.raised.square`).
  - **Ambient Frontmost Application Context**: Automatically captures frontmost application name and bundle identifier (`[Active Application: <Name> (<BundleID>)]`) and injects it into quick action instructions, giving local and cloud LLMs immediate context awareness across code editors, messaging clients, and email apps.
  - **Ask AI About Screen Area**: Integrated `CommandID.askAIAboutScreenArea` (`text.viewfinder`) invoking zero-disk in-memory crosshair marquee screen OCR via `ScreenCaptureService.shared.capture(mode: .textOCR)` and auto-seeding recognized text directly into Quick AI composer.
  - **Dynamic Prompt Variables in Custom Actions**: Wired `SnippetTemplateEngine.expandPrompt` into `QuickActionRunner`, allowing custom prompts and quick actions to evaluate dynamic tokens (`{selection}`, `{clipboard}`, `{date}`, `{argument}`, `{query}`).
  - **Inline `@` Context & Tool Mentions**: Integrated `InlineMentionCompletionService` into `ComposerTextView` with AppKit native autocomplete for `@web`, `@selection`, `@clipboard`, `@screen`, `@window`, `@notes`, `@calendar`, and dynamic MCP server slugs. Automatically expands `@clipboard` and frontmost `@selection` inline, and routes `@web` queries directly through live search.

- **Release v1.1.5 / UI & UX Major Suite**:
  - **Quick Look File Preview Flicker Fix**: Resolved bug where pressing `⌘Y` on a file flickered and immediately closed. In `PaletteWindowController.windowDidResignKey`, opening the `QLPreviewPanel` synchronously posted a resign key notification while `NSApp.keyWindow` was still nil, causing the controller to immediately execute `QuickLookCoordinator.shared.close()` and `hidePalette`. Restored `QuickLookCoordinator.shared.isVisible` guard so the palette remains open behind Quick Look and keyboard navigation continues working.
  - **System Stats Settings Pane Section Separation**: Resolved empty ghost headers and missing Refresh Cadence picker caused by `@ViewBuilder` helper properties inside grouped forms and duplicate `.stats` anchor IDs. Inlined sections directly in `StatsSettingsView.swift`, defined discrete `.statsModules`, `.statsMenuBar`, and `.statsPerformance` anchors, and attached `.settingsScrollTarget(.stats)`.
  - **Menu Bar System Stats Visibility & 1-Second Telemetry Refresh**: Resolved invisible menu bar status items (`CPU`, `RAM`, `Disk`, `Battery`, `Network`) caused by missing snapshot projection and 0-width items. Decoupled `StatsMonitor` from UI via an `@MainActor` `onUpdate` closure, populated non-zero initial titles on status item creation, and applied monospaced digit typography (`NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)`) to eliminate horizontal width jitter. Changed default refresh cadence to 1.0 second (`statsRefreshInterval = 1.0`), delivering per-second network download/upload indicators in the menu bar. Throttled `/bin/ps` process spawning to only execute when `StatsDashboardView` is active (`isDashboardActive`), eliminating background CPU churn during routine 1-second menu bar ticks. Added dynamic observation tracking in `AppCore.swift` for all stats settings.
  - **Display Tweaks Auto-Apply & Persistence**: Resolved issue where display tweaks did not take effect on launch or after app updates until opening Settings -> Display Tweaks. Made `DisplayTweaksService.GammaSetData` `Codable`, persisted active gamma profile to `AppSettings.displayTweaksGammaSet`, and updated `AppCore.swift` and `ExtendedFeaturesSettingsView` to immediately apply `applyGammaSet` on app launch and toggle with fallback to `Gamma Control` reference profile. Added automatic resolved points synchronization and active display enumeration matching across wake/reconnect events.
  - **System Telemetry & Hardware Monitors**: Integrated Stats (exelban/stats architecture) directly into szcast with CPU, RAM, Disk, Battery, and Network monitors, rolling 30-sample quadratic Bezier sparkline graphs in `StatsDashboardView`, and individual togglable menu bar items with configurable cadences.
  - **Raycast-Parity Emoji & Symbols**: Replaced legacy emoji picker with full Raycast feature parity: semantic search, custom keywords stored in JSON via `⌘E`, inline autocomplete `:` in text fields, tone modifiers (`⌥⌘C`/`⌥⌘V`), and grid zooming (`⌘-`/`⌘+`/`⌘0`).
  - **Interactive Text Transformer**: Full 15+ format text conversions, live character/word/line/byte metrics, and Side-by-Side Diff Inspector (`⌘D`).
  - **Rich Developer Previews**: Clipboard code syntax highlighting with language detection and line numbers gutter; interactive Color Swatch card with one-click Hex, RGBA, HSL, and NSColor copy pills.
  - **Scoping & Action Ergonomics**: Launcher category scope filter chips (`All`, `Apps`, `Commands`, `Quicklinks`, `Snippets`, `Files`, `Actions`), AI code block direct injection ("Insert at Cursor" and "Run in Terminal"), and structured split Action Panel (`⌘K`).
  - **Tactile & Visual Feedback**: Dictation haptic cues on start/finish with an animated checkmark completion pulse; Settings search target accent glow pulse.
  - **Documentation & Web Modernization**: Streamlined `README.md` to a crisp 115-line architecture & feature guide; updated `site/index.html` to v1.1.5 with concise cards and deployed live to `szcast.vercel.app` (commits `97ec8bae`, `191bf48b`).

- **Release v1.1.4**:
  - Full codebase audit defect fixes: clipboard concealment markers across KeePassXC and Ente Auth to avoid history leaks, zero-error Push-to-Talk sub-100ms cancellation, safe unwrap bounds in Calendar/Insights/Ente, RunLoop timer modes in Clean Keyboard, safe HTTP & file size checks for S1 models, and scheme validation in URLSanitizer.
  - Settings Taxonomy Reorganization: System Settings & Actions moved to General; Core Features alphabetically ordered; Apple Shortcuts moved to Extended Features; Extended Features pane & sidebar dynamically sorted alphabetically by feature title with `.extendedFeatures` Hub pinned at the top.
  - Release binary built and deployed to `/Applications/szcast.app` reporting version 1.1.4.

- **Release v1.1.3**:
  - Indic Speech Suite & Direct Romanization: Integrated 4 dedicated Indic neural speech models across Dictation Settings:
    - `Whisper-Hindi2Hinglish-Apex` (`.whisperApex`): Direct acoustic transcription emitting conversational Latin Hinglish from Hindi speech.
    - `Indic-Transcribe-Flex` (`.indicFlex`): Direct acoustic Canary-1B model emitting Romanized Banglish from Bengali speech.
    - `SraVaani-1.0` (`.sravaani`): IISc/ARTPARK FastConformer-TDT flagship covering 65 Indian languages and dialects.
    - `SraVaani-0.5-live` (`.sravaaniLive`): Streaming low-latency cache-aware CTC model for real-time dictation preview.
  - S1-mini Cleanup Speed Invariant: Direct acoustic Romanization delivers native Latin text directly to the S1-mini polisher, bypassing multi-shot LLM transliteration and keeping S1-mini cleanup latency under 180ms with zero speed hit.
  - Native Bengali Language Support: Added Bengali (`bn`) into `DictationLanguage` picker.
  - Authenticated Hugging Face Token Support: Added `KeychainSecretStore.huggingFaceToken` integration in `DictationModelDownloader` to allow on-demand streaming of gated Indic checkpoints.

- **Release v1.1.2**:
  - HotKey & Dictation Responsiveness: Expanded modifier single-tap threshold from 250ms to 650ms (`ModifierKeyDetector.maxSingleHold`), eliminating dropped Fn keypresses during natural typing. Reduced Push-to-Talk activation delay from 250ms to 40ms on uncontended hold keys, preventing speech onset clipping.
  - Launcher Dismissal Across Modes: Updated `togglePalette()` and intercepted key down events in `PalettePanel` so pressing the global shortcut (`⌘ Space` / Command + Space) from any sub-screen (Clipboard, AI, Calculator, etc.) or focused search bar cleanly closes szcast immediately without event lag.
  - S1-mini Offline Architecture: Fully eliminated Ollama (`localhost:11434`) dependency in favor of dedicated local `llama-server` on port 51143. If the daemon is uninitialized, raw transcripts return in 0ms without network hang. Pointed model downloads directly to GitHub Release assets.
  - DisplayTweaks Sleep & Reconnect Resilience: Added `NSWorkspace.didWakeNotification` and `NSApplication.didChangeScreenParametersNotification` observers to automatically re-apply active gamma curves across sleep/wake cycles and display switches. Cleaned hardcoded download path dependencies.
  - Thread Safety & Resource Cleanup: Resolved Swift concurrency capture warnings in KeePassXC CLI execution, cleaned up unused references in Dictation coordinator, and added Mach port invalidation in Clean Keyboard.

- **Release v1.1.1**:
  - Settings Navigation Titlebar: Restored visible detail pane titles (AI, Display Tweaks, Clean Keyboard, Notes) beside the `< | >` navigation buttons on solid native dark chrome by eliminating manual platter frame shifting and anchoring `.navigationTitle` on the detail view.
  - Hardware Display Tweaks & Gamma Control: Rebuilt with a native 3-point inspector matching Gamma Control profiles: `[ Black | Middle | White ]` tabs with exact per-channel RGB sliders, 5-box checkerboard calibration targets, 256-step grayscale ramp, and RGB spectrum gradient strips matching `/Users/sz/Downloads/Untitled.gammaset`.
  - Layout & Margin Polish: Standardized 20pt native form insets across Dictation Insights, Changelog, and settings pickers, eliminating horizontal clipping.
  - In-App Changelog: Added dedicated Settings pane tracking release milestones, feature highlights, and architectural improvements directly inside the app.
  - Brand & Visual Polish: Integrated official dark vector squircle OpenAI and ChatGPT icon artwork, and removed white backgrounds from assets. Deployed to `/Applications/szcast.app` and published to GitHub.

- **Release v1.1.0**:
  - Dictation Insights Dashboard: Wispr Flow-style analytics driven 100% by local dictation metrics (`DictationHistoryStore`). Real-time WPM speed gauge with cadence percentile meter, S1-mini normalization corrections, total words dictated with book equivalence, application category distribution, and interactive 16-week speech cadence streak calendar.
  - Display Tweaks & Gamma Control: Direct GPU gamma table controls (`CGSetDisplayTransferByTable`) with 0.00–1.00 fine luminance controls for Black point, Middle gamma, and White point across RGB channels, plus quick presets including the Gamma Control reference profile for deep OLED-grade blacks without color banding.
  - Zero-Lag Dictation Daemons: Local S1-mini normalization engine (~460 MB Metal memory) and offline Parakeet v3 ASR engine pre-warmed and kept persistent via launch daemons, eliminating first-dictation cold start delays entirely.
  - Window UI & Navigation Polish: Enforced 840x600 minimum window layout constraints preventing sidebar truncation, 21.5pt AppKit toolbar platter navigation spacing, opaque navigation headers, and dual-mode vector SVG icons for ChatGPT, OpenAI, and Raycast snippets.
  - Documentation & Site: Transparent 8-bit alpha screenshot (`docs/screenshot.png`) with zero-halo drop shadow replacing the white-canvas JPEG in README, updated `site/index.html` copy for v1.1.0, and automated production deployment live on `szcast.vercel.app`.

- **Release v1.0.9-hotfix**:
  - Dictation Insights Dashboard: Wispr Flow-style analytics (WPM arc gauge with top percentile, S1-mini speech fixes and dictionary corrections, total words dictated with book equivalence, category distribution, 7x16 streak matrix).
  - Window UI & Chrome Overhaul: Eliminated Settings titlebar transparent bleed-through by setting `window.titlebarAppearsTransparent = false`, `isOpaque = true`, and native background color. Eliminated embossed title ghost shadow by hiding AppKit title visibility (`window.titleVisibility = .hidden`).
  - Window Resize Floor: Locked minimum window dimensions (840x600) via `AppWindow.setFrame` and `NSWindowDelegate.windowWillResize` to prevent windows being dragged or resized into narrow slivers.
  - Display Tweaks & Gamma Control: Direct linear transfer curve scaling ($y_{\text{scaled}} = \text{blackFloor} + (\text{whiteCeiling} - \text{blackFloor}) \times y$) replacing ineffective localized damping. Added exact "Gamma Control" preset (0.05 Black Point, 0.89 White Point Luminance).
  - Latency: Prewarmed speech recognition and daemon in background eliminating first dictation cold-start lag.
- **EnviousWispr Advanced Dictation Suite**: Deep integration of features ported from EnviousWispr into szcast native design:
  - Multi-root model discovery across `~/Library/Application Support/FluidAudio/Models` and `~/Library/Application Support/EnviousWispr/Models` (immediate detection of installed Nvidia Parakeet Ultra).
  - Superwhisper S1-mini offline AI polishing with Control Line prompt formatting (`Tone`, `Structure`, `Context`).
  - Model offloading settings with memory release intervals and `Never` offload option.
  - Spoken emoji converter (e.g. "thumbs up emoji" -> 👍), spoken punctuation, filler word cleaner (`um`, `uh`, `hmm`), and caret-aware smart text insertion.
  - Media playback controls during recording (`Continue`, `Lower`, `Mute`, `Pause` with Apple Music / Spotify AppleScript hooks).
  - Compact bottom screen glass recording pill with live audio level meter bars.
  - Push to Talk vs Toggle recording modes, Escape cancellation, and hotkeys for Add Selected Word, Paste Last Dictation, Copy Last Dictation.
  - Custom words dictionary with JSON import/export, 5 domain vocabulary packs (Tech 76, Medical 87, Legal 32, Brands 106, Names 90), self-learning dictionary detection, snippets, and searchable history.
- **Release 1.1.2** (`6256ef5`): Dynamic font scaling (12pt-22pt) across launcher rows, details, and AI chat typography; instant `<alias><Space>` command expansion; rich inline images in Notes via TextKit 2 with caret reveal; snippet default action configuration (Paste, Copy, Copy & Paste); snippet duplication (`⌘D`); snippet tags & folder grouping with horizontal filter chips; and AI web search discoverability in chat composer.
- **Focus Timer & Sensory Suite** (`45fb55e`): Full Pomodoro cycles (`.work`, `.shortBreak`, `.longBreak`), menu bar countdown item, `PaletteScreen` UI (`FocusTimerScreen`), non-blocking audio cues via `NSSound` (`SensoryAudioPlayer`), and full-screen CoreAnimation celebration (`ConfettiWindowController`).
- **Native Live Web Search with Citations** (`88fb7f9`): Provider wrapper (`WebSearchAIProvider`) supporting Tavily, Exa, and Jina with secure Keychain storage (`KeychainSecretStore.webSearchAPIKeys`). Live search event forwarding (`.searching`, `.searched`), inline context augmentation (`<web_search_results>`), and Markdown inline citation instructions linking to `ChatCitations` source badges. Configurable via AI Settings with key validation and model capability detection.
- **Quicklink Favicons & Store Updates** (`25506d9`): High-resolution favicon resolution and caching (`QuicklinkFaviconService`) for web quicklinks via Google Favicons CDN, DuckDuckGo, and direct `/favicon.ico` fallbacks. Stored in `Application Support/<bundle-id>/QuicklinkIcons/` and rendered in launcher search, Quicklinks list, preview pane, and settings rows via `EntryIcon.artwork`. Includes Quicklink editor inline "Fetch Favicon" action, action menu refresh/remove controls, auto-fetch on save setting (`quicklinkAutoFetchFavicons`), and one-click "Fetch All Favicons" settings utility. Fixed Raycast store extension bundle downloads (`extensions.raycast-releases.com` trust policy).
- **Superwhisper S1-mini Download & Raw ChatML Transport**: Replicated EnviousWispr S1-mini architecture: dedicated streaming model downloader (`DictationS1Downloader`) pulling `hf.co/superwhisper/s1-mini-gguf:Q4_K_M` via Ollama `/api/pull` with real-time percentage progress and lifecycle management in Settings (`DictationSettingsView`); ChatML raw transport (`DictationS1Polisher`) over Ollama `/api/generate` with `"raw": true` and explicitly closed empty `<think>\n\n</think>\n\n` assistant prefix, completely solving the unclosed `<think>` tag bug in the GGUF template that caused empty responses over `/api/chat` or `/v1/chat/completions`.
- **Superwhisper S1-mini Default GGUF & Embedded llama-server** (`d01db62a`): Standalone local `s1-mini-1.0.gguf` GGUF model integration as the primary/default speech normalization engine via embedded/managed `llama-server` (`Mach-O arm64` binary bundled in `Contents/Resources`). Automatically detects models across `~/Library/Application Support/EnviousWispr/Models/s1-mini/s1-mini-1.0.gguf` and `~/Library/Application Support/szcast/Models/s1-mini/`. Spawns `llama-server` on loopback `127.0.0.1:51143` with `--jinja --chat-template-kwargs '{"enable_thinking":false}'`, `-fa on --cache-type-k q8_0 --cache-type-v q8_0`, delivering 280ms inference without requiring external Ollama daemons. Includes configurable "Unload model after" idle release setting (`dictationS1IdleRelease` with `Never`, 1m, 2m, 5m, 10m default, 15m, 20m, 30m, 1h), dynamic process lifecycle management in `DictationLlamaServerManager`, termination hooks in `DictationCoordinator`, direct Hugging Face byte-streaming downloader fallback in `DictationS1Downloader`, and real-time path display in `DictationSettingsView`.
- **Default Fallbacks & Quicklinks Configuration** (`d069227`): Established default fallback order (`DefaultFallbacks.order`) and disabled set (`DefaultFallbacks.disabled`) matching user profile: enabled top 3 (Brave Search, ChatGPT Web Search, Brave Ask) with all others (commands and secondary search engines) disabled by default. Added `DefaultQuicklinks` seeding on first run.

- **Brand Icon & Extension Release Trust** (`0410ebc4`): Replaced brand icon everywhere with official dark squircle purple "SZ" artwork across macOS app bundle (`szcast.icns`, `AppIcon.appiconset`, `szcast.icon/Assets/thunder.svg`), `README.md`, `site/` (favicon.ico, favicon.png, apple-touch-icon, docs-images/icon.png). Resolved Raycast Store download and update errors by expanding `ExtensionInstallPolicy.trustedDownloadHosts` to include `extensions.raycast-releases.com`, `raycast-releases.com`, `backend.raycast.com`, `files.raycast.com`, and `assets.raycast.com`. Aligned dictation speech normalization prompts with EnviousWispr defaults (`DictationS1Settings.systemPrompt`, control line framing `[Styling: semi-formal] [Structure: prose] [Context: general]`, and disfluency copy-editing fallback for generic LLMs). Enabled S1 polish by default with background parallel model prewarming.
- **Vocabulary Packs & Post-Polish Canonicalization** (`9e75f9db`): Bundled all 5 domain vocabulary packs (`tech.json` 76, `medical.json` 87, `legal.json` 32, `brands.json` 106, `names.json` 90 with 1,537 phonetic aliases) directly into app bundle Resources (`Contents/Resources/Packs`) and Xcode build phase. Added `UserDefaults` persistence for user-toggled packs (`dictationEnabledVocabularyPacks`), straight/curly apostrophe tolerance in regex replacement patterns, and authoritative post-polish re-application in `DictationCoordinator` ensuring S1-mini speech normalization never reverts canonical casing. Updated README and site copy to streamline EnviousWispr mentions, crediting Saurav's native rebuild in the Contribution section.
- **Dictation Hotkey Presets, Icon Full-Bleed Scaling & Performance**:
  - Dictation Hotkey Presets (`DictationHotkeyPreset`): Native support for `Fn key` (`.globe`), `Option + Space` (`⌥Space`), `Control + Space` (`⌃Space`), and custom hotkey recorder with conflict detection and quick 1-click preset selector buttons in Settings.
  - Brand Icon Full-Bleed Scaling: Scaled and cleanly masked the dark squircle artwork with smooth continuous rounded curvature, eliminating the artificial checkerboard background. Switched `ASSETCATALOG_COMPILER_APPICON_NAME` from `szcast` (`.icon` with automatic white plate) to `AppIcon` (`.appiconset`), ensuring macOS renders only the dark squircle with violet SZ without any white container or border.
  - Transcribing & Polish Acceleration: Enabled `configuration.allowLowPrecisionAccumulationOnGPU = true` on CoreML `DictationTensor.load`; set `.all` compute units for Parakeet encoder, decoder, and joint models for unified Apple Neural Engine and Metal GPU execution. Added `-ngl 99` GPU offload flag to `llama-server` in `DictationLlamaServerManager`, used template-level thinking bypass `--jinja --chat-template-kwargs '{"enable_thinking":false}'`, and capped S1-mini `max_tokens` to transcript length to eliminate token generation lag.
  - Dictation Floating Pill UI Fix: Fixed waveform overflow in `DictationPanel.swift` by unifying processing wave to 10 matching capsules within a 55px container with traveling accent wave animation. Added `.fixedSize` to prevent status text truncation and widened pill NSPanel to 210px with zero overlap.
  - macOS Version Cleanup: Removed deprecated `/Applications/Tinycast.app` and old DerivedData debug builds; cleanly installed and registered the latest signed `szcast.app` at `/Applications/szcast.app`.

- **Release 1.0.6**:
  - Sequential Releases Normalization: Re-sequenced GitHub releases into clean chronological semantic versions: `v1.0.0`, `v1.0.1`, `v1.0.2`, `v1.0.3` (defaults on & chords), `v1.0.4` (store-only extensions & background prompt), `v1.0.5` (font scaling, rich note images, alias space, snippets tags), and `v1.0.6` (latest). Scrapped all binaries from older releases so only `v1.0.6` holds `.dmg` and `.zip` distribution bundles.
  - Quick Look File Preview (`⌘Y`): Built native macOS `QLPreviewPanel` coordinator in `QuickLookCoordinator.swift` integrated with `FileSearchScreen` and `LauncherScreen`. Fixed instant-dismiss bug by preventing `PaletteWindowController` from resigning key when `QLPreviewPanel` takes focus; sets floating panel level above palette, restores focus on dismiss, and forwards Up/Down arrow navigation from preview to search results.
  - EnviousWispr Live Speech Dictation Preview & Settings: Dedicated "Live Preview" tab in Dictation Settings matching EnviousWispr design ("Show words while you speak", green Ready badge, Automatic language selector, and Universal engine status). Real-time partial transcript preview rendered live inside floating dictation pill with on/off toggle (`dictationLivePreviewEnabled`).
  - Pasting Mode Parity & Instant Paste: Completely resolved live chunk streaming bug by inhibiting document chunk injection during recording when `.allAtOnce` is selected. Guaranteed instant single-shot clipboard paste via `Paster.pasteString` on completion. Added full 3-mode pasting flexibility (`.allAtOnce` instant, `.wordByWord` 35ms stream, `.characterByCharacter` 15ms typewriter).
  - Robust Live Speech Recognition Engine: Fixed locale resolution bug where uninstalled language variants (like `en-US` when only `en_IN` is installed) caused SpeechAnalyzer audio format failure; added intelligent fallback matching installed language codes, plus universal `SFSpeechRecognizer` fallback, delivering real-time character-by-character / word-by-word transcription preview in the floating pill without document typing.
  - Compact 0.6x Recording Pill: Trimmed floating recording pill width down to 0.6x (from 320pt to 192pt width, 36pt height) with 6 compact waveform bars and live preview text.
  - S1-mini Cleanup Latency Tuning: Brought speech normalization latency to parity with EnviousWispr (~200ms). Eliminated blocking HTTP `/health` roundtrips on alive llama-server instances, added active KV-cache prewarming on dictation start, set greedy argmax decode (`temperature: 0.0`), connection keep-alive, and dynamic tight `max_tokens`.
  - Search Bar Layout & Accessory Spacing: Added dedicated spacing gutter (`metrics.spacing.sm`) and trailing breathing room (+8pt) in `RootPaletteView.swift` header bar between search field and command argument accessories (e.g. Brew argument slots), preventing query text and accessory collision.
  - Configurable Pasting Modes: Added `dictationPasteMode` (`.instant` vs `.wordByWord`), allowing transcripts to be pasted all at once or word-by-word with 35ms cadence.
  - Auto-Capitalization & Leading Space Elimination: Capitalized initial letters across direct transcripts and S1 polish outputs; stripped unwanted leading whitespace before the first character.
  - Persistent Hot Models: Set `dictationIdleRelease` and `dictationS1IdleRelease` to `.never` by default so models remain hot in memory.
  - Full-Bleed Continuous Superellipse Brand Icon: Inset mathematical superellipse crop (`a=794, b=786, p=4.2`) eliminating 100% of corner teeth, checkerboard bleeding, and bottom line artifacts across all 10 macOS resolutions, AppIcon.appiconset, szcast.icns, and web assets.
  - Dictation Hotkey Presets: Native 1-click presets for `Fn key`, `Option+Space`, `Control+Space`, and custom shortcut recorder.

- **Release 1.0.7**:
  - Single-Shot Paste Pipeline: Completely disabled live document chunk typing during speech; audio is strictly routed to the floating pill HUD for live visual feedback.
  - S1-mini Post-Clean Delivery: The full audio recording is transcribed, normalized and cleaned via local S1-mini model, and pasted in a single shot via ⌘V (`Paster.pasteString`) only after cleanup completes.
  - Streamlined Pasting Mode: Standardized on "All at once after transcribing and cleaning"; removed legacy typewriter and word-by-word streaming modes and the "Insert while recording" setting.

- **Release 1.0.9-hotfix**:
  - Dictation Insights Dashboard: Wispr Flow-style analytics inside Dictation Settings (`.insights` tab) and launcher command (`Dictation Insights`). WPM gauge, AI speech normalization fixes breakdown, Total Words milestone with desktop/mobile segmented ratio, desktop app distribution, and 7x16 streak heatmap.
  - S1-mini & Parakeet Always-On: Models prewarmed and persistent on launch/reopen with zero unload latency.
  - Settings Visual Standardization: Ente Auth, KeePassXC, DuckDuckGo Mail, Finder File Actions, Display Tweaks, and Clean Keyboard aligned to macOS native grouped Form style.
  - Custom Snippet Favicons: Domain favicons, custom local icon paths, and SF Symbols for snippets.
  - Raycast-Style Icons: Vibrant squircle icon badges across launcher search, commands, and settings.
  - Concurrency Safety: Concurrently drained stdout/stderr in `KeePassXCService` and `FinderFileActionsService` to eliminate child process pipe deadlocks; strictly verified CGEventTap registration in `CleanKeyboardService`.

- **Upstream Ports & Defensive Hardening**:
  - Upstream Ports: Ported macOS 26 compact bar glass shadow fix (`5370cf64`), quicklink hotkey toggle dismissal (`142e3a06`), Yandex Telemost meeting link detection (`d9414598`), sandboxed clipboard image copy handling (`d153da15`), Notes ICU word count (`bc5cd0cc`), regional grouping widths for calculator supporting lakhs/crores (`e61ba33c`), and snippet selective pinning (`fd3c32fc` with `pinned: true` frontmatter, `⌘.` shortcut, and browser pinned section headers).
  - Stability & Accessibility Fixes: Eliminated fatal favicon force-unwrap crash on templated/non-ASCII URLs (`QuicklinkFaviconService`), resolved recursive AppKit accessibility stack overflow crash on attached document chips (`ChatTranscriptView`), and fixed Pomodoro focus timer sleep drift with wall-clock end-date calculation (`FocusTimerCoordinator`).
  - Privacy & Security Hardening: Hardened clipboard storage permissions (`0700` directory, `0600` db file), expanded sensitive pasteboard markers (`de.petermaurer.TransientPasteboardType`, `org.nspasteboard.AutoGeneratedType`, `com.agilebits.onepassword`), sanitized Jina AI query URL path encoding, and added automated temporary file cleanup for model downloads.
  - Long-Form Continuous Dictation (10–20 Mins): Expanded audio capture buffer from 5 to 20 minutes (`DictationWire.maximumSamples`), increased local S1-mini context window from 2k to 8k tokens (`-c 8192`), and made token cap and request timeout scale dynamically with speech word count while preserving ~200ms latency on short dictation.

- **Raycast Parity Calculator & Live Intelligence Suite** (`138ba3dd`):
  - Pure Offline Engine: Chemistry molar mass evaluation (`molar mass of C6H12O6`), running pace conversions and duration solving (`5:00 min/km in km/h`, `13:24 min/mile in mph`, `5:00 min/km for 10 km`), physical constants (`speed of light`), specialized units (`rankine`, `chain`, `link`, `nibble`, `legal cup`, `dBm`), stepped fraction rounding (`to nearest quarter/eighth/hundredth`), and expanded color formats (`NSColor`, `UIColor`, `hwb`, `lab`).
  - In-Place Weather Card: Keyless Open-Meteo REST service rendering live condition, high/low, temperature, and 4-hour forecast strip directly in launcher with unit toggle (`⌘U`).
  - In-Place Travel Card: Native macOS MapKit (`MKDirections` + `CLGeocoder`) multi-modal route estimator rendering driving, transit, and walking durations side-by-side with fastest route highlighted and one-key copy (`↵`).
  - In-Place Flight Tracker Card: Keyless live FlightRadar24 tracker with flight designators (e.g. `flight BA1444`, `AI101`), origin/destination IATA tags, departure/arrival local times, and status badges.
  - Complete Launcher Integration: Dispatched via `LauncherList.LeadCard` with seamless in-place UI (no external browser or Maps popups required). Test harness expanded to 121 suites (all pass).

- **Compact Bar Shadow & S1-Mini Resolution** (`7ae6b6b3`):
  - Compact Bar Shadow Crescent Fix: Eliminated the double dark shadow crescent clipping artifact under the search pill and circular shortcut buttons on macOS 27 by setting `Theme.glassCastsShadow = true`, restoring the crisp silhouette mask over the glass container, and triggering settled window shadow invalidation.
  - S1-Mini Model Discovery & Fast Download: Discovered pre-existing 462MB `s1-mini-1.0.gguf` in EnviousWispr directory and synced it to `~/Library/Application Support/szcast/Models/s1-mini/s1-mini-1.0.gguf`. Added EnviousWispr candidate paths to `DictationLlamaServerManager` and `DictationModelStore`. Replaced slow byte-by-byte download sequence with native `URLSession.shared.download`.

- **OCR, Data Transformers, Hardware Switcher & Calendar HUD** (`bdd9d535`):
  - Native Screen Text OCR & QR Scanner: Interactive crosshair marquee selection directly to in-memory pasteboard buffer via `/usr/sbin/screencapture -i -c` with zero filesystem footprint; Vision `VNRecognizeTextRequest` and `VNDetectBarcodesRequest` detection; HUD confirmation and clipboard delivery; `⌥⇧2` default global hotkey and `Capture Screen Text` / `Scan QR Code` launcher commands.
  - Developer & Data Transformers: Pure offline evaluation in root search for cryptographic hashes (`sha256`, `sha1`, `sha512`, `md5`), base64 encode/decode, urlencode/urldecode, JWT token inspection with human-readable expiration, UUID v4 generator, and Cicero Lorem Ipsum word/paragraph generator.
  - Audio & Display Hardware Switcher: CoreAudio native device discovery, default input/output setting, and cycling; dynamic `DisplayServicesSetBrightness` linking + Lunar CLI external monitor fallback; 6 new system actions.
  - Menu Bar Meeting Countdown HUD: Default `calendarMenuBarDisplay` set to `.meetingTitle` (`[Title] • in 12m`) with 1-click meeting join and action card integration.
  - Test Harness Suite: Expanded to 123 suites (`hardware-test`, `screen-capture-test` added); all 123 harnesses pass in 179s.

- **URL Sanitizer & Tracking Parameter Stripper** (`35ec1bc1`):
  - Pure offline URL cleaner (`URLSanitizer.swift`) stripping marketing and telemetry query parameters (`utm_*`, `fbclid`, `gclid`, `si`, `twclid`, `msclkid`, `mc_eid`, `tag`, `ref_`, `pd_rd_*`, `pf_rd_*`, etc.) while retaining authentic routing parameters.
  - Recursive unwrap of nested redirects for Google (`/url?q=`), Slack (`slack-redir.net/link?url=`), and Outlook SafeLinks.
  - Root search data transformer (`clean <url>`, `cleanurl <url>`, `sanitize <url>`, `untrack <url>`).
  - System action & launcher command: `Clean URL in Clipboard` (`CommandID.cleanClipboardURL` / `SystemAction.cleanClipboardURL`) with descriptive HUD message and parameter removal count.
  - Clipboard history integration: Context menu item "Copy Clean URL" (`⇧⌘C`) on any text clipboard entry containing links.
  - Test suite expanded to 124 suites (`url-sanitizer-test` added); all 124 harnesses pass in 169s.

- **Release 1.0.8**:
  - URL Sanitizer & Tracking Stripper: Native zero-dependency engine (`URLSanitizer.swift`) removing marketing and telemetry parameters (`utm_*`, `fbclid`, `gclid`, `si`, `twclid`, `msclkid`, `mc_eid`, `tag`, `ref_`, `pd_rd_*`, `pf_rd_*`) and recursively unwrapping Google, Slack, and Outlook SafeLinks redirects. Integrated into search (`clean <url>`), clipboard history (`⇧⌘C`), and launcher commands (`Clean URL in Clipboard`).
  - Native Screen OCR & QR Scanner: Direct-to-memory screen marquee capture (`ScreenCaptureService.swift`, `⌥⇧2`) via Vision framework with zero disk footprint.
  - Developer & Data Transformers: Offline hashing (`sha256`, `md5`), base64/urlencode, JWT inspector, UUID v4 generator, and Lorem Ipsum word generator.
  - Audio & Display Hardware Switcher: CoreAudio peripheral cycling and display brightness controls hooked into System Actions.
  - Menu Bar Meeting Countdown HUD: Real-time upcoming meeting awareness and one-click join.
  - In-Place Live Intelligence Cards: Open-Meteo Weather, MapKit Travel Route Estimator, and FlightRadar24 flight tracker cards in root launcher.
  - Version bump to 1.0.8, signed release DMG & ZIP distribution assets packaged, 124 test suites pass.

- **Ente Auth, Finder File Actions & Display Management**:
  - Built-in Ente Auth 2FA Authenticator: RFC 6238 / RFC 4226 TOTP engine with CommonCrypto HMAC (SHA1, SHA256, SHA512), Base32 decoder, live countdown ticker, formatted token (`123 456`), next code preview, auto-discovery of `ente_auth.txt`, `0600` owner-only JSON persistence, and dedicated global hotkey `Hyper + T` (`⌃⌥⇧⌘T`) copying raw TOTP digits directly on Return.
  - Built-in Finder File Actions: Frontmost Finder selection query via AppleScript, atomic move and copy with collision-safe duplicate renaming (`file 2.txt`), pinned destinations (`~/Downloads`, `~/Documents`, `~/Desktop`, `~/Pictures`, `~/AIOS`), LRU recent folders, Spotlight live search, and dedicated global hotkey `Hyper + M` (`⌃⌥⇧⌘M`) specifically triggering "Move File to Folder".
  - Display Tweaks & FreeDisplay Management: Hardware gamma transfer table calculations (`CGSetDisplayTransferByTable`) with RGB channel gains, deep shadow/black floor lifting, highlight compression, whites, brightness, and contrast curves in Settings (`DisplayTweaksSettingsView`); display mirroring toggle system action (`SystemAction.toggleDisplayMirroring`) via CoreGraphics display configuration APIs.
  - Groq Speech Transcription & Polishing: Groq API integration (`GroqAudioService` with whisper-large-v3 / whisper-large-v3-turbo, `GroqPolishService` with llama-3.3-70b-versatile / llama-3.1-8b-instant), provider picker in Dictation Settings, Keychain API key storage, and direct signup link.
  - Attribution & Acknowledgements: Updated `NOTICE.md` and `AboutView.swift` crediting FreeDisplay (huberdf), gamma-control (Qiueyed), ente-auth (chkpwd / Ente), and finder-file-actions (pa1ar).
  - Test Suite: Expanded from 124 to 127 test harnesses (`display-tweaks-test`, `ente-auth-test`, `finder-file-actions-test`); all 127 harnesses pass in 206s.

- **DuckDuckGo Email, Clean Keyboard, KeePassXC & Simplified Settings**:
  - Settings Categorization Overhaul: Re-categorized settings into 6 balanced domains (`general`, `launcher`, `productivity`, `windowAndDisplay`, `aiAndVoice`, `systemAndAbout`) across `SettingsTab.swift` while preserving all existing deeplink slugs, search catalog anchors, and history.
  - Built-in DuckDuckGo Email Protection: REST integration calling `quack.duckduckgo.com/api/email/addresses` with Keychain Bearer token storage, `DuckDuckGoEmailScreen` palette setup, and global hotkey `Hyper + D` (`⌃⌥⇧⌘D`) generating and copying `@duck.com` addresses with native HUD confirmation.
  - Built-in Clean Keyboard Mode: Physical keyboard cleaning lock using `CGEventTap` keystroke filtering, floating dark-glass countdown HUD (`CleanKeyboardWindowController`), dual escape-hold (3s) and `Control + U` safe unlocks, time extension (`+30s`), and system action `.cleanKeyboard`.
  - Built-in KeePassXC Password Manager: CLI integration wrapping `/opt/homebrew/bin/keepassxc-cli` with database path and master password in Keychain. Features persistent account window resumption across launcher toggles: copying hides the palette, and re-summoning szcast (`⌥Space`) immediately re-opens the exact same account view without re-searching. Dedicated in-view keyboard shortcuts: `⌘C` (copy password), `⌘T` (copy TOTP), `⌘B` (copy username), `⌘U` (open URL), and `Esc` (return to list).
  - Third-Party Acknowledgements: Updated `NOTICE.md`, `README.md`, and `site/index.html` acknowledging FreeDisplay, gamma-control, duckduckgo-email, clean-keyboard, and keepassxc.
  - Test Suite: Expanded to 130 test harnesses (`duckduckgo-email-test`, `clean-keyboard-test`, `keepassxc-test` added; `system-action-test` updated); all 130 harnesses pass in 173s. Full clean debug & release builds verified.

- **S1-Mini Persistent Local Daemon & Latency Optimization**:
  - Persistent Local Daemon: Converted `DictationLlamaServerManager` into a persistent daemon launched at app startup (`startDaemon`), maintaining S1-mini hot in memory with 0ms launch overhead across dictations.
  - Single-Slot Metal Execution: Configured `-np 1` (eliminating the multi-slot allocation delay that previously caused 10s stalls on Metal), `-c 1024`, `-b 512`, `-ub 512`, `-fa on`, `--cache-type-k q8_0`, `--cache-type-v q8_0`, `--cache-prompt`, `--spec-type ngram-simple`, and `--reasoning off`.
  - Stalling Prevention & Fast Fallback: Extended health-check budget to 15s to avoid premature kills on heavy I/O, added clean shutdown hooks on app termination (`prepareForTermination` and `stopDictationForTermination`), and guarded against phantom localhost Ollama fallback stalls when embedded GGUF is available.
  - Active Settings Status: Updated `DictationSettingsView` to reflect live single-slot Metal daemon status and memory footprint.
  - Test Suite & Packaging: 130 test harnesses pass; Debug and signed Release builds verified; local `/Applications/szcast.app` deployed.

- **Release 1.0.9**:
  - Centralized Extension Aliases: Added `ExtensionCommandsSettingsSection` in `Settings -> Commands` querying all `.extensionCommand` entries with unified search, instant `AliasField`, `ShortcutRecorder`, and launcher visibility toggle.
  - Submenu & Extension List Numeric Shortcuts: Extended numeric chords (`⌘1`..`⌘9`, `⌘0`) in `PaletteWindowController` and default `PaletteScreen.perform` across all list modes and submenus with dynamic `⌘1`..`⌘9` keycap badges in `ExtensionItemRow` when `Command` is held.
  - Superwhisper-Style File Transcription: Added "Transcribe Audio/Video File…" in `MenuBarItem.swift` via `NSOpenPanel`, decoding media to 16kHz float PCM via `DictationFileTranscriber` (`AVAssetReader`), transcribing via Parakeet/Groq, formatting via local S1-mini daemon, and copying to clipboard with HUD confirmation.
  - Indic Phonetic Romanization: Implemented Bengali (Banglish) and Hindi (Hinglish) transliteration pickers in Dictation Settings (Option 1 S1-mini prompt vs Option 2 Avro/Hinglish deterministic converters).
  - Lunar Display Pill Sliders: Reworked `LunarPillSlider` in `DisplayTweaksSettingsView` with tinted tracks and traveling pill thumb containing active 0..100 value.
  - Settings Scaling Fix: Enforced strict 840x600 minimum bounds in `AppWindowController` and `SettingsRootView` `WindowReader`.
  - Raycast Vibrant Squircle Icon System: Implemented `RaycastIconTheme.swift` mapping system and custom symbols to vibrant, theme-colored squircle backgrounds with crisp white glyphs across launcher results, submenus, settings sidebar (`SettingsSidebarView`), and action panels, eliminating dull monochrome grey tiles.
  - Custom Snippet Favicons & Icons: Added `icon: String?` to `Snippet.swift`, YAML frontmatter serialization in `SnippetMarkdownSerializer`, live squircle preview in `SnippetEditorView`, and automated web favicon resolution/caching in `SnippetFaviconService.swift` supporting website domains, URLs, and SF symbols in launcher results and library lists.
  - Persistent S1-mini & Parakeet Launch on Any MacBook: Ensured `dictationModels.ensurePrewarmed()` and `DictationLlamaServerManager.shared.startDaemon()` run unconditionally on launch and reopen, with automated background downloading of `s1-mini-1.0.gguf` (mirrors) and Parakeet models if missing on a fresh machine, keeping both models alive in memory with Metal GPU acceleration.
  - Native Grouped Settings Alignment: Converted Clean Keyboard, Display Tweaks, Ente Auth, KeePassXC, DuckDuckGo Email, and Finder File Actions to `.formStyle(.grouped)` with native two-line labeled pickers and card sections.
  - Updated Documentation Screenshot: Replaced `docs/screenshot.jpg` with the official dark command palette screenshot.
  - Release Packaging & Distribution: Version bumped to 1.0.9; signed Release DMG (`build/szcast-1.0.9.dmg`) and ZIP (`build/szcast-1.0.9.zip`) packaged and deployed to `/Applications/szcast.app`.

- **Release 1.1.0**:
  - Dictation Insights Dashboard: Wispr Flow-style analytics inside Dictation Settings (`.insights` tab) with 100% real user metrics derived dynamically from `DictationHistoryStore.items` (real WPM cadence, S1-mini AI normalization fix count and words corrected, cumulative word milestone with equivalent speech page estimation, audio duration progress bar, desktop application breakdown without truncation, and 16-week contribution streak calendar).
  - Settings Navigation Platter Offset: Enforced 21.5pt gap between vertical sidebar divider line and `< | >` navigation buttons via AppKit `NSToolbarPlatterView` frame observer.
  - Display Tweaks & Gamma Control: Hardware gamma transfer curve scaling with exact Gamma Control preset (0.05 Black Point, 0.89 White Point Luminance).
  - Version bump to 1.1.0, signed Release DMG (`build/szcast-1.1.0.dmg`) and ZIP (`build/szcast-1.1.0.zip`) packaged and deployed to `/Applications/szcast.app`.

- **Release 1.1.2**:
  - Universal Launcher Dismissal: Intercepted `Command + Space` in `PalettePanel.sendEvent` so pressing the launcher hotkey from any sub-screen (Clipboard, AI, Calculator, Search bar) cleanly dismisses szcast without delay.
  - Documentation Screenshot: Replaced `docs/screenshot.png` and `docs/screenshot.jpg` with the official dark command palette capture.

- **Release 1.1.3**:
  - Indic Speech Suite: Integrated 4 dedicated Indic models into Dictation:
    - `Whisper-Hindi2Hinglish-Apex`: Direct speech-to-Hinglish acoustic decoding under Hindi Romanization.
    - `indic-transcribe-flex`: Direct speech-to-Banglish acoustic decoding under Bengali Romanization.
    - `SraVaani-1.0`: 65-language flagship Indic FastConformer-TDT ASR.
    - `SraVaani-0.5-live`: Streaming cache-aware CTC ASR.
  - Latency Invariant Preserved: Because Whisper-Apex and Indic-Flex output Latin characters acoustically, S1-mini skips phonetic transliteration and only executes punctuation/casing cleanup, maintaining ~120–180ms response time.
  - Hugging Face Token Auth: Added `KeychainSecretStore.huggingFaceToken` support for gated model repositories.
  - Release Packaging: Signed `build/szcast-1.1.3.dmg` and `build/szcast-1.1.3.zip` deployed to `/Applications/szcast.app` and published to GitHub.

- **Launcher Command Seeding Fix** (`EntryNaming.queryRemainder`):
  - The defect: activating any command row handed the *whole* typed text to `LauncherCoordinator.runCommand` as its `searchQuery`, and every consumer reads that parameter as a residual filter term (`togglePalette(seeding:)`, `fileSearchCoordinator.show(query:)`, `menuSearchCoordinator.show(query:)`, `windowSwitchCoordinator.show(query:)`, `quickAICoordinator.show(draft:)`). So typing `search menu bar items` and pressing Return opened menu search *filtered to that phrase* — zero results in every command's screen, not just Menu Search.
  - The fix: `EntryNaming.queryRemainder(_:names:)` strips the row's own leading name (title, `alternateTitles`, stored alias) as **whole words**, longest name first. `launch` calls it once before both `runCommand` dispatches. Nil = no name prefixed (query stands); `""` = the query *was* the name, seeding nothing — distinct from nil at `togglePalette`, where nil would close an open screen instead of opening it blank.
  - Verified live on the Debug build by AX-driving the real palette: pre-fix the menu-search field held `search menu bar items`; post-fix it opens empty. Harness `launcher-query-remainder-test` covers exact, case-folded, partial-word, longer-word, whitespace, multi-word-name and alias cases. 131/131 harnesses pass.

- **Core vs Extended Features Architecture & Settings Simplification**:
  - Restructured Settings taxonomy into 4 clean sections: `.general`, `.coreFeatures`, `.extendedFeatures`, and `.systemAndAbout`.
  - General: General, Permissions, Navigation, System Settings, System Actions.
  - Core Features (sorted alphabetically by name): AI, Applications, Clipboard, Commands & HotKeys, Dictation, Emoji & Symbols, Fallbacks, File Search, Notes, Quick Actions, Quicklinks, Snippets, Window Management.
  - Extended Features (7 modular capabilities): Ente Auth, KeePassXC, DuckDuckGo Mail, Display Tweaks, Calendar, Clean Keyboard, Apple Shortcuts.
  - Managed via dedicated `ExtendedFeaturesSettingsView` with master toggles and quick navigation to feature panes.
  - Smart one-time migration (`AppSettings.runExtendedFeaturesMigration` via `extendedFeaturesV1Migrated` key): fresh installs default extended features to OFF; existing users with configured accounts/credentials/authorizations automatically keep them ON. Future toggling by the user is preserved and never reset on app updates. Dynamic sidebar filtering conditionally displays active tabs.
  - Deep-link and command gating: opening an un-enabled extended feature screen or hotkey is cleanly inhibited.

- **Removal of Liquid Glass UI**:
  - Completely excised translucency controls, slider settings, and `VisualEffectBlur` from `RootPaletteView` and `Theme.swift` in favor of solid, crisp native chrome.

- **Removal of Finder File Actions**:
  - Completely removed `szcast/Features/FinderFileActions/`, its models, service, settings, and UI in favor of external szcast extension.

- **Hardening Suite (Defects 1–9 Fixed)**:
  - 1. Prefix Argument Matching: Added prefix argument matching in `LauncherOrder.swift` and `SearchRelevance.swift` (`isPrefixWithArgument`), retaining commands at high rank when followed by search arguments (`search files report`) rather than dropping them.
  - 2. Quick Look Focus Trap: In `PaletteWindowController.swift`, scoped key retention strictly to when `NSApp.keyWindow is QLPreviewPanel`, automatically closing Quick Look and hiding the palette when clicking into other applications.
  - 3 & 4. KeePassXC Enhancements: Enabled `hasKeyfile` unlocking without requiring a master password for keyfile-only vaults (`--no-password`), added CLI background search (`searchCli(term:)`) to enable searching across usernames, URLs, and notes, and backfilled usernames into memory on detail load.
  - 5. Ente Auth URI Import: Sanitized unencoded spaces and brackets in `EnteAuthStore.parseOTPAuthURI` prior to `URLComponents` initialization, allowing seamless import of 2FA account exports with unencoded label spaces.
  - 6. Clean Keyboard Teardown: Registered `CleanKeyboardService.shared.stopCleaning()` inside `AppCore.prepareForTermination()` to guarantee CGEventTap Mach port invalidation and removal from RunLoop on app quit.
  - 7. Display Tweaks Multi-Monitor Calibration: Updated `applyGammaSet` and `applyTransferTables` in `DisplayTweaksService.swift` to iterate through all connected displays (`enumerateDisplays().map(\.id)`) when `displayID` is nil/0.
  - 8. Notes Inline Text Preservation: Constrained block image decoration in `NoteMarkdownStyler.swift` strictly to standalone image lines (`lineText == tagText`), preserving normal visibility for text preceding or succeeding inline images.
  - 9. AI Web Search Error Transparency: Replaced silent `[]` fallback with explicit `WebSearchError` (`.unauthorized`, `.rateLimited`, `.httpError`) in `WebSearchService.swift`, cleanly surfacing API key expiry and rate-limiting issues in AI chat streams.

- **Full Codebase Audit & Hardening**:
  - 1. Concealed Pasteboard for Credentials & TOTP: Added `Paster.copyConcealedText(_:)` and `KeePassXCService.copyConcealed(_:)` marking sensitive pasteboard types (`org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType`, `de.petermaurer.TransientPasteboardType`, `com.apple.is-sensitive`). Passwords and TOTP codes copied from KeePassXC and Ente Auth are now strictly omitted from szcast's unencrypted SQLite clipboard history and third-party clipboard managers.
  - 2. Dictation Push-to-Talk Sub-100ms False Alarm: Suppressed `.danger` "No speech was recorded" banner on sub-1,600 sample releases in Push-to-Talk mode (`DictationCoordinator.swift`), cancelling short taps cleanly and silently.
  - 3. Ente Auth UI Dynamic Path & Safe Binding: Reflected the true candidate parent directory (`Downloads`, `Documents`, or `.ente`) in `EnteAuthScreen.swift` and eliminated force unwrap on `foundExport`.
  - 4. URLSanitizer Redirect Target Scheme Validation: Enforced `http://` or `https://` prefix check on unwrapped query redirect targets in `URLSanitizer.unwrapRedirect`, blocking relative paths and unsafe schemes from bypassing URL parsing.
  - 5. Calendar Meeting URL Safe Parsing: Replaced force unwrapped URL construction in `CalendarCoordinator.entry(for:)` with safe optional fallback.
  - 6. Dictation Insights App Breakdown Safe Binding: Replaced force unwrap `item.appName!` in `DictationInsightsDashboardView.swift` with safe optional unwrapping.
  - 7. Settings Sidebar Search Isolation: Filtered search entries in `SettingsSidebarView` with `isTabVisible($0.tab)`, preventing disabled extended features from leaking into settings search results.
  - 8. Clean Keyboard RunLoop Tracking Resilience: Scheduled `countdownTimer` and `escapeHoldTimer` in `RunLoop.main` `.common` modes, ensuring timer ticks and 3-second escape hold unlocks are not stalled during menu or mouse tracking.
  - 9. Dictation S1 Download Integrity & Mirror Fallback: Added HTTP status code check `(200..<300)` and minimum file size check (>10MB) to `DictationS1Downloader.didFinishDownloadingTo`, preventing 404 HTML error pages from being saved as GGUF models and enabling automatic mirror fallback. Added file size verification to `DictationLlamaServerManager.resolveGGUFModel()`.
  - 10. Extended Feature Gating Cleanliness: Removed duplicate Display Tweaks section from `GeneralSettingsView.swift`, routed immediate transfer curve application on enable in `ExtendedFeaturesSettingsView.swift`, and guarded `SystemAction.cleanKeyboard` execution against disabled settings.

- **Snippet Body Substring Search & Inline Previews (Non-Fuzzy)**:
  - Deep snippet body matching: Implemented exact substring matching across snippet body text with word-boundary weight boosts and line excerpt formatting, strictly rejecting loose non-contiguous fuzzy subsequence matching.
  - Multi-term query scoring (`scoreMultiTerm`): Every query term must match as an exact substring across snippet name, keyword, folder, or content body.
  - Excerpt preview: Added `SnippetSearch.excerpt(for:)` displaying clean, whitespace-collapsed snippet body previews inside `SnippetRow` in `SnippetsListView.swift`.
  - Root launcher indexing: Retained `AppIndex.snippetKeywords` indexing depth (30 lines / 200 words) for deep launcher snippet matching.
  - Test harness: Updated `Tests/snippets-test.swift` verifying that fuzzy subsequence queries (e.g. `bnn`, `shrdng`, `dtpln`) yield zero results while exact substrings in body and title match cleanly (134/134 test harnesses pass).
  - Deployed: Signed release binary built and installed to `/Applications/szcast.app`.

- **Changelog & Build Version Synchronization (v1.1.6)**:
  - Synchronized `MARKETING_VERSION = 1.1.6` in `szcast.xcodeproj/project.pbxproj` across Debug and Release configurations.
  - Dynamically bound `currentAppVersion` via `Bundle.main.infoDictionary["CFBundleShortVersionString"]` in `ChangelogSettingsView.swift` and `AboutView.swift`.
  - Added full release catalog for `v1.1.6` (4-phase UI padding & margin audit remediation across 491 files, dynamic dictation panel frame expansion, and unified Retina hairline dividers).
  - Made the `CURRENT` release badge in `ChangelogSettingsView` dynamic based on the active running build version.

- **Selective Upstream Radar Ports (2026-11-25, Tinycast + EnviousWispr)**:
  - **Tinycast**: Ported `75f00462` (pasted/partial file path search `#1988`), `90a35d39` + `ce14fd3d` (`Switch to Previous Room` / `Tidy Current Room` commands, `Room.previous(to:in:)`, shared `pillPresenter` + `RoomHUDController`/`RoomHUDView`, dropping `Add Window to Current Room`), and clean `970bf4e4` fixes (`AppleShortcutRunner` cancellation check, `EmojiScreen` horizontal arrow guard at `count <= 1`, `NoteRevealPolicy.restingCaret` + `fitsWindowToNote` / `Fit Window to Note` titlebar action). Skipped `#1989` AI plan usage menu bar, iCloud sync, and `IconTile`/`Backup v2`.
  - **EnviousWispr** (excluding EQ-1): Ported `722fb06` (AX setter read-back verification in `TextInjector.replaceUsingAccessibility` + `TextReplacementPolicy.accessibilityWriteDisposition` to stop Telegram/TickTick double-pasting), `421578e` + `f515a84`/`5091a32` (mid-take dead-air warning & recovery in `DictationCapture`, serialized session start/stop transitions with 4s start timeout, panel silence state reset), `eeddfab` (`DictationDictionaryStore` + `collapseRepetitions` normalization on meeting transcripts), `4adb364` (compiled regex caching in `DictationTextFormatter` & `DictationDictionaryStore`), `854135d` + `09fbe74` (`DictationLanguage.previewLocale(for:)` BCP-47 resolution, Mandarin vs Cantonese `isCantonese` fallback separation, `SpeechAnalyzer` cache reset on error), `10387be` (post-download model prewarm), and `eea574c` (`SettingsSearchCatalog.prewarm()` off-main on Settings open).
  - Marked `.upstream-synced` (`ed7c2917`) and `.enviouswispr-synced` (`d44f45c`) reviewed; verified Debug/Release `xcodebuild`, `sync-strings.sh`, `check-localizations.js`, `check-settings-search.js`, `check-migrations.sh`, and 139/139 test harnesses; rebuilt and installed signed Release `/Applications/szcast.app` via `Scripts/build-dmg.sh`.

- **3-Level Alfred-Style Snippet Folders (2026-11-26)**:
  - Replaced tag-pill snippet grouping with real 3-level disk subdirectories under `Snippets/`, optional `.szcast-folder.json` collection metadata (`isEnabled`, `keywordPrefix`, `icon`), recursive subfolder directory watchers, and `.snippet(id:)` hotkey migration on file moves and folder renames (`SnippetFolder.swift`, `SnippetRepository.swift`, `SnippetsStore.swift`, `HotKeyManager.swift`).
  - Rebuilt `Hyper + S` (`SnippetsScreen.swift`, `SnippetsListView.swift`) to show Folders first when empty (with `↵`/`→` drill-down and `Esc`/`←`/backspace step-back) while continuing global search across all enabled snippets on typing.
  - Replaced the editor's free-text folder/tag field with a folder picker + live prefix preview (`SnippetEditorView.swift`), added `SnippetFolderConfigField.swift` & `SnippetFolderIconView.swift`, and grouped Settings Library into a collapsible 3-level folder tree (`SnippetsSettingsView.swift`).
  - Verified `./Scripts/lint.sh` (`✓ lint-clean`), Debug `xcodebuild`, and 139/139 harnesses in `./Scripts/run-tests.sh` (note: installed `swiftlint` & `xcodegen`; kept `HEAD`'s `project.pbxproj` base over drifted `project.yml`).

- **Footer Shortcut Strip Moved to `⌘K` Actions (2026-11-26)**:
  - Removed `contextualShortcutStrip`, `currentContextualShortcuts`, and `ContextualShortcut` from `RootPaletteView.swift`, restoring a clean bottom bar across all 9 modes (`.snippets`, `.clipboard`, `.emoji`, `.fileSearch`, `.systemStats`, `.textTransformer`, `.quicklinks`, `.keepassxc`, `.enteAuth`).
  - Removed KeePassXC's detail `Footer Shortcut Legend` (`ShortcutBadge`) and row shortcut badges in `KeePassXCScreen.swift`, and added `actions(at:)` menus to `StatsScreen.swift`, `TextTransformerScreen.swift`, `EnteAuthScreen.swift`, and `KeePassXCScreen.swift`.
  - Synced and translated 8 new keys in `Localizable.xcstrings` across all 8 languages; `./Scripts/lint.sh`, Debug `xcodebuild`, and 139/139 harnesses in `./Scripts/run-tests.sh` pass.

## Active State & Next Steps
- **Active State**: Committed and pushed 3-level snippet folders and `⌘K` actions consolidation to `origin/main`; signed Release build (`v1.1.6`) built via `Scripts/build-dmg.sh` and installed to `/Applications/szcast.app` (139/139 harnesses pass, lint & Debug build clean).
- **Immediate Next Steps**:
  1. Test long continuous dictation (5+ minutes) in real-world workflows across Hindi and Bengali models.
  2. Perform weekly upstream radar audit (`./Scripts/upstream-radar.sh`).

Attribution: AGPL-3.0. Copyright © 2026 Abue Ammar in LICENSE; NOTICE.md keeps third-party material. Fork of Tinycast; no affiliation implied.
