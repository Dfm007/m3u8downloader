import Foundation

@MainActor
final class M3U8Downloader: ObservableObject {
    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var statusText = ""
    @Published var downloadedFiles: [URL] = []
    
    private var downloadTask: Task<Void, Error>?
    
    func download(m3u8URL: URL, filename: String) {
        guard !isDownloading else { return }
        downloadTask = Task {
            isDownloading = true
            progress = 0
            statusText = "Fetching m3u8..."
            
            do {
                let (data, _) = try await URLSession.shared.data(from: m3u8URL)
                guard let content = String(data: data, encoding: .utf8) else {
                    throw M3U8ParserError.invalidContent
                }
                
                let playlist = try M3U8Parser.parse(content, baseURL: m3u8URL)
                let segments: [M3U8Segment]
                
                switch playlist {
                case .master(let variants):
                    statusText = "Master playlist detected, selecting highest bandwidth..."
                    guard let best = variants.max(by: { $0.bandwidth < $1.bandwidth }) else {
                        throw M3U8ParserError.invalidContent
                    }
                    let variantURL = URL(string: best.url) ?? m3u8URL
                    let (vData, _) = try await URLSession.shared.data(from: variantURL)
                    guard let vContent = String(data: vData, encoding: .utf8) else {
                        throw M3U8ParserError.invalidContent
                    }
                    let mediaPlaylist = try M3U8Parser.parse(vContent, baseURL: variantURL)
                    guard case .media(let segs) = mediaPlaylist else {
                        throw M3U8ParserError.invalidContent
                    }
                    segments = segs
                case .media(let segs):
                    segments = segs
                }
                
                statusText = "Downloading \(segments.count) segments..."
                let outputURL = try await downloadSegments(segments, filename: filename)
                downloadedFiles.append(outputURL)
                statusText = "Download complete"
            } catch {
                statusText = "Error: \(error.localizedDescription)"
                throw error
            }
            
            isDownloading = false
        }
    }
    
    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        statusText = "Cancelled"
    }
    
    private func downloadSegments(_ segments: [M3U8Segment], filename: String) async throws -> URL {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsDir = documentsURL.appendingPathComponent("Downloads", isDirectory: true)
        try fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        
        let tempDir = downloadsDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }
        
        let outputURL = downloadsDir.appendingPathComponent(filename.hasSuffix(".ts") ? filename : filename + ".ts")
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        fileManager.createFile(atPath: outputURL.path, contents: nil)
        
        let fileHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? fileHandle.close() }
        
        for (index, segment) in segments.enumerated() {
            try Task.checkCancellation()
            guard let segURL = URL(string: segment.url) else { continue }
            
            let (segData, _) = try await URLSession.shared.data(from: segURL)
            try fileHandle.write(contentsOf: segData)
            
            progress = Double(index + 1) / Double(segments.count)
            statusText = "Downloading segment \(index + 1)/\(segments.count)"
        }
        
        return outputURL
    }
}
