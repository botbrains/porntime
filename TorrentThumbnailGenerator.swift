
import UIKit
import AVFoundation
import class PopcornTorrent.PTTorrentDownload

/// A utility class that generates and caches video thumbnails for downloaded torrent files.
///
/// Thumbnails are generated using `AVAssetImageGenerator` by extracting a frame
/// near the beginning of the video (at 10% of the duration, to avoid black frames).
/// Generated thumbnails are cached to disk in the app's Caches directory for fast retrieval.
final class TorrentThumbnailGenerator {

    static let shared = TorrentThumbnailGenerator()

    private let thumbnailDirectory: URL
    private let generationQueue = DispatchQueue(label: "com.popcorntime.thumbnailGenerator", qos: .utility, attributes: .concurrent)

    /// In-memory cache to avoid redundant disk reads within the same session.
    private let memoryCache = NSCache<NSString, UIImage>()

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        thumbnailDirectory = caches.appendingPathComponent("TorrentThumbnails", isDirectory: true)

        try? FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)

        memoryCache.countLimit = 50
    }

    // MARK: - Public API

    /// Generates (or retrieves from cache) a thumbnail for the given download.
    ///
    /// - Parameters:
    ///   - download: The `PTTorrentDownload` to generate a thumbnail for. Must be a finished download.
    ///   - videoFileURL: The local file URL pointing to the downloaded video.
    ///   - size: The desired thumbnail size. Defaults to 320×180 (16:9).
    ///   - completion: Called on the main queue with the resulting thumbnail image, or `nil` on failure.
    func thumbnail(
        for download: PTTorrentDownload,
        videoFileURL: URL,
        size: CGSize = CGSize(width: 320, height: 180),
        completion: @escaping (UIImage?) -> Void
    ) {
        let cacheKey = cacheKey(for: download)

        // 1. Check memory cache
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            completion(cached)
            return
        }

        generationQueue.async { [weak self] in
            guard let self = self else { return }

            // 2. Check disk cache
            let diskPath = self.thumbnailDirectory.appendingPathComponent("\(cacheKey).jpg")
            if let data = try? Data(contentsOf: diskPath), let image = UIImage(data: data) {
                self.memoryCache.setObject(image, forKey: cacheKey as NSString)
                DispatchQueue.main.async { completion(image) }
                return
            }

            // 3. Generate thumbnail from video file
            let image = self.generateThumbnail(from: videoFileURL, maxSize: size)

            if let image = image {
                self.memoryCache.setObject(image, forKey: cacheKey as NSString)

                // Save to disk cache
                if let jpegData = image.jpegData(compressionQuality: 0.8) {
                    try? jpegData.write(to: diskPath, options: .atomic)
                }
            }

            DispatchQueue.main.async { completion(image) }
        }
    }

    /// Removes the cached thumbnail for a given download (e.g., when the download is deleted).
    func removeThumbnail(for download: PTTorrentDownload) {
        let cacheKey = cacheKey(for: download)
        memoryCache.removeObject(forKey: cacheKey as NSString)

        let diskPath = thumbnailDirectory.appendingPathComponent("\(cacheKey).jpg")
        try? FileManager.default.removeItem(at: diskPath)
    }

    /// Clears all cached thumbnails.
    func clearCache() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: thumbnailDirectory)
        try? FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private func cacheKey(for download: PTTorrentDownload) -> String {
        // Use the persistent ID from media metadata as a stable unique key
        if let persistentID = download.mediaMetadata[MPMediaItemPropertyPersistentID] as? String {
            // Sanitize for filename safety
            return persistentID.replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
        }
        // Fallback: hash of the title
        let title = (download.mediaMetadata[MPMediaItemPropertyTitle] as? String) ?? "unknown"
        return String(title.hashValue)
    }

    private func generateThumbnail(from videoURL: URL, maxSize: CGSize) -> UIImage? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize

        // Try to grab a frame at ~10% of the duration to avoid opening black frames
        let duration = asset.duration
        let tenPercent = CMTimeMultiplyByFloat64(duration, multiplier: 0.1)

        // If duration isn't available, fall back to 10 seconds in
        let requestTime: CMTime
        if duration.seconds > 0 {
            requestTime = tenPercent
        } else {
            requestTime = CMTime(seconds: 10, preferredTimescale: 600)
        }

        do {
            let cgImage = try generator.copyCGImage(at: requestTime, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            // If the requested time fails, try the very beginning
            do {
                let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                return UIImage(cgImage: cgImage)
            } catch {
                print("TorrentThumbnailGenerator: Failed to generate thumbnail for \(videoURL.lastPathComponent): \(error)")
                return nil
            }
        }
    }
}

import MediaPlayer.MPMediaItem
