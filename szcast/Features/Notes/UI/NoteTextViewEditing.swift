import Foundation

@MainActor
protocol NoteTextViewEditing: AnyObject {
    var rendersMarkdown: Bool { get }
    var markdown: NoteMarkdown { get }
    var notesDirectory: URL? { get }
    func focusChanged()
    func appearanceChanged()
    func dragSelectionEnded()
}
