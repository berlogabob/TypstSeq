import Foundation

/// Mirrors the subset of `lib/vault_registry.dart`'s `vaults.json` schema this
/// extension needs: local-path vault roots only (the only kind that exists on
/// macOS).
private struct VaultsFile: Decodable {
    struct Vault: Decodable {
        struct Storage: Decodable {
            let kind: String
            let path: String?
        }
        let storage: Storage
    }
    let vaults: [Vault]
}

enum VaultLookup {
    /// Finds the vault root directory containing `fileURL`, by reading the
    /// same `~/Documents/vaults.json` the host app writes
    /// (`VaultRegistry.save()`). Falls back to the file's own directory when
    /// no registered vault contains it (single-file preview: sibling
    /// `#include`/`#image` references outside that directory won't resolve).
    static func resolveRoot(for fileURL: URL) -> URL {
        let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first
        let vaultsFile = documents?.appendingPathComponent("vaults.json")

        let filePath = fileURL.resolvingSymlinksInPath().path
        var bestMatch: String?

        if let vaultsFile,
            let data = try? Data(contentsOf: vaultsFile),
            let parsed = try? JSONDecoder().decode(VaultsFile.self, from: data)
        {
            for vault in parsed.vaults where vault.storage.kind == "local-path" {
                guard let path = vault.storage.path, !path.isEmpty else { continue }
                let root = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                guard filePath == root || filePath.hasPrefix(root + "/") else { continue }
                if bestMatch == nil || root.count > bestMatch!.count {
                    bestMatch = root
                }
            }
        }

        if let bestMatch {
            return URL(fileURLWithPath: bestMatch, isDirectory: true)
        }
        return fileURL.deletingLastPathComponent()
    }

    /// Reads every file under `root` into `[relativePath: bytes]`, mirroring
    /// `lib/report.dart`'s `exportReportPdfStorage`: skip `_index/`,
    /// `.tylog/` and `.tmp` files, brute-force include everything else
    /// (vendored `@preview/...` packages under `_system/packages/` come along
    /// for free — no separate package resolution needed).
    static func readAllFiles(root: URL) -> [(path: String, bytes: Data)] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        var files: [(path: String, bytes: Data)] = []
        let rootPath = root.path

        for case let url as URL in enumerator {
            guard
                let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey])
                    .isDirectory,
                !isDirectory
            else { continue }

            var relative = url.path
            if relative.hasPrefix(rootPath + "/") {
                relative = String(relative.dropFirst(rootPath.count + 1))
            }
            if relative.hasPrefix("_index/") || relative.hasPrefix(".tylog/")
                || relative.hasSuffix(".tmp")
            {
                continue
            }
            guard let bytes = try? Data(contentsOf: url) else { continue }
            files.append((path: relative, bytes: bytes))
        }
        return files
    }
}
