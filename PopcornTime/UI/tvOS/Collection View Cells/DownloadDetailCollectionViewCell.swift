

import Foundation
import class PopcornTorrent.PTTorrentDownload
import MediaPlayer.MPMediaItem

protocol DownloadCollectionViewCellDelegate: class {
    func cell(_ cell: DownloadCollectionViewCell, longPressDetected gesture: UILongPressGestureRecognizer)
}

class DownloadCollectionViewCell: BaseCollectionViewCell {
    
    @IBOutlet var blurView: UIVisualEffectView!
    @IBOutlet var progressView: UIDownloadProgressView!
    @IBOutlet var pausedImageView: UIImageView!
    
    
    var downloadState: DownloadButton.buttonState = .normal {
        didSet {
            guard downloadState != oldValue else { return }
            
            invalidateAppearance()
        }
    }
    
    var progress: Float = 0 {
        didSet {
            progressView.endAngle = ((2 * CGFloat.pi) * CGFloat(progress)) + progressView.startAngle
        }
    }
    
    weak var delegate: DownloadCollectionViewCellDelegate?
    
    @objc func longPressDetected(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        delegate?.cell(self, longPressDetected: gesture)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(longPressDetected(_:)))
        addGestureRecognizer(gesture)
        
        focusedConstraints.append(blurView.heightAnchor.constraint(equalTo: imageView.focusedFrameGuide.heightAnchor))
        focusedConstraints.append(blurView.widthAnchor.constraint(equalTo: imageView.focusedFrameGuide.widthAnchor))
        
        progressView.endAngle = .pi * 1.5
    }
    
    func invalidateAppearance() {
        pausedImageView.isHidden = downloadState != .paused
        progressView.isFilled = downloadState != .paused
        blurView.isHidden = downloadState == .downloaded
    }
    
}

extension DownloadCollectionViewCell: CellCustomizing {

    func configureCellWith<T>(_ item: T) {

        guard let download = item as? PTTorrentDownload else { print(">>> initializing cell with invalid item"); return }

        self.progress = download.torrentStatus.totalProgress
        self.downloadState = DownloadButton.buttonState(download.downloadStatus)

        if let image = download.mediaMetadata[MPMediaItemPropertyArtwork] as? String, let url = URL(string: image) {
            self.imageView?.af_setImage(withURL: url)
        } else if download.downloadStatus == .finished {
            // Generate a thumbnail from the downloaded video file
            self.imageView?.image = UIImage(named: "Episode Placeholder")
            self.loadVideoThumbnail(for: download)
        } else {
            self.imageView?.image = UIImage(named: "Episode Placeholder")
        }

        self.titleLabel?.text = download.mediaMetadata[MPMediaItemPropertyTitle] as? String
        self.blurView.isHidden = download.downloadStatus == .finished
    }

    /// Extracts and displays a thumbnail from the downloaded video file.
    private func loadVideoThumbnail(for download: PTTorrentDownload) {
        // Use the download's play handler to get the local video file URL,
        // then generate a thumbnail from it.
        download.play { [weak self] videoFileURL, videoFilePath in
            guard let self = self else { return }

            // Stop the playback server immediately — we only needed the file path
            download.cancelStreamingAndDeleteData(false)

            TorrentThumbnailGenerator.shared.thumbnail(for: download, videoFileURL: videoFilePath) { [weak self] image in
                guard let self = self, let image = image else { return }
                UIView.transition(with: self.imageView, duration: 0.3, options: .transitionCrossDissolve, animations: {
                    self.imageView?.image = image
                }, completion: nil)
            }
        }
    }
}
