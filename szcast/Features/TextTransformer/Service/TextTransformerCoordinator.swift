import AppKit
import SwiftUI

@MainActor
final class TextTransformerCoordinator: ObservableObject {
    @Published var inputText: String = "" {
        didSet {
            recalculate()
        }
    }
    @Published var activeCategory: TransformCategory = .all
    @Published var selectedTransform: TextTransformType = .camelCase {
        didSet {
            recalculate()
        }
    }
    @Published var outputText: String = ""
    @Published var metrics: TextMetrics = .zero
    @Published var outputMetrics: TextMetrics = .zero
    @Published var isDiffMode: Bool = false

    private var initialText: String = ""

    init() {
        recalculate()
    }

    func prepareOnOpen(seedingQuery: String? = nil) {
        if let query = seedingQuery, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputText = query
            initialText = query
        } else if let pbString = NSPasteboard.general.string(forType: .string),
                  !pbString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputText = pbString
            initialText = pbString
        } else if inputText.isEmpty {
            inputText = "szcast native text transformer engine"
            initialText = inputText
        }
        recalculate()
    }

    func recalculate() {
        outputText = TextTransformEngine.transform(inputText, using: selectedTransform)
        metrics = TextMetrics(text: inputText)
        outputMetrics = TextMetrics(text: outputText)
    }

    func resetToInitial() {
        inputText = initialText
        recalculate()
    }

    func clearInput() {
        inputText = ""
        recalculate()
    }

    func toggleDiffMode() {
        isDiffMode.toggle()
    }

    func filteredTransforms(matching query: String) -> [TextTransformType] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return TextTransformType.allCases.filter { type in
            if activeCategory != .all && type.category != activeCategory {
                return false
            }
            if q.isEmpty {
                return true
            }
            return type.title.lowercased().contains(q)
                || type.subtitle.lowercased().contains(q)
                || type.rawValue.lowercased().contains(q)
                || type.category.title.lowercased().contains(q)
        }
    }

    func copyOutput() -> Bool {
        Paster.copyPlainText(outputText)
    }

    func pasteOutput(previousApp: NSRunningApplication?) {
        Paster.pasteString(outputText, previousApp: previousApp)
    }
}
