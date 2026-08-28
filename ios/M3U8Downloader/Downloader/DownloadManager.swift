import Foundation

@MainActor
final class DownloadManager: ObservableObject {
    @Published var tasks: [DownloadTask] = []
    
    private let maxConcurrent = 3
    private var runningCount = 0
    private var downloadJobs: [UUID: Task<Void, Never>] = [:]
    private var segmentData: [UUID: [Int: Data]] = [:]
    
    func addDownload(resourceName: String, m3u8URL: String) {
        let task = DownloadTask(resourceName: resourceName, m3u8URL: m3u8URL)
        tasks.append(task)
        scheduleNext()
    }
    
    func pause(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = .paused
        downloadJobs[id]?.cancel()
        downloadJobs[id] = nil
        runningCount -= 1
        scheduleNext()
    }
    
    func resume(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = .pending
        scheduleNext()
    }
    
    func cancel(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = .cancelled
        downloadJobs[id]?.cancel()
        downloadJobs[id] = nil
        segmentData[id] = nil
        runningCount -= 1
        scheduleNext()
    }
    
    func retry(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = .pending
        tasks[index].progress = 0
        tasks[index].errorMessage = nil
        tasks[index].downloadedSegmentCount = 0
        scheduleNext()
    }
    
    private func scheduleNext() {
        let pending = tasks.filter { $0.status == .pending }
        for task in pending {
            guard runningCount < maxConcurrent else { break }
            startDownload(task.id)
        }
    }
    
    private func startDownload(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = .downloading
        runningCount += 1
        
        let task = tasks[index]
        downloadJobs[id] = Task { [weak self] in
            await self?.performDownload(id)
        }
    }
    
    private func performDownload(_ id: UUID) async {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let task = tasks[index]
        
        do {
            guard let url = URL(string: task.m3u8URL) else {
                throw M3U8ParserError.invalidURL
            }
            
            // 1. Download m3u8 playlist
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let content = String(data: data, encoding: .utf8) else {
                throw M3U8ParserError.invalidContent
            }
            
            let playlist = try M3U8Parser.parse(content, baseURL: url)
            let segments: [M3U8Segment]
            
            switch playlist {
            case .master(let variants):
                guard let best = variants.max(by: { $0.bandwidth < $1.bandwidth }),
                      let variantURL = URL(string: best.url) else {
                    throw M3U8ParserError.invalidContent
                }
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
            
            // 2. Download segments
            tasks[index].totalSegmentCount = segments.count
            let startIndex = tasks[index].downloadedSegmentCount
            
            for segmentIndex in startIndex..<segments.count {
                try Task.checkCancellation()
                
                guard let segURL = URL(string: segments[segmentIndex].url) else { continue }
                let (segData, _) = try await URLSession.shared.data(from: segURL)
                
                if segmentData[id] == nil {
                    segmentData[id] = [:]
                }
                segmentData[id]?[segmentIndex] = segData
                
                tasks[index].downloadedSegmentCount = segmentIndex + 1
                tasks[index].progress = Double(segmentIndex + 1) / Double(segments.count)
            }
            
            // 3. Merge segments
            let mergedData = mergeSegments(segmentData[id] ?? [:], totalCount: segments.count)
            let outputURL = try saveMergedFile(mergedData, filename: task.resourceName)
            
            tasks[index].status = .completed
            tasks[index].outputFileName = outputURL.lastPathComponent
            segmentData[id] = nil
            
        } catch is CancellationError {
            // Task cancelled, keep current progress for resume
        } catch {
            tasks[index].status = .failed
            tasks[index].errorMessage = error.localizedDescription
        }
        
        runningCount -= 1
        downloadJobs[id] = nil
        scheduleNext()
    }
    
    private func mergeSegments(_ data: [Int: Data], totalCount: Int) -> Data {
        var merged = Data()
        for i in 0..<totalCount {
            if let segmentData = data[i] {
                merged.append(segmentData)
            }
        }
        return merged
    }
    
    private func saveMergedFile(_ data: Data, filename: String) throws -> URL {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsDir = documentsURL.appendingPathComponent("Downloads", isDirectory: true)
        try fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        
        let safeName = filename.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let outputURL = downloadsDir.appendingPathComponent(safeName + ".ts")
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        try data.write(to: outputURL)
        return outputURL
    }
}
