import SwiftUI

@main
struct M3U8DownloaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    if url.scheme == "m3u8downloader" {
                        if let dataParam = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "data" })?.value,
                           let decodedData = dataParam.removingPercentEncoding,
                           let jsonData = decodedData.data(using: .utf8),
                           let items = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: String]] {
                            AppGroup.saveDetectedResources(items)
                        }
                        NotificationCenter.default.post(name: .newResourcesDetected, object: nil)
                    }
                }
        }
    }
}

extension Notification.Name {
    static let newResourcesDetected = Notification.Name("newResourcesDetected")
}
