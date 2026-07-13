import Foundation
import CoreGraphics
import ImageIO

/// Loads an image file (jpg/png/heic/…) into a CGImage via ImageIO.
enum ImageLoader {
    static func load(path: String) -> CGImage? {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return image
    }
}
