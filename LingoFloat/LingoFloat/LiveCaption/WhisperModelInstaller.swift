import Foundation

/// Owns LingoFloat's managed WhisperKit model storage and first-run download.
///
/// Models are data, not application resources: keeping them under Application
/// Support lets the installed app stay small and lets users switch checkpoints
/// without replacing the app bundle.
nonisolated enum WhisperModelInstaller {
    private static let applicationSupportFolder = "LingoFloat/Models"
    private static let repository = "argmaxinc/whisperkit-coreml"
    private static let revision = "main"

    static func downloadRoot() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent(applicationSupportFolder, isDirectory: true)

        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    static func isCompleteModelFolder(_ folder: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: folder.path) else { return false }

        let requiredModelPrefixes = [
            "MelSpectrogram",
            "AudioEncoder",
            "TextDecoder"
        ]

        guard let entries = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        ) else { return false }

        return requiredModelPrefixes.allSatisfy { prefix in
            entries.contains { url in
                url.lastPathComponent.hasPrefix(prefix)
                    && (url.pathExtension == "mlmodelc" || url.pathExtension == "mlpackage")
                    && isNonEmptyModelArtifact(url)
            }
        }
    }

    private static func isNonEmptyModelArtifact(_ artifact: URL) -> Bool {
        if artifact.pathExtension == "mlmodelc" {
            let weight = artifact.appendingPathComponent("weights/weight.bin")
            guard let values = try? weight.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
                return false
            }
            return values.isRegularFile == true && (values.fileSize ?? 0) > 0
        }

        guard let enumerator = FileManager.default.enumerator(
            at: artifact,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
                continue
            }
            if values.isRegularFile == true, (values.fileSize ?? 0) > 0 {
                return true
            }
        }
        return false
    }

    static func folderMatches(_ folder: URL, model: WhisperModel) -> Bool {
        folder.lastPathComponent.localizedCaseInsensitiveContains("whisper-\(model.rawValue)")
    }

    static func install(
        model: WhisperModel,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> URL {
        let root = try downloadRoot()
        let folder = root
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(model.modelName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        let entries = try await fetchModelFiles(model: model)
        let totalBytes = entries.reduce(Int64(0)) { $0 + Int64($1.size) }
        guard totalBytes > 0 else {
            throw WhisperModelInstallerError.emptyManifest(model.modelName)
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 3_600
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var completedBytes = entries.reduce(Int64(0)) { partial, entry in
            let destination = destinationURL(for: entry, model: model, folder: folder)
            return partial + (hasExpectedSize(destination, expectedSize: entry.size) ? Int64(entry.size) : 0)
        }
        await progress(Double(completedBytes) / Double(totalBytes))

        for entry in entries where !hasExpectedSize(
            destinationURL(for: entry, model: model, folder: folder),
            expectedSize: entry.size
        ) {
            let destination = destinationURL(for: entry, model: model, folder: folder)
            let source = try downloadURL(for: entry.path)
            try await downloadFile(
                from: source,
                to: destination,
                expectedSize: entry.size,
                session: session
            )
            completedBytes += Int64(entry.size)
            await progress(Double(completedBytes) / Double(totalBytes))
        }

        guard isCompleteModelFolder(folder) else {
            throw WhisperModelInstallerError.incompleteDownload(folder)
        }
        return folder
    }

    private static func fetchModelFiles(model: WhisperModel) async throws -> [ModelFile] {
        guard var components = URLComponents(
            string: "https://huggingface.co/api/models/\(repository)/tree/\(revision)/\(model.modelName)"
        ) else {
            throw WhisperModelInstallerError.invalidRemoteURL(model.modelName)
        }
        components.queryItems = [
            URLQueryItem(name: "recursive", value: "true"),
            URLQueryItem(name: "expand", value: "false")
        ]
        guard let url = components.url else {
            throw WhisperModelInstallerError.invalidRemoteURL(model.modelName)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WhisperModelInstallerError.invalidManifestResponse
        }

        let prefix = "\(model.modelName)/"
        return try JSONDecoder().decode([ModelTreeEntry].self, from: data)
            .compactMap { entry in
                guard entry.type == "file",
                      entry.size > 0,
                      entry.path.hasPrefix(prefix)
                else { return nil }
                return ModelFile(path: entry.path, size: entry.size)
            }
            .sorted { lhs, rhs in
                if lhs.size == rhs.size { return lhs.path < rhs.path }
                return lhs.size < rhs.size
            }
    }

    private static func destinationURL(
        for entry: ModelFile,
        model: WhisperModel,
        folder: URL
    ) -> URL {
        let prefix = "\(model.modelName)/"
        let relativePath = String(entry.path.dropFirst(prefix.count))
        return folder.appendingPathComponent(relativePath, isDirectory: false)
    }

    private static func downloadURL(for path: String) throws -> URL {
        guard var components = URLComponents(
            string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(path)"
        ) else {
            throw WhisperModelInstallerError.invalidRemoteURL(path)
        }
        components.queryItems = [URLQueryItem(name: "download", value: "true")]
        guard let url = components.url else {
            throw WhisperModelInstallerError.invalidRemoteURL(path)
        }
        return url
    }

    private static func downloadFile(
        from source: URL,
        to destination: URL,
        expectedSize: Int,
        session: URLSession
    ) async throws {
        var lastError: Error?
        for attempt in 1...3 {
            do {
                var request = URLRequest(url: source)
                request.timeoutInterval = 120
                let (temporaryFile, response) = try await session.download(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode)
                else {
                    throw WhisperModelInstallerError.invalidFileResponse(source)
                }
                guard hasExpectedSize(temporaryFile, expectedSize: expectedSize) else {
                    throw WhisperModelInstallerError.incorrectFileSize(source)
                }

                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if FileManager.default.fileExists(atPath: destination.path) {
                    _ = try FileManager.default.replaceItemAt(
                        destination,
                        withItemAt: temporaryFile
                    )
                } else {
                    try FileManager.default.moveItem(at: temporaryFile, to: destination)
                }
                return
            } catch {
                lastError = error
                if attempt < 3 {
                    try await Task.sleep(for: .seconds(attempt))
                }
            }
        }
        throw lastError ?? WhisperModelInstallerError.invalidFileResponse(source)
    }

    private static func hasExpectedSize(_ file: URL, expectedSize: Int) -> Bool {
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
            return false
        }
        return values.isRegularFile == true && values.fileSize == expectedSize
    }

    private struct ModelTreeEntry: Decodable {
        let type: String
        let size: Int
        let path: String
    }

    private struct ModelFile: Sendable {
        let path: String
        let size: Int
    }
}

nonisolated enum WhisperModelInstallerError: LocalizedError {
    case incompleteDownload(URL)
    case emptyManifest(String)
    case invalidRemoteURL(String)
    case invalidManifestResponse
    case invalidFileResponse(URL)
    case incorrectFileSize(URL)

    var errorDescription: String? {
        switch self {
        case .incompleteDownload(let folder):
            return "The downloaded WhisperKit model is incomplete at \(folder.path)."
        case .emptyManifest(let model):
            return "Hugging Face returned no files for \(model)."
        case .invalidRemoteURL(let path):
            return "Could not build the model URL for \(path)."
        case .invalidManifestResponse:
            return "Hugging Face returned an invalid model manifest response."
        case .invalidFileResponse(let url):
            return "Hugging Face returned an invalid response for \(url.lastPathComponent)."
        case .incorrectFileSize(let url):
            return "The downloaded file has the wrong size: \(url.lastPathComponent)."
        }
    }
}
