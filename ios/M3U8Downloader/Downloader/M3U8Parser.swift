import Foundation

struct M3U8Segment {
    let duration: Double
    let url: String
    let keyURI: String?
    let keyIV: String?
    let byteRange: (length: Int, offset: Int)?
}

struct M3U8Variant {
    let bandwidth: Int
    let resolution: String?
    let url: String
}

enum M3U8Playlist {
    case master(variants: [M3U8Variant])
    case media(segments: [M3U8Segment])
}

enum M3U8ParserError: Error {
    case invalidContent
    case invalidURL
}

final class M3U8Parser {

    static func parse(_ content: String, baseURL: URL) throws -> M3U8Playlist {
        let lines = content.components(separatedBy: .newlines)
        var variants: [M3U8Variant] = []
        var segments: [M3U8Segment] = []
        var currentDuration: Double = 0
        var currentKeyURI: String?
        var currentKeyIV: String?
        var currentByteRange: (length: Int, offset: Int)?
        var lastByteRangeEnd: Int = 0   // 关键：记录上一个 BYTERANGE 的结束位置

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#EXT-X-STREAM-INF") {
                let bandwidth = extractAttribute(trimmed, name: "BANDWIDTH").flatMap(Int.init) ?? 0
                let resolution = extractAttribute(trimmed, name: "RESOLUTION")
                variants.append(M3U8Variant(bandwidth: bandwidth, resolution: resolution, url: ""))
            } else if trimmed.hasPrefix("#EXT-X-KEY") {
                let method = extractAttribute(trimmed, name: "METHOD")
                if method == "AES-128" {
                    let keyURI = extractAttribute(trimmed, name: "URI")
                    if let keyURI = keyURI {
                        currentKeyURI = resolveURL(keyURI, relativeTo: baseURL).absoluteString
                    }
                    currentKeyIV = extractAttribute(trimmed, name: "IV")
                } else if method == "NONE" {
                    currentKeyURI = nil
                    currentKeyIV = nil
                }
            } else if trimmed.hasPrefix("#EXT-X-BYTERANGE") {
                let rangeStr = trimmed.replacingOccurrences(of: "#EXT-X-BYTERANGE:", with: "")
                currentByteRange = parseByteRange(rangeStr, lastEnd: lastByteRangeEnd)
            } else if trimmed.hasPrefix("#EXTINF") {
                let durationStr = trimmed.replacingOccurrences(of: "#EXTINF:", with: "")
                    .components(separatedBy: ",").first ?? "0"
                currentDuration = Double(durationStr) ?? 0
            } else if trimmed.hasPrefix("#") || trimmed.isEmpty {
                continue
            } else {
                let fullURL = resolveURL(trimmed, relativeTo: baseURL)
                if !variants.isEmpty {
                    variants[variants.count - 1] = M3U8Variant(
                        bandwidth: variants[variants.count - 1].bandwidth,
                        resolution: variants[variants.count - 1].resolution,
                        url: fullURL.absoluteString
                    )
                } else {
                    segments.append(M3U8Segment(
                        duration: currentDuration,
                        url: fullURL.absoluteString,
                        keyURI: currentKeyURI,
                        keyIV: currentKeyIV,
                        byteRange: currentByteRange
                    ))
                    // 更新 lastByteRangeEnd 供下一个无 offset 的 BYTERANGE 使用
                    if let range = currentByteRange {
                        lastByteRangeEnd = range.offset + range.length
                    }
                    currentByteRange = nil
                }
            }
        }

        if !variants.isEmpty {
            return .master(variants: variants)
        } else if !segments.isEmpty {
            return .media(segments: segments)
        } else {
            throw M3U8ParserError.invalidContent
        }
    }

    // 新版本：支持 offset 继承
    private static func parseByteRange(_ rangeStr: String, lastEnd: Int) -> (length: Int, offset: Int)? {
        let parts = rangeStr.split(separator: "@", omittingEmptySubsequences: false)
        guard let length = Int(parts[0]) else { return nil }
        if parts.count > 1 {
            // 显式写了 @offset
            let offset = Int(parts[1]) ?? lastEnd
            return (length, offset)
        }
        // 没写 @offset：从上一个 BYTERANGE 结束位置继续
        return (length, lastEnd)
    }

    private static func extractAttribute(_ line: String, name: String) -> String? {
        let pattern = name + "=([^,]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }
        guard let swiftRange = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[swiftRange]).replacingOccurrences(of: "\"", with: "")
    }

    private static func resolveURL(_ urlString: String, relativeTo baseURL: URL) -> URL {
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return URL(string: urlString) ?? baseURL
        }
        if urlString.hasPrefix("/") {
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            components?.path = urlString
            components?.query = nil
            return components?.url ?? baseURL
        }
        return baseURL.deletingLastPathComponent().appendingPathComponent(urlString)
    }
}