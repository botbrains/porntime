import Foundation
import ObjectMapper
import PopcornKit
import MediaPlayer.MPMediaItem

struct JackettConfiguration {
    static let endpointTemplateKey = "jackett.endpointTemplate"

    static let defaultEndpointTemplate = "http://192.168.1.178:9117/api/v2.0/indexers/gay-torrents/results/torznab/api?apikey=18q4a844kahn5ozaes7nowzfs7nbemt3&t=search&cat=&q="

    static var endpointTemplate: String {
        get {
            return defaultEndpointTemplate
        }
        set {
            // Intentionally ignored: endpoint is hardcoded for this build.
        }
    }

    static func resetToDefault() {
        // Intentionally no-op: endpoint is hardcoded for this build.
    }

    static func makeFeedURL(page: Int, query: String, limit: Int) -> URL? {
        var template = endpointTemplate
        if template.contains(" ") {
            template = template.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? template
        }

        guard var components = URLComponents(string: template) else {
            return nil
        }

        var queryDict = [String: String]()
        for item in components.queryItems ?? [] {
            queryDict[item.name] = item.value ?? ""
        }

        queryDict["q"] = query
        queryDict["limit"] = String(limit)
        queryDict["offset"] = String(max((page - 1) * limit, 0))

        components.queryItems = queryDict.map { URLQueryItem(name: $0.key, value: $0.value) }
            .sorted(by: { $0.name < $1.name })

        return components.url
    }
}

class JackettManager {

    static let shared = JackettManager()

    private init() {}

