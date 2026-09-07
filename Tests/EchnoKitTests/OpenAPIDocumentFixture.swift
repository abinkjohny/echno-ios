import Foundation

/// Reads the vendored OpenAPI document so tests can assert against the contract
/// itself, not just against generated Swift.
///
/// The generated code cannot answer "which HTTP path does this operation hit?" —
/// that lives only in the document. Since the generator's `_1` suffixes follow
/// document order rather than the `/web` split, that question needs asking
/// directly, or a regeneration could quietly point the app at a different
/// controller family.
enum OpenAPIDocumentFixture {

    struct Document {
        private let operationPaths: [String: String]

        init(operationPaths: [String: String]) {
            self.operationPaths = operationPaths
        }

        func path(forOperation id: String) -> String? { operationPaths[id] }
    }

    /// Walks up from this file to the repository root, so the test does not
    /// depend on the working directory `swift test` happens to run in.
    static func load(file: StaticString = #filePath) throws -> Document {
        var directory = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory
                .appending(path: "Sources/EchnoAPI/openapi.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try parse(candidate)
            }
            directory.deleteLastPathComponent()
        }
        throw FixtureError.documentNotFound
    }

    private static func parse(_ url: URL) throws -> Document {
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard
            let root = raw as? [String: Any],
            let paths = root["paths"] as? [String: [String: Any]]
        else { throw FixtureError.malformed }

        var operationPaths: [String: String] = [:]
        for (path, methods) in paths {
            for (method, operation) in methods {
                guard ["get", "post", "put", "patch", "delete"].contains(method),
                      let operation = operation as? [String: Any],
                      let id = operation["operationId"] as? String
                else { continue }
                operationPaths[id] = path
            }
        }
        return Document(operationPaths: operationPaths)
    }

    enum FixtureError: Error { case documentNotFound, malformed }
}
