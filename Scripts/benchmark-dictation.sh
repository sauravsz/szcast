#!/bin/bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [ "${1:-}" = "" ] || [ "${1:-}" = "--ci" ] || [ "${1:-}" = "--synthetic" ]; then
    tmp_src=$(mktemp /tmp/szcast-bench.XXXXXX.swift)
    tmp_bin=$(mktemp /tmp/szcast-bench-bin.XXXXXX)
    trap 'rm -f "$tmp_src" "$tmp_bin"' EXIT
    cat > "$tmp_src" << 'SWIFT'
import Accelerate
import Foundation

@main
@MainActor
struct DictationPipelineBenchmark {
    static func main() {
        let sampleRate = 16_000
        let audio30s = (0..<(sampleRate * 30)).map { i -> Float in
            Float(0.05 * sin(2 * .pi * 240 * Double(i) / Double(sampleRate)))
        }
        let prepStart = CFAbsoluteTimeGetCurrent()
        let conditioned = DictationAudioChunks.conditionForTranscription(audio30s, whisperMode: false)
        let prepMs = (CFAbsoluteTimeGetCurrent() - prepStart) * 1000
        precondition(conditioned.count == audio30s.count, "Conditioning length mismatch")

        let mel = try! DictationMel()
        let melStart = CFAbsoluteTimeGetCurrent()
        for c in stride(from: 0, to: 16_000 * 30, by: 16_000 * 15) {
            _ = try! mel.features(conditioned[c..<min(c + 16_000 * 15, conditioned.count)])
        }
        let melMs = (CFAbsoluteTimeGetCurrent() - melStart) * 1000

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("szcast-bench-\(UUID())")
        let store = DictationDictionaryStore(
            fileURL: dir.appending(path: "words.json"),
            snippetsFileURL: dir.appending(path: "snippets.json")
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<80 {
            store.addWord(canonical: "Term\(i)", aliases: ["tirm\(i)"])
        }
        let rawTranscript = String(repeating: "Um, we use kubernetis and tirm12 for b-b-because at three fifteen pm, sorry I mean four pm. ", count: 25)
        let fmtStart = CFAbsoluteTimeGetCurrent()
        var formatted = ""
        for _ in 0..<10 {
            var s = DictationTextFormatter.stripHallucinations(rawTranscript)
            s = DictationTextFormatter.resolveBacktracks(s)
            s = DictationTextFormatter.collapseRepetitions(s)
            s = DictationTextFormatter.convertSpokenPunctuation(s)
            s = DictationTextFormatter.removeFillerWords(s)
            s = store.applyDictionaryAndPacks(s)
            formatted = DictationTextFormatter.format(s, context: nil)
        }
        let fmtMs = ((CFAbsoluteTimeGetCurrent() - fmtStart) * 1000) / 10.0
        precondition(!formatted.isEmpty)

        print("Synthetic Pipeline Benchmark (30s audio DSP + Mel + 80-hotword Trie + Formatter):")
        print(String(format: "  DSP Condition (30s): %.2f ms (%.4fx RTF)", prepMs, prepMs / 30_000.0))
        print(String(format: "  Mel 2x15s Chunks:    %.2f ms (%.4fx RTF)", melMs, melMs / 30_000.0))
        print(String(format: "  NLP+Hotword Avg:     %.2f ms", fmtMs))
    }
}
SWIFT
    swiftc -O -swift-version 6 -target "$(uname -m)-apple-macos26.0" \
        "$tmp_src" \
        "$repo/szcast/Features/Dictation/Model/DictationAudioChunks.swift" \
        "$repo/szcast/Features/Dictation/Model/DictationTextFormatter.swift" \
        "$repo/szcast/Features/Dictation/Model/CustomWord.swift" \
        "$repo/szcast/Features/Dictation/Model/DictationSnippet.swift" \
        "$repo/szcast/Features/Dictation/Model/VocabularyPack.swift" \
        "$repo/szcast/Features/Dictation/Service/DictationDictionaryStore.swift" \
        "$repo/szcast/Features/Dictation/Helper/DictationTensor.swift" \
        "$repo/szcast/Features/Dictation/Helper/DictationMel.swift" \
        "$repo/szcast/Platform/AppPaths.swift" \
        -o "$tmp_bin"
    "$tmp_bin"
    exit 0
fi

if (( $# < 1 || $# > 4 )); then
    printf 'Usage: %s [--ci | AUDIO [HELPER_APP] [MODEL_DIRECTORY] [MODEL]]\n' "${0##*/}" >&2
    exit 2
fi
helper=${2:-"$repo/build/DerivedData/Build/Products/Debug/szcast Dev.app/Contents/Helpers/szcast Dev Dictation.app"}
models=${3:-"$HOME/Library/Caches/com.sauravsz.szcast.dev/Dictation"}
binary=$(mktemp /tmp/szcast-dictation-benchmark.XXXXXX)
trap 'rm -f "$binary"' EXIT
swiftc -O -swift-version 6 -target "$(uname -m)-apple-macos26.0" \
    "$repo/Tests/dictation-performance.swift" \
    "$repo/szcast/Platform/ProcessExit.swift" \
    "$repo/szcast/Features/Dictation/Model/DictationModel.swift" \
    "$repo/szcast/Features/Dictation/Service/DictationWire.swift" -o "$binary"
"$binary" "$1" "$helper" "$models" "${4:-all}"