    /// Fetches the feed. Pass a search query (empty string = browse recent).
    /// Pagination is handled via `offset` (page * limit).
    func load(page: Int,
              query: String = "",
              limit: Int = 50,
              completion: @escaping ([JackettMedia]?, NSError?) -> Void) {

        guard let url = JackettConfiguration.makeFeedURL(page: page, query: query, limit: limit) else {
            completion(nil, NSError(domain: "JackettManager", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Invalid Jackett URL."]))
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, _, error in
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

            guard let results = JackettXMLParser(data: data).parse() else {
                DispatchQueue.main.async {
                    completion(nil, NSError(domain: "JackettManager", code: -3,
                                            userInfo: [NSLocalizedDescriptionKey: "Invalid XML response from Jackett."]))
                }
                return
            }

            DispatchQueue.main.async { completion(results, nil) }
        }

        task.resume()
    }
}

// MARK: - JackettMedia

struct JackettMedia: Media, Hashable {
    var title: String
    var id: String
    var tmdbId: Int?
    var slug: String

    var summary: String

    var smallBackgroundImage: String?
    var mediumBackgroundImage: String?
    var largeBackgroundImage: String?

    var posterURL: String?
    var smallCoverImage: String? { posterURL }
    var mediumCoverImage: String? { posterURL }
    var largeCoverImage: String?

    var subtitles: [String: [Subtitle]]
    var torrents: [Torrent]

    var isWatched: Bool
    var isAddedToWatchlist: Bool

    var publishDate: Date?
    var category: String?
    var sizeBytes: Int64

    var mediaItemDictionary: [String: Any] {
        [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyMediaType: NSNumber(value: MPMediaType.movie.rawValue),
            MPMediaItemPropertyPersistentID: id,
            MPMediaItemPropertyArtwork: smallCoverImage ?? "",
            MPMediaItemPropertyBackgroundArtwork: smallBackgroundImage ?? "",
            MPMediaItemPropertySummary: summary
        ]
    }

    init(title: String,
         id: String,
         summary: String,
         torrents: [Torrent],
         posterURL: String? = nil,
         sizeBytes: Int64 = 0,
         publishDate: Date? = nil,
         category: String? = nil) {
        self.title = title
        self.id = id
        self.tmdbId = nil
        self.slug = title.slugged
        self.summary = summary
        self.smallBackgroundImage = posterURL
        self.mediumBackgroundImage = posterURL
        self.largeBackgroundImage = posterURL
        self.posterURL = posterURL
        self.largeCoverImage = posterURL
        self.subtitles = [:]
        self.torrents = torrents
        self.isWatched = false
        self.isAddedToWatchlist = false
        self.publishDate = publishDate
        self.category = category
        self.sizeBytes = sizeBytes
    }

    init?(_ mediaItemDictionary: [String: Any]) {
        guard let id = mediaItemDictionary[MPMediaItemPropertyPersistentID] as? String,
              let title = mediaItemDictionary[MPMediaItemPropertyTitle] as? String else {
            return nil
        }

        let artwork = mediaItemDictionary[MPMediaItemPropertyArtwork] as? String
        let summary = mediaItemDictionary[MPMediaItemPropertySummary] as? String ?? ""

        self.init(title: title,
                  id: id,
                  summary: summary,
                  torrents: [],
                  posterURL: artwork)
    }

    init?(map: Map) {
        self.init(title: "Unknown",
                  id: UUID().uuidString,
                  summary: "",
                  torrents: [])
    }

    mutating func mapping(map: Map) {
        switch map.mappingType {
        case .fromJSON:
            title <- map["title"]
            id <- map["id"]
            summary <- map["summary"]
            posterURL <- map["posterURL"]
            category <- map["category"]
            torrents <- map["torrents"]
            if let size: Int = try? map.value("sizeBytes") {
                sizeBytes = Int64(size)
            }
            publishDate <- (map["publishDate"], DateTransform())
            if slug.isEmpty { slug = title.slugged }

        case .toJSON:
            title >>> map["title"]
            id >>> map["id"]
            summary >>> map["summary"]
            posterURL >>> map["posterURL"]
            category >>> map["category"]
            sizeBytes >>> map["sizeBytes"]
            publishDate >>> map["publishDate"]
            torrents >>> map["torrents"]
        }
    }

    static func == (lhs: JackettMedia, rhs: JackettMedia) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - JackettXMLParser

class JackettXMLParser: NSObject {
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func parse() -> [JackettMedia]? {
        let parser = XMLParser(data: data)
        let delegate = JackettXMLParserDelegate()
        parser.delegate = delegate

        if parser.parse() {
            return delegate.items
        }

        return nil
    }
}

class JackettXMLParserDelegate: NSObject, XMLParserDelegate {
    var items: [JackettMedia] = []

    private struct CurrentItem {
        var title = ""
        var link = ""
        var guid = ""
        var description = ""
        var publishDate = ""
        var category = ""
        var enclosureURL = ""
        var sizeFromElement: Int64 = 0
        var sizeFromAttr: Int64 = 0
        var seeders: Int = 0
        var peers: Int = 0
    }

    private var currentItem: CurrentItem?
    private var currentElement = ""

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName

        if elementName == "item" {
            currentItem = CurrentItem()
            return
        }

        guard var item = currentItem else { return }

        if elementName == "enclosure" {
            item.enclosureURL = attributeDict["url"] ?? ""
        }

        let normalizedElement = (qName ?? elementName).lowercased()
        if normalizedElement == "torznab:attr" || elementName.lowercased() == "attr" {
            let name = (attributeDict["name"] ?? "").lowercased()
            let value = attributeDict["value"] ?? ""
            switch name {
            case "seeders":
                item.seeders = Int(value) ?? item.seeders
            case "peers":
                item.peers = Int(value) ?? item.peers
            case "size":
                item.sizeFromAttr = Int64(value) ?? item.sizeFromAttr
            case "category":
                if item.category.isEmpty { item.category = value }
            default:
                break
            }
        }

        currentItem = item
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard var item = currentItem else { return }

        switch currentElement {
        case "title":
            item.title += string
        case "link":
            item.link += string
        case "guid":
            item.guid += string
        case "description":
            item.description += string
        case "pubDate":
            item.publishDate += string
        case "category":
            item.category += string
        case "size":
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                item.sizeFromElement = Int64(trimmed) ?? item.sizeFromElement
            }
        default:
            break
        }

        currentItem = item
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        guard elementName == "item", let item = currentItem else { return }

        defer { currentItem = nil }

        let playableURL = firstNonEmpty(item.enclosureURL, item.link, item.guid)
        guard !playableURL.isEmpty else {
            return
        }

        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return
        }

        let sizeBytes = max(item.sizeFromElement, item.sizeFromAttr)
        let summary = stripHTML(item.description).trimmingCharacters(in: .whitespacesAndNewlines)
        let publishDate = parseDate(item.publishDate)
        let poster = extractPosterURL(fromHTML: item.description)

        let quality = inferQuality(from: title)
        let sizeString = sizeBytes > 0 ? ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file) : nil
        let torrent = Torrent(url: playableURL,
                              quality: quality,
                              seeds: item.seeders,
                              peers: item.peers,
                              size: sizeString)

        let idSource = firstNonEmpty(item.guid, playableURL, title)
        let media = JackettMedia(title: title,
                                 id: stableID(from: idSource),
                                 summary: summary.isEmpty ? title : summary,
                                 torrents: [torrent],
                                 posterURL: poster,
                                 sizeBytes: sizeBytes,
                                 publishDate: publishDate,
                                 category: item.category.isEmpty ? nil : item.category)
        items.append(media)
    }

    private func firstNonEmpty(_ values: String...) -> String {
        values.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func stableID(from source: String) -> String {
        let normalized = source.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? UUID().uuidString : normalized
    }

    private func inferQuality(from title: String) -> String {
        let patterns = ["2160p", "1080p", "720p", "480p", "360p", "3D"]
        let lower = title.lowercased()
        if let match = patterns.first(where: { lower.contains($0.lowercased()) }) {
            return match
        }
        return "Unknown"
    }

    private func parseDate(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: trimmed)
    }

    private func stripHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    private func extractPosterURL(fromHTML html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<img[^>]+src=[\"']([^\"']+)[\"']", options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges > 1,
              let srcRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return String(html[srcRange])
    }
}
