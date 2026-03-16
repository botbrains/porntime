
// This file intentionally left minimal.
// Poster resolution for Jackett items is now handled directly:
//   1. The JackettXMLParser extracts poster URLs from the feed (Torznab attributes + description HTML)
//   2. JackettMedia.smallCoverImage returns the posterURL, which CoverCollectionViewCell loads via AlamofireImage
//   3. When no poster URL is available, TitleCardGenerator creates a styled placeholder image
