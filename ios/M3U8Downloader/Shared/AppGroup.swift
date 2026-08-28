import Foundation

enum AppGroup {
    static let identifier = "group.com.duan.m3u8downloader"
    static let detectedResourcesKey = "detectedM3U8Resources"
    
    static var userDefaults: UserDefaults? {
        return UserDefaults(suiteName: identifier)
    }
    
    static func saveDetectedResources(_ items: [[String: String]]) {
        userDefaults?.set(items, forKey: detectedResourcesKey)
    }
    
    static func loadDetectedResources() -> [DetectedResource] {
        guard let items = userDefaults?.array(forKey: detectedResourcesKey) as? [[String: String]] else {
            return []
        }
        return items.compactMap { dict in
            guard let url = dict["url"], let name = dict["name"] else { return nil }
            return DetectedResource(name: name, url: url)
        }
    }
    
    static func clearDetectedResources() {
        userDefaults?.removeObject(forKey: detectedResourcesKey)
    }
}

struct DetectedResource: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let url: String
    
    init(name: String, url: String) {
        self.id = UUID()
        self.name = name
        self.url = url
    }
}
