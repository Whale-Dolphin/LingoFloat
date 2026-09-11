import Foundation
import Testing
@testable import LingoFloat

struct WhisperModelInstallerTests {
    @Test("incomplete model folders are rejected")
    func rejectsIncompleteFolder() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try createModelComponent(named: "MelSpectrogram", in: root)
        try createModelComponent(named: "AudioEncoder", in: root)

        #expect(!WhisperModelInstaller.isCompleteModelFolder(root))
    }

    @Test("all required non-empty Core ML components form a complete model")
    func acceptsCompleteFolder() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try createModelComponent(named: component, in: root)
        }

        #expect(WhisperModelInstaller.isCompleteModelFolder(root))
    }

    @Test("managed model folder must match the selected variant")
    func matchesSelectedVariant() {
        let small = URL(fileURLWithPath: "/tmp/openai_whisper-small", isDirectory: true)
        #expect(WhisperModelInstaller.folderMatches(small, model: .small))
        #expect(!WhisperModelInstaller.folderMatches(small, model: .medium))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func createModelComponent(named name: String, in root: URL) throws {
        let weights = root
            .appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            .appendingPathComponent("weights", isDirectory: true)
        try FileManager.default.createDirectory(at: weights, withIntermediateDirectories: true)
        try Data([0x01]).write(to: weights.appendingPathComponent("weight.bin"))
    }
}
