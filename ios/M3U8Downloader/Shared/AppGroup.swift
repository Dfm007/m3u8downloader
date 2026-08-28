import Foundation

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

enum SharedStorage {
    static let detectedResourcesKey = "detectedM3U8Resources"
    
    static func saveDetectedResources(_ items: [[String: String]]) {
        UserDefaults.standard.set(items, forKey: detectedResourcesKey)
    }
    
    static func loadDetectedResources() -> [DetectedResource] {
        guard let items = UserDefaults.standard.array(forKey: detectedResourcesKey) as? [[String: String]] else {
            return []
        }
        return items.compactMap { dict in
            guard let url = dict["url"], let name = dict["name"] else { return nil }
            return DetectedResource(name: name, url: url)
        }
    }
    
    static func clearDetectedResources() {
        UserDefaults.standard.removeObject(forKey: detectedResourcesKey)
    }
}
