import Foundation

@main
@MainActor
struct FinderFileActionsTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        testFolderDestinationModel()
        testUniqueDestinationPath()
        testMoveAndCopyOperations()
        testPinnedAndRecentFolders()

        print("FinderFileActionsTests: \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func testFolderDestinationModel() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let docs = home.appendingPathComponent("Documents")
        let dest = FinderFolderDestination(url: docs, kind: .pinned)

        expect(dest.name == "Documents", "Name matches folder name")
        expect(dest.kind == .pinned, "Kind matches .pinned")
        expect(dest.displayPath.hasPrefix("~"), "Display path collapses home to ~")
    }

    static func testUniqueDestinationPath() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1. Destination does not exist yet
        let target1 = FinderFileActionsService.getUniquePath(in: tempDir, for: "document.pdf", isDirectory: false)
        expect(target1.lastPathComponent == "document.pdf", "Non-existing target retains name")

        // 2. Create document.pdf
        FileManager.default.createFile(atPath: target1.path, contents: Data(), attributes: nil)
        let target2 = FinderFileActionsService.getUniquePath(in: tempDir, for: "document.pdf", isDirectory: false)
        expect(target2.lastPathComponent == "document 2.pdf", "Collision produces 'document 2.pdf'")

        // 3. Create document 2.pdf as well
        FileManager.default.createFile(atPath: target2.path, contents: Data(), attributes: nil)
        let target3 = FinderFileActionsService.getUniquePath(in: tempDir, for: "document.pdf", isDirectory: false)
        expect(target3.lastPathComponent == "document 3.pdf", "Second collision produces 'document 3.pdf'")

        // 4. Directory collision without extension
        let dir1 = tempDir.appendingPathComponent("MyFolder")
        try? FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        let targetDir = FinderFileActionsService.getUniquePath(in: tempDir, for: "MyFolder", isDirectory: true)
        expect(targetDir.lastPathComponent == "MyFolder 2", "Directory collision produces 'MyFolder 2'")
    }

    static func testMoveAndCopyOperations() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceDir = tempDir.appendingPathComponent("Source")
        let destDir = tempDir.appendingPathComponent("Dest")

        try? FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file1 = sourceDir.appendingPathComponent("test1.txt")
        try? "content 1".write(to: file1, atomically: true, encoding: .utf8)

        let service = FinderFileActionsService()

        // Move file1 into destDir
        let moveResult = try? service.moveItems(sources: [file1], to: destDir)
        expect(moveResult != nil && moveResult?.count == 1, "moveItems succeeded")
        expect(!FileManager.default.fileExists(atPath: file1.path), "Source file removed after move")
        expect(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("test1.txt").path), "Destination file exists after move")

        // Create file1 again in source, and move again (should resolve collision)
        try? "content 2".write(to: file1, atomically: true, encoding: .utf8)
        let moveCollisionResult = try? service.moveItems(sources: [file1], to: destDir)
        expect(moveCollisionResult != nil && moveCollisionResult?.count == 1, "move with collision succeeded")
        expect(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("test1 2.txt").path), "Collision-safe destination 'test1 2.txt' exists")

        // Copy file
        let fileToCopy = destDir.appendingPathComponent("test1.txt")
        let copyResult = try? service.copyItems(sources: [fileToCopy], to: sourceDir)
        expect(copyResult != nil && copyResult?.count == 1, "copyItems succeeded")
        expect(FileManager.default.fileExists(atPath: fileToCopy.path), "Original file remains after copy")
        expect(FileManager.default.fileExists(atPath: sourceDir.appendingPathComponent("test1.txt").path), "Copied file exists in destination")
    }

    static func testPinnedAndRecentFolders() {
        let service = FinderFileActionsService()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Test Pinning
        let isInitiallyPinned = service.pinnedFolders.contains(where: { $0.standardizedFileURL.path == tempDir.standardizedFileURL.path })
        expect(!isInitiallyPinned, "New temp folder is not pinned initially")

        let pinnedResult = service.togglePin(folder: tempDir)
        expect(pinnedResult == true, "togglePin returns true when pinning")
        let isNowPinned = service.pinnedFolders.contains(where: { $0.standardizedFileURL.path == tempDir.standardizedFileURL.path })
        expect(isNowPinned, "folder is now pinned")

        let unpinnedResult = service.togglePin(folder: tempDir)
        expect(unpinnedResult == false, "togglePin returns false when unpinning")
        let isNowUnpinned = !service.pinnedFolders.contains(where: { $0.standardizedFileURL.path == tempDir.standardizedFileURL.path })
        expect(isNowUnpinned, "folder is now unpinned")

        // Test Recent Folders
        service.addRecentFolder(tempDir)
        expect(service.recentFolders.first?.standardizedFileURL.path == tempDir.standardizedFileURL.path, "Recorded recent folder appears at front")
    }
}
