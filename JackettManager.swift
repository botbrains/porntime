
import Foundation
import ObjectMapper
import MediaPlayer.MPMediaItem
import PopcornKit

// MARK: - Jackett Result Model

/// A single torrent result from the Jackett indexer feed.
/// Conforms to `Media` so it slots directly into the existing CollectionViewController pipeline.
public struct JackettMedia: Media, Equatable, Hashable {
    
    public let title: String
    public let id: String
    public var tmdbId: Int?
    public let slug: String
    public let summary: String
    
    public var smallBackgroundImage: String? { return nil }
    public var mediumBackgroundImage: String? { return nil }
    public var largeBackgroundImage: String?
    public var smallCoverImage: String? { return posterURL }
    public var mediumCoverImage: String? { return posterURL }
    public var largeCoverImage: String?
    
    /// Poster/thumbnail URL extracted from the Jackett feed, if available.
    public var posterURL: String?
    
    public var subtitles = Dictionary<String, [Subtitle]>()
    public var torrents = [Torrent]()
    
    public var isWatched: Bool {
        get { return false }
        set {}
    }
    
    public var isAddedToWatchlist: Bool {
        get { return false }
        set {}
    }
    
    /// The raw magnet link or .torrent URL from the Jackett feed.
    public let magnetLink: String
    public let seeders: Int
    public let leechers: Int
    public let sizeBytes: Int64
    public let publishDate: Date?
    
    // MARK: - Mappable conformance (required by Media protocol)
    
    public init?(map: Map) {
        return nil // We don't construct these from ObjectMapper JSON.
    }
    
    public mutating func mapping(map: Map) {
        // No-op — we build these from XML, not ObjectMapper.
    }
    
    // MARK: - MPMediaItem dictionary conformance (required by Media protocol)
    
    public var mediaItemDictionary: [String: Any] {
        return [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyMediaType: NSNumber(value: MPMediaType.movie.rawValue),
            MPMediaItemPropertyPersistentID: id,
            MPMediaItemPropertyArtwork: "",
            MPMediaItemPropertyBackgroundArtwork: "",
            MPMediaItemPropertySummary: summary
        ]
    }
    
    public init?(_ mediaItemDictionary: [String: Any]) {
        guard
            let id = mediaItemDictionary[MPMediaItemPropertyPersistentID] as? String,
            let title = mediaItemDictionary[MPMediaItemPropertyTitle] as? String,
            let summary = mediaItemDictionary[MPMediaItemPropertySummary] as? String
        else {
            return nil
        }
        self.init(title: title, id: id, magnetLink: "", seeders: 0, leechers: 0, sizeBytes: 0, summary: summary)
    }
    
    // MARK: - Primary initializer
    
    public init(title: String,
                id: String,
                magnetLink: String,
                seeders: Int,
                leechers: Int,
                sizeBytes: Int64,
                publishDate: Date? = nil,
                summary: String = "",
                posterURL: String? = nil) {
        self.title = title
        self.id = id
        self.slug = title.slugged
        self.magnetLink = magnetLink
        self.seeders = seeders
        self.leechers = leechers
        self.sizeBytes = sizeBytes
        self.publishDate = publishDate
        self.summary = summary.isEmpty ? JackettMedia.buildSummary(seeders: seeders, leechers: leechers, size: sizeBytes) : summary
        self.posterURL = posterURL
        
        // Build the single torrent entry that the playback pipeline needs.
        let quality = JackettMedia.extractQuality(from: title)
        let health: Health = seeders > 10 ? .excellent : (seeders > 3 ? .good : .bad)
        let torrent = Torrent(health: health,
                              url: magnetLink,
                              quality: quality,
                              seeds: seeders,
                              peers: leechers,
                              size: JackettMedia.formatSize(sizeBytes))
        self.torrents = [torrent]
    }
    
