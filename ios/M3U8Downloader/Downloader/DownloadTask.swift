import Foundation

enum DownloadStatus: String, Codable {
    case pending
    case downloading
    case paused
    case completed
    case failed
    case cancelled
}

struct DownloadTask: Identifiable, Codable, Hashable {
    let id: UUID
    let resourceName: String
    let m3u8URL: String
    var status: DownloadStatus
    var progress: Double
    var outputFileName: String?
    var errorMessage: String?
    var downloadedSegmentCount: Int
    var totalSegmentCount: Int
    
    init(resourceName: String, m3u8URL: String) {
        self.id = UUID()
        self.resourceName = resourceName
        self.m3u8URL = m3u8URL
        self.status = .pending
        self.progress = 0
        self.outputFileName = nil
        self.errorMessage = nil
        self.downloadedSegmentCount = 0
        self.totalSegmentCount = 0
    }
    
    var statusText: String {
        switch status {
        case .pending: return "等待中"
        case .downloading: return "下载中 \(Int(progress * 100))% (\(downloadedSegmentCount)/\(totalSegmentCount))"
        case .paused: return "已暂停 (\(downloadedSegmentCount)/\(totalSegmentCount))"
        case .completed: return "已完成"
        case .failed: return "失败: \(errorMessage ?? "未知错误")"
        case .cancelled: return "已取消"
        }
    }
}
