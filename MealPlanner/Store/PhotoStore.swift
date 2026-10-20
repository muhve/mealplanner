import Foundation
import MealPlannerCore
import UIKit
import ImageIO
import UniformTypeIdentifiers

struct PhotoStore: Sendable {
  private var directory: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("photos", isDirectory: true)
  }

  func url(for name: String) -> URL? {
    guard validPhotoFileName(name) != nil else { return nil }
    return directory.appendingPathComponent(name)
  }

  nonisolated static func save(data: Data) async throws -> String {
    try await Task.detached(priority: .userInitiated) {
      try autoreleasepool { try storeImageData(data) }
    }.value
  }

  // Camera JPEG conversion also stays off the main actor.
  nonisolated static func save(cameraImage: UIImage) async throws -> String {
    try await Task.detached(priority: .userInitiated) {
      try autoreleasepool {
        guard let data = cameraImage.jpegData(compressionQuality: 1) else {
          throw CoreError("Kuvan lataaminen epäonnistui.")
        }
        return try storeImageData(data)
      }
    }.value
  }

  nonisolated private static func storeImageData(_ data: Data) throws -> String {
    guard let source = CGImageSourceCreateWithData(
      data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
      width > 0, height > 0
    else { throw CoreError("Kuvan lataaminen epäonnistui.") }

    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    let displayedWidth = (5...8).contains(orientation) ? height : width
    // ImageIO limits the longest side; account for portrait and EXIF rotation
    // so the oriented width is at most 1600 pixels without upscaling.
    let maxPixels = max(1, Int((max(width, height) * min(1, 1600 / displayedWidth)).rounded(.down)))
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
      kCGImageSourceShouldCacheImmediately: true
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw CoreError("Kuvan lataaminen epäonnistui.")
    }
    let jpeg = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      jpeg as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
      throw CoreError("Kuvan tallentaminen epäonnistui.")
    }
    CGImageDestinationAddImage(destination, image,
      [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw CoreError("Kuvan tallentaminen epäonnistui.")
    }
    let directory = PhotoStore().directory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let name = UUID().uuidString + ".jpg"
    try (jpeg as Data).write(to: directory.appendingPathComponent(name), options: .atomic)
    return name
  }

  func install(assetURL: URL, name: String) throws {
    guard let destination = url(for: name) else { throw CoreError("Virheellinen kuvatiedosto.") }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(contentsOf: assetURL).write(to: destination, options: .atomic)
  }

  func delete(_ name: String) {
    guard let url = url(for: name) else { return }
    try? FileManager.default.removeItem(at: url)
  }

  func cleanUp(state: AppState, backups: [String]) {
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
    for file in orphanedPhotos(state: state, files: files, backups: backups) { delete(file) }
  }
}
