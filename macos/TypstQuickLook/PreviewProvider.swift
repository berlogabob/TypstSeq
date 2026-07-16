import Foundation
import QuickLookUI
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let sourceURL = request.fileURL
        let root = VaultLookup.resolveRoot(for: sourceURL)

        guard let markup = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            return errorReply(title: "Could not read file", message: sourceURL.path)
        }

        let files = VaultLookup.readAllFiles(root: root)

        do {
            let pdf = try compile(markup: markup, files: files)
            let pdfURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("pdf")
            try pdf.write(to: pdfURL)
            return QLPreviewReply(fileURL: pdfURL)
        } catch let error as CompileError {
            return errorReply(title: "Typst compilation failed", message: error.message)
        }
    }

    // MARK: - Rust bridge call

    private struct CompileError: Error {
        let message: String
    }

    /// Builds the C `TypstQlFile` array (each file registered under both its
    /// relative path and a leading-`/` variant, matching
    /// `lib/report.dart`'s `exportReportPdfStorage`) and calls
    /// `typst_ql_compile_pdf`.
    private func compile(markup: String, files: [(path: String, bytes: Data)]) throws -> Data {
        var cPaths: [UnsafeMutablePointer<CChar>] = []
        var cBuffers: [UnsafeMutablePointer<UInt8>] = []
        defer {
            cPaths.forEach { free($0) }
            cBuffers.forEach { $0.deallocate() }
        }

        var entries: [TypstQlFile] = []
        entries.reserveCapacity(files.count * 2)
        for file in files {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: max(file.bytes.count, 1))
            file.bytes.copyBytes(to: buffer, count: file.bytes.count)
            cBuffers.append(buffer)

            let relativePath = strdup(file.path)!
            let absolutePath = strdup("/" + file.path)!
            cPaths.append(relativePath)
            cPaths.append(absolutePath)

            entries.append(TypstQlFile(path: relativePath, bytes: buffer, bytes_len: file.bytes.count))
            entries.append(TypstQlFile(path: absolutePath, bytes: buffer, bytes_len: file.bytes.count))
        }

        var outPdf: UnsafeMutablePointer<UInt8>?
        var outPdfLen: Int = 0
        var outError: UnsafeMutablePointer<CChar>?

        let status = markup.withCString { markupPtr in
            entries.withUnsafeBufferPointer { entriesPtr in
                typst_ql_compile_pdf(
                    markupPtr,
                    entriesPtr.baseAddress,
                    entriesPtr.count,
                    &outPdf,
                    &outPdfLen,
                    &outError
                )
            }
        }

        if status == 0, let outPdf {
            let data = Data(bytes: outPdf, count: outPdfLen)
            typst_ql_free_bytes(outPdf, outPdfLen)
            return data
        }

        let message = outError.map { String(cString: $0) } ?? "Unknown Typst compilation error."
        if let outError {
            typst_ql_free_string(outError)
        }
        throw CompileError(message: message)
    }

    // MARK: - Error rendering

    private func errorReply(title: String, message: String) -> QLPreviewReply {
        let escapedTitle = escapeHTML(title)
        let escapedMessage = escapeHTML(message)
        let html = """
            <html><head><meta charset="utf-8"><style>
            body { font: -apple-system-body; margin: 2em; color: #222; }
            h1 { font-size: 1.1em; color: #b00020; }
            pre { white-space: pre-wrap; font: -apple-system-caption1; }
            </style></head><body>
            <h1>\(escapedTitle)</h1>
            <pre>\(escapedMessage)</pre>
            </body></html>
            """
        let data = Data(html.utf8)
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 640, height: 360)) { _ in
            data
        }
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
