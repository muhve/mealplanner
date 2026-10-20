import SwiftUI
import UIKit
import ImageIO

/// Decode and downsample on a background queue; each visible view retains its image.
struct DishPhotoView: View {
  let name: String
  let height: CGFloat
  var width: CGFloat? = nil
  @Environment(\.displayScale) private var displayScale
  @State private var image: UIImage?

  var body: some View {
    Color.clear
      .frame(height: height)
      .frame(width: width)
      .overlay {
        if let image {
          Image(uiImage: image).resizable().scaledToFill()
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .accessibilityHidden(true)
      .task(id: name) {
        image = nil
        guard let url = PhotoStore().url(for: name) else { return }
        let maxPixels = width.map { max($0, height) * displayScale } ?? 1200
        let loaded: UIImage? = await withCheckedContinuation { continuation in
          DispatchQueue.global(qos: .userInitiated).async {
            let options: [CFString: Any] = [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              kCGImageSourceShouldCacheImmediately: true
            ]
            let source = CGImageSourceCreateWithURL(
              url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            let thumbnail = source.flatMap {
              CGImageSourceCreateThumbnailAtIndex($0, 0, options as CFDictionary)
            }
            continuation.resume(returning: thumbnail.map { UIImage(cgImage: $0) })
          }
        }
        guard !Task.isCancelled else { return }
        image = loaded
      }
  }
}
