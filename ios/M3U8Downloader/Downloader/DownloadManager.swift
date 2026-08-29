import Foundation
import CryptoSwift

@MainActor
final class DownloadManager: ObservableObject {
    @Published var tasks: [DownloadTask] = []

    private let maxConcurrent = 3
    private var downloadJobs: [UUID: Task<Void, Never>] = [:]
    private var segmentData: [UUID: [Int: Data]] = [:]

    var runningCount: Int {
        downloadJobs.count
    }

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
        scheduleNext()
    }

    func retry(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = .pending
        tasks[index].progress = 0
        tasks[index].errorMessage = nil
        tasks[index].downloadedSegmentCount = 0
        segmentData[id] = nil
        scheduleNext()
    }

    func delete(_ id: UUID) {
        downloadJobs[id]?.cancel()
        downloadJobs[id] = nil
        segmentData[id] = nil

        if let index = tasks.firstIndex(where: { $0.id == id }),
           tasks[index].status == .completed,
           let fileName = tasks[index].outputFileName {
            let fileManager = FileManager.default
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsURL.appendingPathComponent("Downloads").appendingPathComponent(fileName)
            try? fileManager.removeItem(at: fileURL)
        }

        tasks.removeAll { $0.id == id }
        scheduleNext()
    }

    // MARK: - 请求构造（防 Cloudflare 拦截）

    private func makeRequest(url: URL, referer: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        if let referer = referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        return request
    }

    // 从 m3u8 URL 提取站点根地址作为 Referer
    private func refererForURL(_ url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        return "\(scheme)://\(host)/"
    }

    // MARK: - 调度

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

        downloadJobs[id] = Task { [weak self] in
            await self?.performDownload(id)
        }
    }

    // MARK: - 下载主流程

    private func performDownload(_ id: UUID) async {
        func updateTask(_ update: (inout DownloadTask) -> Void) {
            guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
            update(&tasks[idx])
        }

        guard let task = tasks.first(where: { $0.id == id }) else { return }

        do {
            guard let url = URL(string: task.m3u8URL) else {
                throw M3U8ParserError.invalidURL
            }

            let referer = refererForURL(url)

            // 下载 m3u8 playlist
            let (data, _) = try await URLSession.shared.data(for: makeRequest(url: url, referer: referer))
            guard let content = String(data: data, encoding: .utf8) else {
                throw M3U8ParserError.invalidContent
            }

            // 如果返回的是 HTML（Cloudflare 拦截），直接报错
            if content.hasPrefix("<!DOCTYPE") || content.hasPrefix("<html") {
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
                let (vData, _) = try await URLSession.shared.data(for: makeRequest(url: variantURL, referer: referer))
                guard let vContent = String(data: vData, encoding: .utf8) else {
                    throw M3U8ParserError.invalidContent
                }
                if vContent.hasPrefix("<!DOCTYPE") || vContent.hasPrefix("<html") {
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

            updateTask { $0.totalSegmentCount = segments.count }

            guard let currentTask = tasks.first(where: { $0.id == id }) else { return }
            let startIndex = currentTask.downloadedSegmentCount

            var cachedKey: [UInt8]?
            var cachedKeyURI: String?

            for segmentIndex in startIndex..<segments.count {
                try Task.checkCancellation()

                guard tasks.contains(where: { $0.id == id }) else { return }

                guard let segURL = URL(string: segments[segmentIndex].url) else { continue }

                let segData: Data
                if let range = segments[segmentIndex].byteRange {
                    var request = makeRequest(url: segURL, referer: referer)
                    let start = range.offset
                    let end = range.offset + range.length - 1
                    request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                    let (rangeData, _) = try await URLSession.shared.data(for: request)
                    segData = rangeData
                } else {
                    let (segDataFull, _) = try await URLSession.shared.data(for: makeRequest(url: segURL, referer: referer))
                    segData = segDataFull
                }

                var finalData = segData

                // AES-128-CBC 解密
                if let keyURI = segments[segmentIndex].keyURI {
                    let keyBytes: [UInt8]
                    if cachedKeyURI == keyURI, let cached = cachedKey {
                        keyBytes = cached
                    } else {
                        guard let keyURL = URL(string: keyURI) else { continue }
                        let (kData, _) = try await URLSession.shared.data(for: makeRequest(url: keyURL, referer: referer))
                        keyBytes = [UInt8](kData)
                        cachedKey = keyBytes
                        cachedKeyURI = keyURI
                    }

                    let ivBytes = getIVBytes(for: segments[segmentIndex], sequenceNumber: segmentIndex)

                    do {
                        let aes = try AES(key: keyBytes, blockMode: CBC(iv: ivBytes), padding: .pkcs7)
                        let decrypted = try aes.decrypt([UInt8](segData))
                        finalData = Data(decrypted)
                    } catch {
                        // 解密失败保留原始数据
                    }
                }

                if segmentData[id] == nil {
                    segmentData[id] = [:]
                }
                segmentData[id]?[segmentIndex] = finalData

                updateTask {
                    $0.downloadedSegmentCount = segmentIndex + 1
                    $0.progress = Double(segmentIndex + 1) / Double(segments.count)
                }
            }

            let mergedData = mergeSegments(segmentData[id] ?? [:], totalCount: segments.count)
            let outputURL = try saveMergedFile(mergedData, filename: task.resourceName)

            updateTask {
                $0.status = .completed
                $0.outputFileName = outputURL.lastPathComponent
            }
            segmentData[id] = nil

        } catch is CancellationError {
            // 被取消，什么都不做
        } catch {
            updateTask {
                $0.status = .failed
                $0.errorMessage = error.localizedDescription
            }
        }

        downloadJobs[id] = nil
        scheduleNext()
    }

    // MARK: - 工具方法

    private func getIVBytes(for segment: M3U8Segment, sequenceNumber: Int) -> [UInt8] {
        if let ivHex = segment.keyIV {
            let cleaned = ivHex.replacingOccurrences(of: "0x", with: "")
            var bytes = [UInt8]()
            var index = 0
            while index < cleaned.count {
                let start = cleaned.index(cleaned.startIndex, offsetBy: index)
                let end = cleaned.index(start, offsetBy: 2)
                let byteStr = String(cleaned[start..<end])
                bytes.append(UInt8(byteStr, radix: 16) ?? 0)
                index += 2
            }
            return bytes
        }
        var iv = [UInt8](repeating: 0, count: 16)
        let seq = UInt32(sequenceNumber)
        iv[12] = UInt8((seq >> 24) & 0xFF)
        iv[13] = UInt8((seq >> 16) & 0xFF)
        iv[14] = UInt8((seq >> 8) & 0xFF)
        iv[15] = UInt8(seq & 0xFF)
        return iv
    }

    private func mergeSegments(_ dict: [Int: Data], totalCount: Int) -> Data {
        var result = Data()
        for i in 0..<totalCount {
            if let data = dict[i] {
                result.append(data)
            }
        }
        return result
    }

    private func saveMergedFile(_ data: Data, filename: String) throws -> URL {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsURL = documentsURL.appendingPathComponent("Downloads", isDirectory: true)

        if !fileManager.fileExists(atPath: downloadsURL.path) {
            try fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        }

        let safeFilename = filename.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let fileURL = downloadsURL.appendingPathComponent(safeFilename + ".ts")
        try data.write(to: fileURL)
        return fileURL
    }
}