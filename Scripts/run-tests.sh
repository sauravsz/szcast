#!/bin/bash
# The test suite: each harness compiles the shipped sources it guards. See docs/testing.md.

set -uo pipefail

# Absolute: the workers re-enter this script after the cd, where a relative $0 would not resolve.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.." || exit 1

BIN="${TMPDIR:-/tmp}/szcast-harness"
mkdir -p "$BIN"

# `--exec` is the worker half: xargs re-enters here once per queued harness.
if [ "${1:-}" = "--exec" ]; then
    shift
    name=$1 opt=$2
    shift 2
    : > "$BIN/$name.running"
    trap 'rm -f "$BIN/$name.running" "$BIN/$name.time"' EXIT
    fail() {
        printf '\033[31mFAIL\033[0m  %-25s %s\n' "$name" "$1"
        : > "$BIN/$name.failed"
        exit 0
    }
    TIMEFORMAT=%1R
    if ! compiled=$( { time swiftc -swift-version 6 "$opt" "$@" "Tests/$name.swift" -o "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2>&1 ); then
        fail "did not compile"
    fi
    { time "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2> "$BIN/$name.time" &
    pid=$!
    # macOS ships no `timeout`, so the worker polls; a wedged harness must fail, not stall.
    ticks=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$ticks" -ge $((SZCAST_TEST_TIMEOUT * 5)) ]; then
            { pkill -KILL -P "$pid"; kill -KILL "$pid"; wait "$pid"; } 2>/dev/null
            printf '\n[run-tests] killed after %ss without finishing\n' "$SZCAST_TEST_TIMEOUT" >> "$BIN/$name.log"
            fail "timed out after ${SZCAST_TEST_TIMEOUT}s"
        fi
        ticks=$((ticks + 1))
        sleep 0.2
    done
    wait "$pid"
    status=$?
    took=$(< "$BIN/$name.time")
    if [ "$status" -gt 128 ]; then fail "crashed (signal $((status - 128))) after ${took}s"; fi
    if [ "$status" -ne 0 ]; then fail "assertion failed after ${took}s"; fi
    printf '\033[32mok\033[0m    %-25s %5ss  \033[2m(compile %ss)\033[0m\n' "$name" "$took" "$compiled"
    exit 0
fi

failed=()
ran=0
only="${1:-}"

# `--index` feeds harness compile commands to .compile, as xcodebuild never compiles Tests/.
emit_db=0
DB="${TMPDIR:-/tmp}/szcast-compile-db.json"
if [ "$only" = "--index" ]; then
    emit_db=1
    only=""
    printf '[' > "$DB"
fi

QUEUE="$BIN/queue"
# `--index` queues nothing, so it must never reset the state of a suite already running.
if [ "$emit_db" -eq 0 ]; then
    # Queue, logs and verdicts are shared by path, so a second suite in this $TMPDIR waits its turn.
    if [ -z "${SZCAST_SUITE_LOCKED:-}" ]; then
        export SZCAST_SUITE_LOCKED=1
        lockf -k -t 0 "$BIN/suite.lock" true 2>/dev/null || echo "Waiting for the suite already running…" >&2
        exec lockf -k "$BIN/suite.lock" "$SELF" "$@"
    fi
    : > "$QUEUE"
    rm -f "$BIN"/*.failed "$BIN"/*.running
fi

# `slow` dispatches in the first wave; `index` only claims editor flags for a hand-run harness.
run() {
    local opt=-Onone pri=1 index_only=0
    while :; do
        case "$1" in
            slow)  pri=0; shift;;
            -O)    opt=-O; shift;;
            index) index_only=1; shift;;
            *)     break;;
        esac
    done
    local name=$1
    shift
    if [ -n "$only" ] && [ "$name" != "$only" ]; then return 0; fi
    if [ "$index_only" -eq 1 ] && [ "$emit_db" -eq 0 ]; then return 0; fi
    ran=$((ran + 1))

    # Absolute paths: sourcekit-lsp ignores `directory` for relative arguments and indexes nothing.
    if [ "$emit_db" -eq 1 ]; then
        local sources=()
        for source in "$@" "Tests/$name.swift"; do sources+=("$PWD/$source"); done
        [ "$ran" -gt 1 ] && printf ',' >> "$DB"
        printf '{"directory":"%s","command":"swiftc -swift-version 6 -sdk %s' \
            "$PWD" "$(xcrun --show-sdk-path --sdk macosx)" >> "$DB"
        printf ' %s' "${sources[@]}" >> "$DB"
        # Only `Tests/` files: `.compile` is last-wins, so a shipped source keeps the app's command.
        local claimed=""
        for source in "${sources[@]}"; do
            case "$source" in *"/Tests/"*) claimed="$claimed${claimed:+,}\"$source\"";; esac
        done
        printf '","files":[%s]}' "$claimed" >> "$DB"
        return 0
    fi

    # xargs splits the queue on whitespace, so no harness source path may contain a space.
    printf '%s %s %s %s\n' "$pri" "$name" "$opt" "$*" >> "$QUEUE"
}

L=Szcast/Features/Launcher/Model
run slow -O fuzz-test      $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift $L/LauncherSuggestions.swift
FS=Szcast/Features/FileSearch
FILE_INDEX="$FS/Service/FileIndex.swift $FS/Service/FileIndexSnapshot.swift $FS/Service/FileIndexCrawler.swift"
run file-search-test       $FS/Model/*.swift
run file-index-test        $FS/Model/*.swift $FILE_INDEX
run file-search-session-test $FS/Model/*.swift $FS/Service/FileSearchSession.swift $FILE_INDEX
run menu-search-test       $L/SearchRelevance.swift \
                           Szcast/Features/MenuSearch/Model/*.swift \
                           Szcast/Features/MenuSearch/Service/*.swift
run window-switch-test     $L/SearchRelevance.swift \
                           Szcast/Features/WindowSwitcher/Model/*.swift
run index file-search-performance $FS/Model/*.swift $FILE_INDEX
run ranking-test           $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/LauncherRankingStore.swift
run scopes-test            $L/SearchScopes.swift
run app-name-test          Szcast/Platform/AppDisplayName.swift \
                           Szcast/Platform/BundleLocalization.swift \
                           $L/SearchRelevance.swift
run ext-install-policy-test Szcast/Features/Extensions/Model/ExtensionInstallPolicy.swift
run favorites-test         $L/FavoriteSlots.swift
run favorite-slot-target-test  $L/FavoriteSlots.swift
run app-installation-test  $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift $L/LauncherSuggestions.swift $L/SearchScopes.swift \
                           Szcast/Features/Launcher/Service/AppIndex.swift \
                           Szcast/Features/Launcher/Service/AppLauncher.swift \
                           Szcast/Features/Launcher/Service/RunningAppsMonitor.swift \
                           Szcast/Features/Launcher/Service/FavoritesStore.swift \
                           $FS/Model/FileSearchResult.swift \
                           Szcast/Features/Launcher/Service/AliasStore.swift \
                           Szcast/Features/Launcher/Service/VisibilityStore.swift \
                           Szcast/Features/Launcher/Service/BundleNameCache.swift \
                           Szcast/Platform/AppDisplayName.swift Szcast/Platform/BundleLocalization.swift \
                           Szcast/Platform/SystemLanguages.swift \
                           Szcast/Platform/Images/FileIconStamp.swift Szcast/Platform/Memo.swift \
                           Szcast/Platform/Signposts.swift Szcast/Platform/NotificationToken.swift \
                           Szcast/Platform/LocalizedResource.swift
run launcher-file-test     $L/LauncherFileFormat.swift \
                           Szcast/Features/Settings/Model/SettingsFileJSON.swift
run launcher-settings-file-test \
                           $L/LauncherFileFormat.swift $L/CommandID.swift $L/CommandCatalog.swift \
                           Szcast/Features/Launcher/Service/LauncherSettingsFile.swift \
                           Szcast/Features/Launcher/Service/AliasStore.swift \
                           Szcast/Features/Launcher/Service/VisibilityStore.swift \
                           Szcast/Features/Settings/SettingsTab.swift \
                           Szcast/Features/Settings/Model/*.swift \
                           Szcast/Features/HotKeys/Service/HotKeySettingsFile.swift \
                           Szcast/Features/HotKeys/Service/KeyShortcut.swift \
                           Szcast/Features/HotKeys/Model/HotKeyAction.swift \
                           Szcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Szcast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Szcast/Features/HotKeys/Model/HotKeySpelling.swift \
                           Szcast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Szcast/Features/HotKeys/Model/ModifierKey.swift \
                           Szcast/Features/HotKeys/Model/HyperKey.swift \
                           Szcast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Szcast/Platform/ASCIIKeyboardLayout.swift \
                           Szcast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Szcast/Features/Quicklinks/Model/Quicklink.swift \
                           Szcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Szcast/Features/SystemActions/Model/SystemAction.swift \
                           Szcast/Features/Snippets/Model/Snippet.swift \
                           Szcast/Platform/LocalizedResource.swift
run apple-shortcut-test    Szcast/Features/AppleShortcuts/Model/*.swift
run calc-test              Szcast/Features/Calculator/Model/*.swift
run index calc-performance Szcast/Features/Calculator/Model/*.swift
run calendar-test          Szcast/Features/Calendar/Model/*.swift \
                           Szcast/Features/Calendar/UI/EventEditorSession.swift
run clipboard-test         Szcast/Features/Clipboard/Model/ClipboardStore.swift \
                           Szcast/Platform/Images/ImageDerivative.swift \
                           Szcast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Szcast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Szcast/Features/Clipboard/Model/ColorValue.swift \
                           Szcast/Features/Clipboard/Model/ColorFormat.swift \
                           Szcast/Features/Clipboard/Model/ColorSpaces.swift
run clipboard-coordinator-test Szcast/Features/Clipboard/UI/ClipboardCoordinator.swift \
                           Szcast/Features/Clipboard/Model/*.swift \
                           Szcast/Platform/Images/ImageDerivative.swift \
                           Szcast/Palette/PaletteState.swift Szcast/Palette/PaletteMode.swift \
                           Szcast/Palette/HoverArming.swift \
                           Szcast/Features/Emoji/Model/EmojiCatalog.swift \
                           Szcast/Features/FileSearch/Model/FileSearchFilter.swift \
                           Szcast/Features/Quicklinks/Model/Quicklink.swift \
                           Szcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Szcast/Features/CustomCommands/Model/CustomCommand.swift
run clipboard-thumbnail-test Szcast/Features/Clipboard/Model/ClipboardStore.swift \
                           Szcast/Platform/Images/ImageDerivative.swift \
                           Szcast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Szcast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Szcast/Features/Clipboard/Model/ColorValue.swift \
                           Szcast/Features/Clipboard/Model/ColorFormat.swift \
                           Szcast/Features/Clipboard/Model/ColorSpaces.swift \
                           Szcast/Platform/ProcessExit.swift \
                           Szcast/Platform/Images/ImageThumbnail.swift \
                           Szcast/Platform/Images/ThumbnailCache.swift
# `Q` is the URL detector a drag payload builds its link with, rather than a second one.
Q=Szcast/Features/Quicklinks/Model/QuicklinkDestination.swift
run clipboard-search-test  Szcast/Features/Clipboard/Model/*.swift Szcast/Platform/Images/ImageDerivative.swift $Q
run paste-sequence-test    Szcast/Features/Clipboard/Model/*.swift Szcast/Platform/Images/ImageDerivative.swift $Q
run clipboard-text-test    Szcast/Features/Clipboard/Model/*.swift Szcast/Platform/Images/ImageDerivative.swift $Q \
                           Szcast/Features/Clipboard/Service/ClipboardTextExtractor.swift \
                           Szcast/Features/Clipboard/Service/ClipboardTextIndexer.swift \
                           Szcast/Features/Clipboard/Service/ClipboardTextWorker.swift \
                           Szcast/Platform/ProcessExit.swift
run pasteboard-test        Szcast/Platform/PasteboardFiles.swift \
                           Szcast/Features/Clipboard/Model/ClipboardStore.swift \
                           Szcast/Platform/Images/ImageDerivative.swift \
                           Szcast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Szcast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Szcast/Features/Clipboard/Model/ColorValue.swift \
                           Szcast/Features/Clipboard/Model/ColorFormat.swift \
                           Szcast/Features/Clipboard/Model/ColorSpaces.swift \
                           Szcast/Features/Clipboard/Service/ClipboardManager.swift \
                           Szcast/Features/Clipboard/Service/Paster.swift
run index clipboard-file-performance \
                           Szcast/Platform/PasteboardFiles.swift \
                           Szcast/Features/Clipboard/Model/ClipboardStore.swift \
                           Szcast/Platform/Images/ImageDerivative.swift \
                           Szcast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Szcast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Szcast/Features/Clipboard/Model/ColorValue.swift \
                           Szcast/Features/Clipboard/Model/ColorFormat.swift \
                           Szcast/Features/Clipboard/Model/ColorSpaces.swift \
                           Szcast/Features/Clipboard/Service/ClipboardManager.swift
run index clipboard-thumbnail-performance \
                           Szcast/Platform/ProcessExit.swift \
                           Szcast/Platform/Images/ImageThumbnail.swift \
                           Szcast/Platform/Images/ImageDerivative.swift \
                           Szcast/Platform/Images/ThumbnailCache.swift
run emoji-test             Szcast/Features/Emoji/Model/EmojiCatalog.swift \
                           Szcast/Features/Emoji/Model/EmojiGridGeometry.swift \
                           Szcast/Features/Emoji/Model/EmojiData.generated.swift
run emoji-search-test      Szcast/Features/Emoji/Model/EmojiCatalog.swift \
                           Szcast/Features/Emoji/Model/EmojiData.generated.swift \
                           Szcast/Features/Emoji/Service/EmojiIndex.swift \
                           Szcast/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Szcast/Features/Emoji/Service/PinnedEmojiStore.swift \
                           Szcast/Features/Launcher/Model/SearchRelevance.swift \
                           Szcast/Platform/AppPaths.swift Szcast/Platform/Memo.swift
run index emoji-search-performance \
                           Szcast/Features/Emoji/Model/EmojiCatalog.swift \
                           Szcast/Features/Emoji/Model/EmojiData.generated.swift \
                           Szcast/Features/Emoji/Service/EmojiIndex.swift \
                           Szcast/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Szcast/Features/Launcher/Model/SearchRelevance.swift \
                           Szcast/Platform/AppPaths.swift Szcast/Platform/Memo.swift
run palette-selection-test Szcast/Features/PaletteRowIndex.swift \
                           Szcast/Features/Emoji/Model/EmojiGridGeometry.swift
run appearance-test        Szcast/Platform/Appearance.swift \
                           Szcast/DesignSystem/Theme.swift \
                           Szcast/DesignSystem/InterfaceMetrics.swift \
                           Szcast/Features/Settings/AppAppearance.swift
run language-test          Szcast/Features/Settings/AppLanguage.swift
run localized-resource-test Szcast/Platform/LocalizedResource.swift
run relaunch-test          Szcast/App/AppDelegate.swift Szcast/Platform/RelaunchRunner.swift
run interface-size-test    Szcast/Platform/Appearance.swift \
                           Szcast/DesignSystem/Theme.swift \
                           Szcast/DesignSystem/InterfaceMetrics.swift \
                           Szcast/Features/Settings/InterfaceSize.swift \
                           Szcast/Features/Extensions/Model/ExtensionFormMetrics.swift
run palette-placement-test Szcast/Platform/Appearance.swift \
                           Szcast/DesignSystem/Theme.swift \
                           Szcast/DesignSystem/InterfaceMetrics.swift \
                           Szcast/Features/Settings/InterfaceSize.swift \
                           Szcast/Palette/PalettePlacement.swift
run palette-menu-click-test Szcast/Platform/Appearance.swift \
                           Szcast/DesignSystem/Theme.swift \
                           Szcast/Platform/WindowLevel.swift \
                           Szcast/Platform/NotificationToken.swift \
                           Szcast/DesignSystem/Interaction/KeyboardFocus.swift \
                           Szcast/DesignSystem/Interaction/Motion.swift \
                           Szcast/DesignSystem/Interaction/AnimatedPanel.swift \
                           Szcast/Palette/PalettePanel.swift
run form-input-test        Szcast/Platform/Appearance.swift \
                           Szcast/DesignSystem/Theme.swift \
                           Szcast/DesignSystem/InterfaceMetrics.swift \
                           Szcast/DesignSystem/FormTextInput.swift \
                           Szcast/DesignSystem/FormTextArea.swift
run scroll-reveal-test     Szcast/DesignSystem/Scrolling/SelectionReveal.swift
run redaction-test         Szcast/DesignSystem/RedactedPlaceholder.swift
run keyboard-focus-test    Szcast/DesignSystem/Interaction/KeyboardFocus.swift
run command-escape-tap-test Szcast/Palette/CommandEscapeTap.swift
run palette-escape-test    Szcast/Palette/PaletteMode.swift \
                           Szcast/Palette/PaletteEscapeAction.swift \
                           Szcast/Palette/CommandEscapeTap.swift \
                           Szcast/Features/Settings/EscapeKeyBehavior.swift \
                           Szcast/Features/Quicklinks/Model/Quicklink.swift \
                           Szcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Szcast/Features/CustomCommands/Model/CustomCommand.swift
run palette-navigation-test Szcast/Palette/PaletteState.swift \
                           Szcast/Palette/PaletteMode.swift \
                           Szcast/Palette/HoverArming.swift \
                           Szcast/Features/Emoji/Model/EmojiCatalog.swift \
                           Szcast/Features/Clipboard/Model/ClipboardStore.swift \
                           Szcast/Platform/Images/ImageDerivative.swift \
                           Szcast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Szcast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Szcast/Features/FileSearch/Model/FileSearchFilter.swift \
                           Szcast/Features/Clipboard/Model/ColorValue.swift \
                           Szcast/Features/Clipboard/Model/ColorFormat.swift \
                           Szcast/Features/Clipboard/Model/ColorSpaces.swift \
                           Szcast/Features/Quicklinks/Model/Quicklink.swift \
                           Szcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Szcast/Features/CustomCommands/Model/CustomCommand.swift
run palette-filter-test    Szcast/Palette/PaletteMode.swift \
                           Szcast/Palette/PaletteFilterAction.swift \
                           Szcast/Features/Quicklinks/Model/Quicklink.swift \
                           Szcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Szcast/Features/CustomCommands/Model/CustomCommand.swift
run action-menu-search-test Szcast/Palette/ActionMenuSearchQuery.swift \
                            Szcast/Features/Launcher/Model/SearchRelevance.swift
run palette-shortcut-test  Szcast/Palette/PaletteShortcut.swift
run ascii-layout-test      Szcast/Platform/ASCIIKeyboardLayout.swift
run palette-tab-test       Szcast/Palette/PaletteMode.swift \
                           Szcast/Palette/PaletteTabAction.swift \
                           Szcast/Features/Quicklinks/Model/Quicklink.swift \
                           Szcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Szcast/Features/CustomCommands/Model/CustomCommand.swift
run compact-bar-test       Szcast/Features/Launcher/Model/CompactBarSelection.swift \
                           Szcast/Features/Settings/AppSettingsKey.swift \
                           Szcast/Features/Settings/Model/*.swift \
                           Szcast/Features/Launcher/Model/CommandID.swift \
                           Szcast/Features/HotKeys/Model/HotKeyAction.swift \
                           Szcast/Features/QuickActions/Model/QuickAction.swift \
                           Szcast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Szcast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Szcast/Features/Quicklinks/Model/Quicklink.swift \
                           Szcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Szcast/Features/SystemActions/Model/SystemAction.swift \
                           Szcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Szcast/Features/Snippets/Model/Snippet.swift \
                           Szcast/Platform/LocalizedResource.swift
run fallback-test          Szcast/Features/Launcher/Model/Fallback.swift \
                           Szcast/Features/Launcher/Model/CommandID.swift \
                           Szcast/Features/Launcher/Model/DefaultFallbacks.swift \
                           Szcast/Features/HotKeys/Model/HotKeyAction.swift \
                           Szcast/Features/QuickActions/Model/QuickAction.swift \
                           Szcast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Szcast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Szcast/Features/Quicklinks/Model/Quicklink.swift \
                           Szcast/Features/Quicklinks/Model/DefaultQuicklinks.swift \
                           Szcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Szcast/Features/SystemActions/Model/SystemAction.swift \
                           Szcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Szcast/Features/Snippets/Model/Snippet.swift \
                           Szcast/Platform/LocalizedResource.swift
run dictionary-test        Szcast/Features/Dictionary/Model/DictionaryEntry.swift \
                           Szcast/Features/Dictionary/Model/DictionaryMarkup.swift
run dictation-test         Szcast/Features/Dictation/Model/DictationModel.swift Szcast/Features/Dictation/Model/DictationIdleRelease.swift Szcast/Features/Dictation/Model/DictationLanguage.swift Szcast/Features/Dictation/Model/DictationTextFormatter.swift Szcast/Features/Dictation/Model/DictationS1Settings.swift Szcast/Features/Dictation/Model/CustomWord.swift Szcast/Features/Dictation/Model/VocabularyPack.swift Szcast/Features/Dictation/Service/DictationS1Polisher.swift Szcast/Features/Dictation/Service/DictationS1Downloader.swift Szcast/Features/Dictation/Service/DictationLlamaServerManager.swift Szcast/Platform/AppPaths.swift
run dictation-cue-test     Szcast/Features/Dictation/Service/DictationCueRunner.swift
run dictation-field-test   Szcast/Features/Dictation/Model/DictationModel.swift \
                           Szcast/Features/Dictation/Model/DictationAudioChunks.swift \
                           Szcast/Features/Dictation/Model/DictationMode.swift \
                           Szcast/Features/Dictation/Model/DictationDestination.swift \
                           Szcast/Features/Dictation/Model/DictationTextFormatter.swift \
                           Szcast/Features/Dictation/Model/DictationOtherAudioMode.swift \
                           Szcast/Features/Dictation/Model/DictationS1Settings.swift \
                           Szcast/Features/Dictation/Model/DictationIdleRelease.swift \
                           Szcast/Features/Dictation/Model/CustomWord.swift \
                           Szcast/Features/Dictation/Model/VocabularyPack.swift \
                           Szcast/Features/Dictation/Model/DictationSnippet.swift \
                           Szcast/Features/Dictation/Model/DictationHistoryItem.swift \
                           Szcast/Features/Dictation/Service/DictationCoordinator.swift \
                           Szcast/Features/Dictation/Service/DictationInsertionContext.swift \
                           Szcast/Features/Dictation/Service/DictationDictionaryStore.swift \
                           Szcast/Features/Dictation/Service/DictationHistoryStore.swift \
                           Szcast/Features/Dictation/Service/DictationS1Polisher.swift \
                           Szcast/Features/Dictation/Service/DictationS1Downloader.swift \
                           Szcast/Features/Dictation/Service/DictationLlamaServerManager.swift \
                           Szcast/DesignSystem/ChatTypography.swift \
                           Szcast/Features/AI/UI/ChatComposerTextView.swift \
                           Szcast/Features/TextInjection/Service/*.swift \
                           Szcast/Features/Snippets/Model/*.swift \
                           Szcast/Platform/AccessibilityText.swift \
                           Szcast/Platform/PasteboardFiles.swift \
                           Szcast/Platform/AppPaths.swift \
                           Szcast/Platform/Appearance.swift Szcast/DesignSystem/Theme.swift
run dictation-volume-test  Szcast/Features/Dictation/Model/DictationVolumeSnapshot.swift \
                           Szcast/Features/Dictation/Model/DictationOtherAudioMode.swift \
                           Szcast/Features/Dictation/Service/DictationAudioDucker.swift \
                           Szcast/Platform/AppPaths.swift
run index -O dictation-performance Szcast/Platform/ProcessExit.swift \
                           Szcast/Features/Dictation/Model/DictationModel.swift \
                           Szcast/Features/Dictation/Service/DictationWire.swift
run dictation-inference-test Szcast/Features/Dictation/Model/DictationAudioChunks.swift \
    Szcast/Features/Dictation/Service/DictationSpectrum.swift \
    Szcast/Features/Dictation/Helper/DictationTensor.swift Szcast/Features/Dictation/Helper/DictationTokenizer.swift \
    Szcast/Features/Dictation/Helper/DictationMel.swift
run dictation-worker-test  Szcast/Features/Dictation/Model/DictationModel.swift \
                           Szcast/Features/Dictation/Model/DictationIdleRelease.swift \
                           Szcast/Features/Dictation/Service/DictationWire.swift \
                           Szcast/Features/Dictation/Service/DictationWorker.swift \
                           Szcast/Features/Dictation/Service/DictationModelStore.swift \
                           Szcast/Features/Dictation/Service/DictationModelDownloader.swift \
                           Szcast/Platform/ProcessExit.swift Szcast/Platform/AppPaths.swift
run hotkey-test            Szcast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Szcast/Features/HotKeys/Model/ModifierKey.swift \
                           Szcast/Features/HotKeys/Model/ModifierKeyDetector.swift \
                           Szcast/Features/HotKeys/Model/DoubleTapDetector.swift \
                           Szcast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Szcast/Features/HotKeys/Model/HotKeySpelling.swift \
                           Szcast/Features/HotKeys/Model/HyperKey.swift \
                           Szcast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Szcast/Platform/ASCIIKeyboardLayout.swift \
                           Szcast/Features/HotKeys/Service/KeyShortcut.swift \
                           Szcast/Features/HotKeys/Model/HotKeyAction.swift \
                           Szcast/Features/QuickActions/Model/QuickAction.swift \
                           Szcast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Szcast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Szcast/Features/Launcher/Model/CommandID.swift \
                           Szcast/Features/Quicklinks/Model/Quicklink.swift \
                           Szcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Szcast/Features/SystemActions/Model/SystemAction.swift \
                           Szcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Szcast/Features/Snippets/Model/Snippet.swift \
                           Szcast/Platform/LocalizedResource.swift
run callout-test          Szcast/Platform/Appearance.swift \
                           Szcast/DesignSystem/Theme.swift \
                           Szcast/DesignSystem/InterfaceMetrics.swift \
                           Szcast/Features/HotKeys/UI/CalloutPlacement.swift
run icon-cache-test        Szcast/Platform/Appearance.swift \
                           Szcast/Platform/Images/IconCache.swift
run entry-icon-test        Szcast/Platform/Appearance.swift \
                           Szcast/Platform/Images/IconCache.swift \
                           Szcast/Platform/Images/FileIconStamp.swift
run ext-icon-test          Szcast/Platform/Appearance.swift \
                           Szcast/Platform/AppDisplayName.swift \
                           Szcast/Platform/Images/IconCache.swift \
                           Szcast/Platform/Compression/Zlib.swift \
                           Szcast/DesignSystem/Theme.swift \
                           Szcast/DesignSystem/InterfaceMetrics.swift \
                           Szcast/Features/Extensions/Model/ExtensionBootConfig.swift \
                           Szcast/Features/Extensions/Model/ExtensionLaunchType.swift \
                           Szcast/Features/Extensions/Model/ExtensionManifest.swift \
                           Szcast/Features/Extensions/Model/ExtensionRefreshPolicy.swift \
                           Szcast/Features/Extensions/Model/ExtensionRefreshState.swift \
                           Szcast/Features/Extensions/Model/RenderNode.swift \
                           Szcast/Features/Extensions/Service/ExtensionCatalog.swift \
                           Szcast/Features/Extensions/Service/ExtensionFetcher.swift \
                           Szcast/Platform/ProcessExit.swift \
                           Szcast/Features/Extensions/Service/ExtensionNodeShims.swift \
                           Szcast/Features/Extensions/Service/ExtensionRuntime.swift \
                           Szcast/Features/Extensions/Service/ExtensionIconCache.swift \
                           Szcast/Features/Extensions/UI/ExtensionAnimatedImage.swift \
                           Szcast/Features/Extensions/UI/ExtensionImage.swift \
                           Szcast/Features/Clipboard/Model/ColorValue.swift \
                           Szcast/Features/Clipboard/Model/ColorSpaces.swift
run system-action-test     Szcast/Features/SystemActions/Model/SystemAction.swift \
                           Szcast/Platform/LocalizedResource.swift
run microphone-mute-test   Szcast/Features/SystemActions/Service/SystemActionFailure.swift \
                           Szcast/Features/SystemActions/Service/SystemActionRunner+Microphone.swift
run volume-test            Szcast/Features/SystemActions/Model/VolumeLevel.swift
run window-command-test    Szcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Szcast/Features/WindowManagement/Model/WindowCycle.swift \
                           Szcast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Szcast/Features/WindowManagement/Model/WindowActionMemory.swift \
                           Szcast/Platform/LocalizedResource.swift
run window-preset-test     Szcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Szcast/Features/WindowManagement/Model/WindowShortcutPreset.swift \
                           Szcast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Szcast/Features/HotKeys/Model/ModifierKey.swift \
                           Szcast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Szcast/Features/HotKeys/Model/HyperKey.swift \
                           Szcast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Szcast/Platform/ASCIIKeyboardLayout.swift \
                           Szcast/Features/HotKeys/Service/KeyShortcut.swift \
                           Szcast/Platform/LocalizedResource.swift
run space-gesture-test     Szcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Szcast/Features/WindowManagement/Model/SpaceGesture.swift \
                           Szcast/Platform/LocalizedResource.swift
run window-layout-test     Szcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Szcast/Features/WindowManagement/Model/WindowCycle.swift \
                           Szcast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayout.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayoutPlan.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayoutStore.swift \
                           Szcast/Features/WindowManagement/Model/CustomWindowSize.swift \
                           Szcast/Features/WindowManagement/Model/CustomWindowSizeStore.swift \
                           Szcast/Platform/LocalizedResource.swift
run deeplink-test          Szcast/Features/DeepLinks/Model/DeepLink.swift \
                           Szcast/Features/DeepLinks/Model/DeepLinkInput.swift \
                           Szcast/Features/DeepLinks/Model/DeepLinkConsentPolicy.swift \
                           Szcast/Features/DeepLinks/Model/DeepLinkSource.swift \
                           Szcast/Features/DeepLinks/Model/CustomWindowSize+DeepLink.swift \
                           Szcast/Features/Settings/SettingsTab.swift \
                           Szcast/Features/Launcher/Model/CommandID.swift \
                           Szcast/Features/HotKeys/Model/HotKeyAction.swift \
                           Szcast/Features/HotKeys/Model/HotKeyAction+EntryID.swift \
                           Szcast/Features/QuickActions/Model/QuickAction.swift \
                           Szcast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Szcast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Szcast/Features/Quicklinks/Model/Quicklink.swift \
                           Szcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Szcast/Features/SystemActions/Model/SystemAction.swift \
                           Szcast/Features/CustomCommands/Model/CustomCommand.swift \
                           Szcast/Features/AppleShortcuts/Model/AppleShortcut.swift \
                           Szcast/Features/Snippets/Model/Snippet.swift \
                           Szcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Szcast/Features/WindowManagement/Model/WindowCycle.swift \
                           Szcast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayout.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Szcast/Features/WindowManagement/Model/RoomLayoutKind.swift \
                           Szcast/Features/WindowManagement/Model/RoomLayoutEngine.swift \
                           Szcast/Features/WindowManagement/Model/RoomGrid.swift \
                           Szcast/Features/WindowManagement/Model/RoomWindow.swift \
                           Szcast/Features/WindowManagement/Model/Room.swift \
                           Szcast/Features/WindowManagement/Model/CustomWindowSize.swift \
                           Szcast/Platform/LocalizedResource.swift
run window-room-test       Szcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Szcast/Features/WindowManagement/Model/WindowCycle.swift \
                           Szcast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayout.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayoutPlan.swift \
                           Szcast/Features/WindowManagement/Model/RoomLayoutKind.swift \
                           Szcast/Features/WindowManagement/Model/RoomLayoutEngine.swift \
                           Szcast/Features/WindowManagement/Model/RoomGrid.swift \
                           Szcast/Features/WindowManagement/Model/RoomWindow.swift \
                           Szcast/Features/WindowManagement/Model/Room.swift \
                           Szcast/Features/WindowManagement/Model/RoomWindowMatcher.swift \
                           Szcast/Features/WindowManagement/Model/RoomParking.swift \
                           Szcast/Features/WindowManagement/Model/RoomPlan.swift \
                           Szcast/Features/WindowManagement/Model/RoomArrangement.swift \
                           Szcast/Features/WindowManagement/Model/RoomStore.swift \
                           Szcast/Features/WindowManagement/Model/RoomMinimumSizeStore.swift \
                           Szcast/Features/WindowManagement/Model/RoomParkingLedger.swift \
                           Szcast/Platform/LocalizedResource.swift
run window-file-test       Szcast/Features/WindowManagement/Model/WindowCommand.swift \
                           Szcast/Features/WindowManagement/Model/WindowCycle.swift \
                           Szcast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayout.swift \
                           Szcast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Szcast/Features/WindowManagement/Model/CustomWindowSize.swift \
                           Szcast/Features/WindowManagement/Model/Room.swift \
                           Szcast/Features/WindowManagement/Model/RoomWindow.swift \
                           Szcast/Features/WindowManagement/Model/RoomLayoutKind.swift \
                           Szcast/Features/WindowManagement/Model/RoomGrid.swift \
                           Szcast/Features/WindowManagement/Model/RoomLayoutEngine.swift \
                           Szcast/Features/WindowManagement/Model/WindowManagementFileFormat.swift \
                           Szcast/Features/Settings/Model/SettingsFileJSON.swift \
                           Szcast/Features/Settings/Model/SettingsFileIdentity.swift \
                           Szcast/Platform/LocalizedResource.swift
run custom-command-test    Szcast/Platform/PseudoTerminal.swift \
                           Szcast/Platform/ProcessExit.swift \
                           Szcast/Features/CustomCommands/Model/CustomCommand.swift \
                           Szcast/Features/CustomCommands/Model/RaycastScriptImport.swift \
                           Szcast/Features/CustomCommands/UI/CustomCommandEditorSession.swift \
                           Szcast/Features/CustomCommands/Service/ShellCommandRunner.swift
run custom-command-list-test Szcast/Features/CustomCommands/Model/CustomCommand.swift \
                             Szcast/Features/CustomCommands/UI/CustomCommandListScreen.swift
run uninstall-coordinator-test Szcast/Features/Uninstall/Model/*.swift \
                           Szcast/Features/Uninstall/UI/UninstallCoordinator.swift
run uninstall-test         Szcast/Features/Uninstall/Model/UninstallTarget.swift \
                           Szcast/Features/Uninstall/Model/UninstallSearchRoot.swift \
                           Szcast/Features/Uninstall/Model/UninstallRules.swift \
                           Szcast/Features/Uninstall/Model/UninstallProtection.swift \
                           Szcast/Features/Uninstall/Model/UninstallPlan.swift
run quicklink-test         Szcast/Platform/AppPaths.swift \
                           Szcast/Features/Quicklinks/Service/QuicklinkFaviconService.swift \
                           Szcast/Features/Quicklinks/Model/Quicklink.swift \
                           Szcast/Features/Quicklinks/Model/DefaultQuicklinks.swift \
                           Szcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Szcast/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Szcast/Features/Quicklinks/Model/QuicklinkArchive.swift \
                           Szcast/Features/Quicklinks/Model/RaycastQuicklinkImport.swift \
                           Szcast/Features/Quicklinks/UI/QuicklinkEditorSession.swift
run quicklink-coordinator-test Szcast/Platform/AppPaths.swift \
                           Szcast/Features/Quicklinks/Service/QuicklinkFaviconService.swift \
                           Szcast/Features/Quicklinks/Model/Quicklink.swift \
                           Szcast/Features/Quicklinks/Model/DefaultQuicklinks.swift \
                           Szcast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Szcast/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Szcast/Features/Quicklinks/Model/QuicklinkArchive.swift \
                           Szcast/Features/Quicklinks/UI/QuicklinkCoordinator.swift \
                           Szcast/Features/Quicklinks/UI/QuicklinkEditorSession.swift \
                           Szcast/Features/Quicklinks/UI/QuicklinkArgumentsAccessory.swift \
                           Szcast/Features/Snippets/Model/Snippet.swift \
                           Szcast/Features/Snippets/Model/SnippetTemplateEngine.swift
run slow snippets-test     Szcast/Platform/NotificationToken.swift \
                           Szcast/Platform/HealthTicker.swift \
                           Szcast/Platform/AccessibilityText.swift \
                           Szcast/Features/Snippets/Model/*.swift \
                           Szcast/Features/Snippets/Service/*.swift \
                           Szcast/Features/Snippets/UI/SnippetEditorSession.swift \
                           Szcast/Features/TextInjection/Service/*.swift
run notes-test             Szcast/Platform/Signposts.swift \
                           $L/SearchRelevance.swift \
                           Szcast/Features/Notes/Model/*.swift \
                           Szcast/Features/Notes/Service/*.swift
run notes-editor-test      Szcast/Platform/Signposts.swift \
                           Szcast/Platform/Appearance.swift \
                           Szcast/DesignSystem/Theme.swift \
                           Szcast/DesignSystem/InterfaceMetrics.swift \
                           Szcast/Platform/NotificationToken.swift \
                           Szcast/Features/TextInjection/Service/InjectableTextView.swift \
                           Szcast/Features/Notes/Model/NoteDocument.swift \
                           Szcast/Features/Notes/Model/NoteTitle.swift \
                           Szcast/Features/Notes/Model/NoteMarkdown.swift \
                           Szcast/Features/Notes/Model/NoteMarkdownParser.swift \
                           Szcast/Features/Notes/Model/NoteInlineScanner.swift \
                           Szcast/Features/Notes/Model/NoteEditPlan.swift \
                           Szcast/Features/Notes/Model/NoteEditAction.swift \
                           Szcast/Features/Notes/Model/NoteFormatting.swift \
                           Szcast/Features/Notes/Model/NoteMarkdownEditing.swift \
                           Szcast/Features/Notes/Model/NoteRevealPolicy.swift \
                           Szcast/Features/Notes/UI/NoteMarkdownTypography.swift \
                           Szcast/Features/Notes/UI/NoteBlockDecoration.swift \
                           Szcast/Features/Notes/UI/NoteMarkdownStyler.swift \
                           Szcast/Features/Notes/UI/NoteMarkdownRenderer.swift \
                           Szcast/Features/Notes/UI/NoteCheckboxGeometry.swift \
                           Szcast/Features/Notes/UI/NoteBlockLayoutFragment.swift \
                           Szcast/Features/Notes/UI/NoteLayoutFragmentProvider.swift \
                           Szcast/Features/Notes/UI/NoteTextViewEditing.swift \
                           Szcast/Features/Notes/UI/NoteTextView.swift \
                           Szcast/Features/Notes/UI/NoteEditorView.swift
run -O index notes-editor-performance \
                           Szcast/Platform/Signposts.swift \
                           Szcast/Platform/Appearance.swift \
                           Szcast/DesignSystem/Theme.swift \
                           Szcast/DesignSystem/InterfaceMetrics.swift \
                           Szcast/Platform/NotificationToken.swift \
                           Szcast/Features/TextInjection/Service/InjectableTextView.swift \
                           Szcast/Features/Notes/Model/NoteDocument.swift \
                           Szcast/Features/Notes/Model/NoteTitle.swift \
                           Szcast/Features/Notes/Model/NoteMarkdown.swift \
                           Szcast/Features/Notes/Model/NoteMarkdownParser.swift \
                           Szcast/Features/Notes/Model/NoteInlineScanner.swift \
                           Szcast/Features/Notes/Model/NoteEditPlan.swift \
                           Szcast/Features/Notes/Model/NoteEditAction.swift \
                           Szcast/Features/Notes/Model/NoteFormatting.swift \
                           Szcast/Features/Notes/Model/NoteMarkdownEditing.swift \
                           Szcast/Features/Notes/Model/NoteRevealPolicy.swift \
                           Szcast/Features/Notes/UI/NoteMarkdownTypography.swift \
                           Szcast/Features/Notes/UI/NoteBlockDecoration.swift \
                           Szcast/Features/Notes/UI/NoteMarkdownStyler.swift \
                           Szcast/Features/Notes/UI/NoteMarkdownRenderer.swift \
                           Szcast/Features/Notes/UI/NoteCheckboxGeometry.swift \
                           Szcast/Features/Notes/UI/NoteBlockLayoutFragment.swift \
                           Szcast/Features/Notes/UI/NoteLayoutFragmentProvider.swift \
                           Szcast/Features/Notes/UI/NoteTextViewEditing.swift \
                           Szcast/Features/Notes/UI/NoteTextView.swift \
                           Szcast/Features/Notes/UI/NoteEditorView.swift
run slow -O raycast-test   Szcast/Features/Backup/Model/RaycastImportError.swift \
                           Szcast/Features/Backup/Service/RaycastDecoder.swift \
                           Szcast/Features/Backup/Service/Scrypt.swift \
                           Szcast/Platform/Compression/Zlib.swift \
                           Szcast/Features/Clipboard/Model/RaycastClipboardImport.swift \
                           Szcast/Features/Clipboard/Model/ClipboardStore.swift \
                           Szcast/Platform/Images/ImageDerivative.swift \
                           Szcast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Szcast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Szcast/Features/Clipboard/Model/ColorValue.swift \
                           Szcast/Features/Clipboard/Model/ColorFormat.swift \
                           Szcast/Features/Clipboard/Model/ColorSpaces.swift
run settings-backup-test   Szcast/Features/Settings/AppSettingsKey.swift \
                           Szcast/Features/Backup/Model/SettingsBackupCoverage.swift
run hyper-key-engine-test  Szcast/Features/HotKeys/Model/HyperKeyEngine.swift \
                           Szcast/Features/HotKeys/Model/HyperKey.swift \
                           Szcast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Szcast/Features/HotKeys/Model/ModifierKey.swift \
                           Szcast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Szcast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Szcast/Features/HotKeys/Service/KeyShortcut.swift \
                           Szcast/Platform/ASCIIKeyboardLayout.swift
run hyper-key-test         Szcast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Szcast/Features/HotKeys/Model/HyperKeyConflictPolicy.swift \
                           Szcast/Features/HotKeys/Service/KeyboardRemapper.swift \
                           Szcast/Features/HotKeys/Service/RemapInstanceLock.swift \
                           Tests/hyper-key-fixtures.swift
run dictation-key-test     Szcast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Szcast/Features/HotKeys/Model/HyperKeyConflictPolicy.swift \
                           Szcast/Features/HotKeys/Service/KeyboardRemapper.swift \
                           Szcast/Features/HotKeys/Service/RemapInstanceLock.swift \
                           Szcast/Features/HotKeys/Service/DictationKeyManager.swift \
                           Szcast/Platform/HealthTicker.swift \
                           Szcast/Platform/NotificationToken.swift \
                           Tests/hyper-key-fixtures.swift \
                           Tests/dictation-key-fixtures.swift
run hotkey-dispatch-test   Szcast/Features/HotKeys/Model/DefaultHotKeys.swift \
                           Szcast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Szcast/Features/HotKeys/Model/ModifierKey.swift \
                           Szcast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Szcast/Features/HotKeys/Model/HyperKey.swift \
                           Szcast/Features/HotKeys/Model/HIDKeyMapping.swift \
                           Szcast/Features/HotKeys/Model/HotKeyAction.swift \
                           Szcast/Features/HotKeys/Service/KeyShortcut.swift \
                           Szcast/Features/HotKeys/Service/HotKeyManager.swift \
                           Szcast/Platform/ASCIIKeyboardLayout.swift \
                           Tests/hotkey-dispatch-fixtures.swift
run settings-file-test     Szcast/Features/Settings/Model/*.swift \
                           Szcast/Features/Settings/Service/SettingsFileMonitor.swift \
                           Szcast/Features/Settings/Service/SettingsFileRepository.swift \
                           Szcast/Platform/AppPaths.swift
run backup-archive-test   Szcast/Platform/AppPaths.swift \
                           Szcast/Features/Backup/Model/BackupArchive.swift \
                           Szcast/Features/Backup/Model/BackupBundle.swift \
                           Szcast/Features/Backup/Model/BackupCategory.swift \
                           Szcast/Features/Backup/Model/BackupClipboardItem.swift \
                           Szcast/Features/Backup/Model/BackupManifest.swift \
                           Szcast/Features/Backup/Service/BackupStaging.swift
E=Szcast/Features/Extensions
run symbols-test           $E/Service/SymbolCatalog.swift
run ext-cleanup-test       $E/Service/ExtensionCleanup.swift \
                           $E/Service/ExtensionCatalog.swift \
                           Szcast/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ext-refresh-test       $E/Model/ExtensionManifest.swift \
                           Szcast/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ext-metadata-test      $E/Model/ExtensionCommandMetadata.swift \
                           $E/Model/ExtensionMenuBarSnapshot.swift \
                           $E/Service/ExtensionCommandMetadataStore.swift
run ext-version-test       $E/Model/ExtensionListing.swift \
                           $E/Service/ExtensionVersionStore.swift
run ext-store-test         $E/Model/ExtensionGitHubSource.swift \
                           $E/Model/ExtensionListing.swift \
                           $E/Model/ExtensionPackageManager.swift \
                           $E/Model/ExtensionStoreResponse.swift
run ext-form-test          $E/Model/ExtensionFormMetrics.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/UI/ExtensionFormKey.swift \
                           $E/Model/ExtensionDateExpression.swift \
                           $E/UI/ExtensionListKey.swift \
                           Tests/ext-list-key-test.swift
run ext-image-size-test   $E/Model/ExtensionImageSize.swift
run ext-sign-in-test       $E/Service/ExtensionSignInSession.swift
run ext-accessory-test     $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           Szcast/Platform/KeychainSecretStore.swift \
                           $E/Service/ExtensionStorage.swift
run slow ext-test          -parse-as-library \
                           Tests/ext-menu-bar-test.swift \
                           Tests/ext-fetch-test.swift \
                           $E/Model/ExtensionLaunchError.swift \
                           $E/Model/ExtensionMenuBarSnapshot.swift \
                           Szcast/Platform/KeychainSecretStore.swift \
                           $E/Service/ExtensionStorage.swift \
                           $E/Service/ExtensionMenuBarManager.swift \
                           $E/Model/ExtensionCommandMetadata.swift \
                           $E/Service/ExtensionCommandMetadataStore.swift \
                           $E/UI/ExtensionMenuBarController.swift \
                           $E/UI/ExtensionMenuBarImage.swift \
                           Szcast/Platform/Appearance.swift \
                           Szcast/Platform/AppDisplayName.swift \
                           Szcast/Platform/Images/IconCache.swift \
                           Szcast/DesignSystem/Theme.swift \
                           Szcast/DesignSystem/InterfaceMetrics.swift \
                           $E/Model/ExtensionBootConfig.swift \
                           $E/Model/ExtensionDeepLink.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/Model/ExtensionGridLayout.swift \
                           $E/Model/ExtensionSearchState.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift \
                           $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionCatalog.swift \
                           $E/Service/ExtensionFetcher.swift \
                           Szcast/Platform/ProcessExit.swift \
                           $E/Service/ExtensionIconCache.swift \
                           $E/Service/ExtensionNodeShims.swift \
                           $E/Service/ExtensionRuntime.swift \
                           $E/Service/ExtensionNameResolver.swift \
                           $E/Service/ExtensionWebSocketBridge.swift \
                           $E/UI/ExtensionAnimatedImage.swift \
                           $E/UI/ExtensionImage.swift \
                           $E/UI/ExtensionScreen.swift \
                           $L/SearchRelevance.swift \
                           Szcast/Platform/Compression/Zlib.swift \
                           Szcast/Features/Clipboard/Model/ColorValue.swift \
                           Szcast/Features/Clipboard/Model/ColorSpaces.swift
run settings-history-test  Szcast/Features/Settings/SettingsTab.swift \
                           Szcast/Features/Settings/SettingsHistory.swift \
                           Szcast/Features/Settings/SettingsAnchor.swift \
                           Szcast/Features/Settings/SettingsNavigationState.swift \
                           Szcast/Features/Settings/SettingsSearchCatalog.swift \
                           $L/SearchRelevance.swift \
                           Szcast/Platform/LocalizedResource.swift
run updates-test           Szcast/Features/Updates/Model/*.swift \
                           Szcast/Features/Updates/Service/BundleSignature.swift \
                           Szcast/Features/Updates/Service/UpdateSignature.swift
run update-check-test      Szcast/Features/Updates/Model/*.swift \
                           Szcast/Features/Updates/Service/UpdateCheckStore.swift \
                           Szcast/Platform/AppPaths.swift
run support-test           Szcast/Features/Support/Model/*.swift
run ai-provider-test       Szcast/Features/Settings/AppSettingsKey.swift \
                           Szcast/Platform/KeychainSecretStore.swift \
                           Szcast/Features/AI/Model/*.swift \
                           Szcast/Features/AI/Settings/AISettingsStore.swift \
                           Szcast/Features/AI/Service/CodexAppServerClient.swift \
                           Szcast/Features/AI/Service/InstalledAIProbe.swift \
                           Szcast/Platform/ExecutableLocator.swift Szcast/Platform/ProcessExit.swift
run opencode-mcp-test      Szcast/Features/AI/Model/*.swift \
                           Szcast/Platform/ExecutableLocator.swift Szcast/Platform/ProcessExit.swift \
                           Szcast/Features/AI/Service/AIProvider.swift \
                           Szcast/Features/AI/Service/AIToolLoopProvider.swift \
                           Szcast/Features/AI/Service/InstalledCLIProvider.swift \
                           Szcast/Features/AI/Service/OpenCodeMCPBridge.swift
run ai-chat-test           Szcast/Features/AI/Model/AIRequest.swift \
                           Szcast/Features/AI/Model/AIConnection.swift \
                           Szcast/Features/AI/Model/AIConversationOpenPolicy.swift \
                           Szcast/Features/AI/Model/AppleIntelligence.swift \
                           Szcast/Features/AI/Model/AIAttachmentPolicy.swift \
                           Szcast/Features/AI/Model/AIRetention.swift \
                           Szcast/Features/AI/Model/AITool.swift \
                           Szcast/Features/AI/Model/JSONValue.swift \
                           Szcast/Features/AI/Model/ChatMessage.swift \
                           Szcast/Features/AI/Model/ChatSession.swift \
                           Szcast/Features/AI/Model/ChatPreset.swift \
                           Szcast/Features/AI/Model/ChatChoices.swift \
                           Szcast/Features/AI/Model/ChatReferences.swift \
                           Szcast/Features/AI/Model/ChatTitle.swift \
                           Szcast/Features/AI/Model/ChatFind.swift \
                           Szcast/Features/AI/Model/ChatCitations.swift \
                           Szcast/Features/AI/Model/ChatToolScope.swift \
                           Szcast/Features/AI/Model/MarkdownBlock.swift \
                           Szcast/Features/AI/Model/MarkdownMath.swift \
                           Szcast/Features/AI/Model/MathFormula.swift \
                           Szcast/Features/AI/Model/MathNode.swift \
                           Szcast/Features/AI/Model/MathSymbolCatalog.swift \
                           Szcast/Features/AI/Service/AIProvider.swift \
                           Szcast/Features/AI/Service/ChatHistoryStore.swift \
                           Szcast/Features/AI/Service/AIToolLoopProvider.swift \
                           Szcast/Features/AI/UI/AIChatState.swift \
                           Szcast/Features/AI/UI/AIChatSurfacesState.swift \
                           Szcast/Features/AI/UI/ChatFindState.swift
run ai-responses-test      Szcast/Features/AI/Model/AIConnection.swift \
                           Szcast/Features/AI/Model/AppleIntelligence.swift \
                           Szcast/Features/AI/Model/AIModelDiscovery.swift \
                           Szcast/Features/AI/Model/AIRequest.swift \
                           Szcast/Features/AI/Model/AIRequestBody.swift \
                           Szcast/Features/AI/Model/AIStreamDecoder.swift \
                           Szcast/Features/AI/Model/AIResponsesDecoder.swift \
                           Szcast/Features/AI/Model/AIThinkTagDecoder.swift \
                           Szcast/Features/AI/Model/AIProviderFailure.swift \
                           Szcast/Features/AI/Model/AITool.swift \
                           Szcast/Features/AI/Model/JSONValue.swift \
                           Szcast/Features/AI/Service/AIProvider.swift \
                           Szcast/Features/AI/Service/AIToolLoopProvider.swift
run chat-markdown-test     Szcast/Platform/Appearance.swift \
                           Szcast/DesignSystem/Theme.swift \
                           Szcast/DesignSystem/InterfaceMetrics.swift \
                           Szcast/DesignSystem/ChatTypography.swift \
                           Szcast/Features/Settings/InterfaceSize.swift \
                           Szcast/Features/AI/Model/AIRequest.swift \
                           Szcast/Features/AI/Model/AITool.swift \
                           Szcast/Features/AI/Model/JSONValue.swift \
                           Szcast/Features/AI/Model/ChatMessage.swift \
                           Szcast/Features/AI/Model/ChatChoices.swift \
                           Szcast/Features/AI/Model/ChatReferences.swift \
                           Szcast/Features/AI/Model/ChatCitations.swift \
                           Szcast/Features/AI/Model/ChatFind.swift \
                           Szcast/Features/AI/Model/MarkdownBlock.swift \
                           Szcast/Features/AI/Model/MarkdownMath.swift \
                           Szcast/Features/AI/Model/MathFormula.swift \
                           Szcast/Features/AI/Model/MathNode.swift \
                           Szcast/Features/AI/Model/MathSymbolCatalog.swift \
                           Szcast/Features/AI/Model/SyntaxGrammar.swift \
                           Szcast/Features/AI/Model/SyntaxHighlighter.swift \
                           Szcast/Features/AI/Model/SyntaxStructuredLexers.swift \
                           Szcast/Features/AI/UI/ChatTextHighlight.swift \
                           Szcast/Features/AI/UI/ChatMarkdownRenderer.swift \
                           Szcast/Features/AI/UI/MathAttachmentCell.swift \
                           Szcast/Features/AI/UI/MathBox.swift \
                           Szcast/Features/AI/UI/MathFont.swift \
                           Szcast/Features/AI/UI/MathLayoutEngine.swift
run syntax-highlight-test  Szcast/Features/AI/Model/SyntaxGrammar.swift \
                           Szcast/Features/AI/Model/SyntaxHighlighter.swift \
                           Szcast/Features/AI/Model/SyntaxStructuredLexers.swift
run mcp-test               Szcast/Features/Settings/AppSettingsKey.swift \
                           Szcast/Features/AI/Model/AIConnection.swift \
                           Szcast/Features/AI/Model/AppleIntelligence.swift \
                           Szcast/Features/AI/Model/AITool.swift \
                           Szcast/Features/AI/Model/AIToolServer.swift \
                           Szcast/Features/AI/Model/JSONValue.swift \
                           Szcast/Features/MCP/Model/*.swift \
                           Szcast/Features/MCP/Settings/MCPSettingsStore.swift
run -O text-diff-test      Szcast/Features/QuickActions/Model/TextDiffEngine.swift
run index text-diff-performance Szcast/Features/QuickActions/Model/TextDiffEngine.swift
run quick-action-test      Szcast/Features/Settings/AppSettingsKey.swift \
                           Szcast/Features/AI/Model/AIConnection.swift \
                           Szcast/Features/AI/Model/AppleIntelligence.swift \
                           Szcast/Features/AI/Model/ChatGPTSubscription.swift \
                           Szcast/Features/AI/Model/InstalledAI.swift \
                           Szcast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Szcast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Szcast/Features/QuickActions/Model/CustomQuickActionStore.swift \
                           Szcast/Features/QuickActions/Model/QuickAction.swift \
                           Szcast/Features/QuickActions/Model/QuickActionFailure.swift \
                           Szcast/Features/QuickActions/Model/QuickActionPrompt.swift \
                           Szcast/Features/QuickActions/Model/QuickActionSettings.swift \
                           Szcast/Features/QuickActions/Settings/QuickActionSettingsStore.swift \
                           Szcast/Platform/LocalizedResource.swift
run apple-intelligence-test Szcast/Features/Settings/AppSettingsKey.swift \
                           Szcast/Features/AI/Model/*.swift \
                           Szcast/Features/AI/Service/AIProvider.swift \
                           Szcast/Features/AI/Service/AppleIntelligenceProvider.swift
run mcp-oauth-test         Szcast/Platform/ExecutableLocator.swift \
                           Szcast/Platform/ProcessExit.swift \
                           Szcast/Platform/KeychainSecretStore.swift \
                           Szcast/Features/Settings/AppSettingsKey.swift \
                           Szcast/Features/AI/Model/AIConnection.swift \
                           Szcast/Features/AI/Model/AppleIntelligence.swift \
                           Szcast/Features/AI/Model/AITool.swift \
                           Szcast/Features/AI/Model/AIToolServer.swift \
                           Szcast/Features/AI/Model/AIStreamDecoder.swift \
                           Szcast/Features/AI/Model/AIResponsesDecoder.swift \
                           Szcast/Features/AI/Model/AIProviderFailure.swift \
                           Szcast/Features/AI/Model/AIThinkTagDecoder.swift \
                           Szcast/Features/AI/Model/AIRequest.swift \
                           Szcast/Features/AI/Model/JSONValue.swift \
                           Szcast/Features/MCP/Model/*.swift \
                           Szcast/Features/MCP/Service/*.swift
run slow mcp-stdio-test    Szcast/Platform/ExecutableLocator.swift \
                           Szcast/Platform/ProcessExit.swift \
                           Szcast/Platform/KeychainSecretStore.swift \
                           Szcast/Features/Settings/AppSettingsKey.swift \
                           Szcast/Features/AI/Model/AIConnection.swift \
                           Szcast/Features/AI/Model/AppleIntelligence.swift \
                           Szcast/Features/AI/Model/AITool.swift \
                           Szcast/Features/AI/Model/AIToolServer.swift \
                           Szcast/Features/AI/Model/AIStreamDecoder.swift \
                           Szcast/Features/AI/Model/AIResponsesDecoder.swift \
                           Szcast/Features/AI/Model/AIProviderFailure.swift \
                           Szcast/Features/AI/Model/AIThinkTagDecoder.swift \
                           Szcast/Features/AI/Model/AIRequest.swift \
                           Szcast/Features/AI/Model/JSONValue.swift \
                           Szcast/Features/MCP/Model/*.swift \
                           Szcast/Features/MCP/Service/*.swift
run focus-timer-test       szcast/Features/FocusTimer/Model/*.swift \
                           szcast/Features/FocusTimer/Service/*.swift
run web-search-test        szcast/Features/AI/Model/WebSearchModel.swift \
                           szcast/Features/AI/Service/WebSearchService.swift


if [ "$emit_db" -eq 1 ]; then
    printf ']\n' >> "$DB"
    [ -f .compile ] || echo '[]' > .compile
    node -e '
const fs = require("node:fs");
const [comp, db] = process.argv.slice(1);
const existing = JSON.parse(fs.readFileSync(comp, "utf8"));
const harnesses = JSON.parse(fs.readFileSync(db, "utf8"));
const kept = existing.filter((e) => !(e.files || []).some((f) => f.includes("/Tests/")));
fs.writeFileSync(comp, JSON.stringify([...kept, ...harnesses], null, 1));
console.log(harnesses.length + " harness entries indexed into .compile");
' .compile "$DB"
    exit 0
fi

if [ "$ran" -eq 0 ]; then
    echo "No harness named '$only'." >&2
    exit 2
fi

# `sort -s` is stable, so the slow harnesses lead and everything else keeps its declaration order.
JOBS="${SZCAST_TEST_JOBS:-4}"
export SZCAST_TEST_TIMEOUT="${SZCAST_TEST_TIMEOUT:-300}"
started=$SECONDS

# Numbers each result, and names what is still running whenever the output goes quiet.
report() {
    local finished=0 line asked running file
    while :; do
        asked=$SECONDS
        if IFS= read -r -t 15 line; then
            case "$line" in
                "dispatch "*)
                    [ "$finished" -eq "$ran" ] || return 1
                    return "${line#dispatch }";;
            esac
            finished=$((finished + 1))
            printf '[%*d/%d] %s\n' "${#ran}" "$finished" "$ran" "$line"
            continue
        fi
        # Bash 3.2 returns the same status for a timeout and EOF; only EOF comes back at once.
        if [ $((SECONDS - asked)) -lt 10 ]; then return 1; fi
        running=""
        for file in "$BIN"/*.running; do
            [ -e "$file" ] && running="$running $(basename "$file" .running)"
        done
        printf '        \033[2mstill running after %ds:%s\033[0m\n' $((SECONDS - started)) "$running"
    done
}

dispatch() {
    [ -s "$1" ] || return 0
    sort -s -k1,1n "$1" | cut -d' ' -f2- | xargs -P "$2" -L1 "$SELF" --exec
}

# Without this the suite reports "all passed" whenever dispatch itself dies and no harness ran.
if ! {
    dispatch "$QUEUE" "$JOBS"
    echo "dispatch $?"
} | report; then
    echo "harness dispatch failed; no result below can be trusted" >&2
    exit 1
fi
elapsed=$((SECONDS - started))

# A compiler diagnostic is far longer than PIPE_BUF, so the workers log it and it is replayed here.
while read -r _ name _; do
    if [ -f "$BIN/$name.failed" ]; then failed+=("$name"); fi
done < "$QUEUE"

if [ ${#failed[@]} -gt 0 ]; then
    for name in "${failed[@]}"; do
        printf '\n\033[31m--- %s ---\033[0m\n' "$name"
        cat "$BIN/$name.log"
    done
    printf '\n\033[31mFAILED\033[0m  %d of %d harness(es) failed in %ds: %s\n' \
        "${#failed[@]}" "$ran" "$elapsed" "${failed[*]}" >&2
    exit 1
fi
printf '\n\033[32mPASSED\033[0m  All %d harness(es) passed in %ds.\n' "$ran" "$elapsed"