    // MARK: - Hashable / Equatable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: JackettMedia, rhs: JackettMedia) -> Bool {
        return lhs.id == rhs.id
    }
    
    // MARK: - Helpers
    
    private static func extractQuality(from title: String) -> String {
        for p in ["2160p", "1080p", "720p", "480p"] {
            if title.localizedCaseInsensitiveContains(p) { return p }
        }
        return "Unknown"
    }
    
    static func formatSize(_ bytes: Int64) -> String? {
        guard bytes > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private static func buildSummary(seeders: Int, leechers: Int, size: Int64) -> String {
        var parts = [String]()
        parts.append("\(seeders) seed\(seeders == 1 ? "" : "s")")
        parts.append("\(leechers) peer\(leechers == 1 ? "" : "s")")
        if let sizeStr = formatSize(size) {
            parts.append(sizeStr)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Jackett Torznab XML Parser

final class JackettXMLParser: NSObject, XMLParserDelegate {
    
    private let data: Data
    private var results: [JackettMedia] = []
    
    // Parsing state
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentSeeders = 0
    private var currentLeechers = 0
    private var currentSize: Int64 = 0
    private var currentPubDate = ""
    private var currentDescription = ""
    private var currentPosterURL = ""
    private var inItem = false
    
    init(data: Data) {
        self.data = data
    }
    
    func parse() -> [JackettMedia] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return results
    }
    
    // MARK: - XMLParserDelegate
    
    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        
        if elementName == "item" {
            inItem = true
            currentTitle = ""
            currentLink = ""
            currentSeeders = 0
            currentLeechers = 0
            currentSize = 0
            currentPubDate = ""
            currentDescription = ""
            currentPosterURL = ""
        }
        
        // Torznab extended attributes: <torznab:attr name="seeders" value="42"/>
        let isAttr = elementName == "torznab:attr" || elementName == "attr"
        if isAttr, let name = attributes["name"], let value = attributes["value"] {
            switch name {
            case "seeders":  currentSeeders = Int(value) ?? 0
            case "peers":    currentLeechers = Int(value) ?? 0
            case "size":     currentSize = Int64(value) ?? 0
            case "magneturl":
                // Some indexers put the magnet in a torznab attr instead of <link>
                if !value.isEmpty { currentLink = value }
            case "coverurl", "poster", "banner", "coverimage":
                // Some indexers provide cover art via Torznab attributes
                if !value.isEmpty && currentPosterURL.isEmpty { currentPosterURL = value }
            default: break
            }
        }
        
        // <enclosure> tag may carry the .torrent URL + length
        if elementName == "enclosure" {
            if let url = attributes["url"], currentLink.isEmpty {
                currentLink = url
            }
            if let length = attributes["length"], let len = Int64(length), currentSize == 0 {
                currentSize = len
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch currentElement {
        case "title":       currentTitle += string
        case "link":        currentLink += string
        case "pubDate":     currentPubDate += string
        case "description": currentDescription += string
        default: break
        }
    }
    
    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?) {
        guard elementName == "item" else { return }
        inItem = false
        
        let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let link  = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !title.isEmpty, !link.isEmpty else { return }
        
        // Use a stable ID derived from the magnet link / torrent URL
        let id = String(link.hashValue)
        
        // Resolve poster URL: prefer Torznab attribute, fall back to <img> in description HTML
        var poster: String? = currentPosterURL.isEmpty ? nil : currentPosterURL
        if poster == nil {
            poster = JackettXMLParser.extractImageURL(from: currentDescription)
        }
        
        let media = JackettMedia(
            title: title,
            id: id,
            magnetLink: link,
            seeders: currentSeeders,
            leechers: currentLeechers,
            sizeBytes: currentSize,
            publishDate: JackettXMLParser.parseDate(currentPubDate),
            posterURL: poster
        )
        results.append(media)
    }
    
    /// Extracts the first image URL from an HTML string (typically a `<description>` field).
    /// Handles both `<img src="...">` tags and bare image URLs.
    private static func extractImageURL(from html: String) -> String? {
        // Try <img src="..."> or <img src='...'>
        let imgPattern = "<img[^>]+src\\s*=\\s*[\"']([^\"']+)[\"']"
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            let url = String(html[range])
            if url.hasPrefix("http") { return url }
        }
        
        // Try bare image URL in the text
        let urlPattern = "(https?://[^\\s<>\"']+\\.(?:jpg|jpeg|png|gif|webp))"
        if let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }
        
        return nil
    }
    
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        // Standard RSS / Torznab date format
        fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return fmt
    }()
    
    private static func parseDate(_ string: String) -> Date? {
        return dateFormatter.date(from: string.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Jackett Network Manager

class JackettManager {
    
    static let shared = JackettManager()
    
    /// The full Torznab API endpoint for your Jackett indexer.
    let feedURL = "http://ec2-3-107-243-189.ap-southeast-2.compute.amazonaws.com:9117/api/v2.0/indexers/gay-torrents/results/torznab/api"
    let apiKey  = "2ulqmhijd4c15x3hd3ftm4zmmbnlvkg0"
    
    private init() {}
    
    /// Fetches the feed. Pass a search query (empty string = browse recent).
    /// Pagination is handled via `offset` (page * limit).
    func load(page: Int,
              query: String = "",
              limit: Int = 50,
              completion: @escaping ([JackettMedia]?, NSError?) -> Void) {
        
        var components = URLComponents(string: feedURL)!
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "t",      value: "search"),
            URLQueryItem(name: "limit",  value: String(limit)),
            URLQueryItem(name: "offset", value: String((page - 1) * limit)),
            URLQueryItem(name: "q",      value: query)
        ]
        components.queryItems = queryItems
        
        guard let url = components.url else {
            completion(nil, NSError(domain: "JackettManager", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Invalid Jackett URL."]))
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(nil, error as NSError) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(nil, NSError(domain: "JackettManager", code: -2,
                                            userInfo: [NSLocalizedDescriptionKey: "No data received from Jackett."]))
                }
                return
            }
            
            let results = JackettXMLParser(data: data).parse()
            DispatchQueue.main.async { completion(results, nil) }
        }
        task.resume()
    }
}
