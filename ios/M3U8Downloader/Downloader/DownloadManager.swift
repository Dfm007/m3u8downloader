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

    private func performDownload(_ id: UUID) async {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let task = tasks[index]

        do {
            guard let url = URL(string: task.m3u8URL) else {
                throw M3U8ParserError.invalidURL
            }

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

            tasks[index].totalSegmentCount = segments.count
            let startIndex = tasks[index].downloadedSegmentCount

            // key 缓存
            var cachedKey: [UInt8]?
            var cachedKeyURI: String?

            for segmentIndex in startIndex..<segments.count {
                try Task.checkCancellation()

                guard let segURL = URL(string: segments[segmentIndex].url) else { continue }

                let segData: Data
                if let range = segments[segmentIndex].byteRange {
                    var request = URLRequest(url: segURL)
                    let start = range.offset
                    let end = range.offset + range.length - 1
                    request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                    let (rangeData, _) = try await URLSession.shared.data(for: request)
                    segData = rangeData
                } else {
                    let (segDataFull, _) = try await URLSession.shared.data(from: segURL)
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
                        let (kData, _) = try await URLSession.shared.data(from: keyURL)
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

                tasks[index].downloadedSegmentCount = segmentIndex + 1
                tasks[index].progress = Double(segmentIndex + 1) / Double(segments.count)
            }

            let mergedData = mergeSegments(segmentData[id] ?? [:], totalCount: segments.count)
            let outputURL = try saveMergedFile(mergedData, filename: task.resourceName)

            tasks[index].status = .completed
            tasks[index].outputFileName = outputURL.lastPathComponent
            segmentData[id] = nil

        } catch is CancellationError {
            // 被取消
        } catch {
            tasks[index].status = .failed
            tasks[index].errorMessage = error.localizedDescription
        }

        downloadJobs[id] = nil
        scheduleNext()
    }

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
        // 无 IV 时用 sequence number 按 HLS 规范生成
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