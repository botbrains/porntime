
import Foundation
import UIKit

/// Resolves and caches poster images for `JackettMedia` items by searching TMDB
/// using a cleaned-up version of the torrent title.
///
/// The typical torrent title looks like:
///   "The Matrix 1999 1080p BluRay x264-GROUP"
///
/// This class strips quality tags, codec info, and release group names to extract
/// a human-readable title + optional year, then queries TMDB's search API.
/// Results are cached in-memory and on disk so each title is only looked up once.
final class JackettPosterProvider {

    static let shared = JackettPosterProvider()

    // MARK: - Caches

    /// In-memory: JackettMedia.id → poster URL string
    private var urlCache: [String: String] = [:]

    /// Pending lookups to avoid duplicate network requests for the same item
    private var pendingLookups: [String: [(String?) -> Void]] = [:]

    private let cacheQueue = DispatchQueue(label: "com.popcorntime.jackettPosterCache", attributes: .concurrent)

    private init() {
        // Load persisted URL cache from disk
        if let data = try? Data(contentsOf: diskCacheURL),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            urlCache = dict
        }
    }

    // MARK: - Public API

    /// Returns a poster URL for the given `JackettMedia`, fetching from TMDB if needed.
    ///
    /// - Parameters:
    ///   - media: The Jackett torrent item.
    ///   - completion: Called on the main queue with the poster URL string, or `nil`.
    func posterURL(for media: JackettMedia, completion: @escaping (String?) -> Void) {
        let id = media.id

        // 1. Check in-memory cache
        var cached: String?
        cacheQueue.sync { cached = urlCache[id] }
        if let cached = cached {
            completion(cached.isEmpty ? nil : cached)
            return
        }

        // 2. Coalesce duplicate requests
        var isFirstRequest = false
        cacheQueue.sync(flags: .barrier) {
            if pendingLookups[id] != nil {
                pendingLookups[id]?.append(completion)
            } else {
                pendingLookups[id] = [completion]
                isFirstRequest = true
            }
        }
        guard isFirstRequest else { return }

        // 3. Extract a clean title + optional year from the torrent name
        let (cleanTitle, year) = JackettPosterProvider.extractTitleAndYear(from: media.title)

        // 4. Search TMDB
        searchTMDB(query: cleanTitle, year: year) { [weak self] posterPath in
            guard let self = self else { return }

            let posterURL: String?
            if let path = posterPath {
                posterURL = "https://image.tmdb.org/t/p/w500" + path
            } else {
                posterURL = nil
            }

            // Store in cache (empty string means "looked up but not found")
            self.cacheQueue.sync(flags: .barrier) {
                self.urlCache[id] = posterURL ?? ""
            }
            self.persistCache()

            // Deliver to all waiting callers
            var callbacks: [(String?) -> Void] = []
            self.cacheQueue.sync(flags: .barrier) {
                callbacks = self.pendingLookups.removeValue(forKey: id) ?? []
            }
            DispatchQueue.main.async {
                for cb in callbacks { cb(posterURL) }
            }
        }
    }

    /// Clears both in-memory and on-disk caches.
    func clearCache() {
        cacheQueue.sync(flags: .barrier) {
            urlCache.removeAll()
        }
        try? FileManager.default.removeItem(at: diskCacheURL)
    }

    // MARK: - TMDB Search

    private func searchTMDB(query: String, year: String?, completion: @escaping (String?) -> Void) {
        var components = URLComponents(string: "https://api.themoviedb.org/3/search/multi")!
        var queryItems = [
            URLQueryItem(name: "api_key", value: TMDB.apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "include_adult", value: "false")
        ]
        if let year = year {
            queryItems.append(URLQueryItem(name: "year", value: year))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }

            // Lightweight JSON parsing — we only need the first result's poster_path
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let posterPath = first["poster_path"] as? String else {
                // If search with year failed, retry without year
                if year != nil {
                    self.searchTMDB(query: query, year: nil, completion: completion)
                } else {
                    completion(nil)
                }
                return
            }
            completion(posterPath)
        }.resume()
    }

    // MARK: - Title Parsing

    /// Extracts a clean movie/show title and optional year from a torrent filename.
    ///
    /// Examples:
    /// - "The.Matrix.1999.1080p.BluRay.x264-GROUP" → ("The Matrix", "1999")
    /// - "Breaking Bad S01E01 720p" → ("Breaking Bad", nil)
    /// - "Inception (2010) [1080p]" → ("Inception", "2010")
    static func extractTitleAndYear(from torrentTitle: String) -> (title: String, year: String?) {
        var cleaned = torrentTitle

        // Replace common separators with spaces
        cleaned = cleaned.replacingOccurrences(of: ".", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")

        // Remove content in brackets/parentheses that looks like tags
        cleaned = cleaned.replacingOccurrences(of: "\\[.*?\\]", with: " ", options: .regularExpression)

        // Try to find a year (4-digit number between 1900-2099)
        let yearPattern = "\\b((?:19|20)\\d{2})\\b"
        let yearRegex = try? NSRegularExpression(pattern: yearPattern)
        let yearMatch = yearRegex?.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))

        var year: String?
        var titleEndIndex = cleaned.endIndex

        if let match = yearMatch, let range = Range(match.range(at: 1), in: cleaned) {
            year = String(cleaned[range])
            // Everything before the year is likely the title
            titleEndIndex = range.lowerBound
        } else {
            // No year found — try to cut at common quality/tag markers
            let markers = [
                "2160p", "1080p", "720p", "480p", "4K", "UHD",
                "BluRay", "Blu-Ray", "BDRip", "BRRip", "WEB-DL", "WEBRip", "WEBDL",
                "HDRip", "DVDRip", "HDTV", "PDTV", "DVDScr", "CAM", "TS",
                "x264", "x265", "H264", "H265", "HEVC", "AVC", "AAC", "DTS", "AC3",
                "REMUX", "PROPER", "REPACK", "EXTENDED", "UNRATED",
                "S\\d{1,2}E\\d{1,2}", "S\\d{1,2}", "Season", "Complete"
            ]
            let markerPattern = "\\b(" + markers.joined(separator: "|") + ")\\b"
            if let markerRegex = try? NSRegularExpression(pattern: markerPattern, options: .caseInsensitive),
               let match = markerRegex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
               let range = Range(match.range, in: cleaned) {
                titleEndIndex = range.lowerBound
            }
        }

        var title = String(cleaned[cleaned.startIndex..<titleEndIndex])

        // Remove year from title if it's at the end
        if let year = year {
            title = title.replacingOccurrences(of: year, with: "")
        }

        // Remove leftover parentheses and trim
        title = title.replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Collapse multiple spaces
        while title.contains("  ") {
            title = title.replacingOccurrences(of: "  ", with: " ")
        }

        guard !title.isEmpty else {
            return (torrentTitle, nil)
        }

        return (title, year)
    }

    // MARK: - Disk Persistence

    private var diskCacheURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("JackettPosterCache.json")
    }

    private func persistCache() {
        cacheQueue.async {
            let snapshot = self.urlCache
            DispatchQueue.global(qos: .utility).async {
                if let data = try? JSONEncoder().encode(snapshot) {
                    try? data.write(to: self.diskCacheURL, options: .atomic)
                }
            }
        }
    }
}
