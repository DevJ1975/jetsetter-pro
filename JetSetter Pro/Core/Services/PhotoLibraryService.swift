// File: Core/Services/PhotoLibraryService.swift
//
// Fetches photos from the user's library that fall within a given date range,
// and provides UIImage thumbnails for display. Used by the Photo Trip Journal
// feature to auto-build a scrapbook of a trip.

import Foundation
import Photos
import UIKit

@MainActor
final class PhotoLibraryService {

    static let shared = PhotoLibraryService()
    private init() {}

    private let imageManager = PHCachingImageManager()

    // MARK: - Authorization

    /// Requests photo library read access. Returns true when authorized or
    /// limited (limited access lets us read whatever the user explicitly shared).
    func requestAuthorization() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited { return true }
        if status == .denied || status == .restricted { return false }
        let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return granted == .authorized || granted == .limited
    }

    var isAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    // MARK: - Fetch

    /// Returns the assets created between `startDate` and `endDate`, sorted
    /// chronologically. Empty when permission isn't granted.
    func assets(from startDate: Date, to endDate: Date) -> [PHAsset] {
        guard isAuthorized else { return [] }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@",
            startDate as NSDate, endDate as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        // Only photos — exclude screenshots and bursts to keep the journal clean.
        options.includeAssetSourceTypes = [.typeUserLibrary]

        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            // Skip likely screenshots: matches device aspect ratios via mediaSubtypes
            if !asset.mediaSubtypes.contains(.photoScreenshot) {
                assets.append(asset)
            }
        }
        return assets
    }

    // MARK: - Image loading

    /// Loads a thumbnail-sized UIImage for an asset. Uses opportunistic mode so
    /// the callback may fire multiple times — once with a low-res placeholder
    /// and again with the final image.
    func thumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            var didResume = false
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // The opportunistic mode delivers a degraded image first, then
                // the final. We only resume on the final image.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded, !didResume else { return }
                didResume = true
                continuation.resume(returning: image)
            }
        }
    }

    /// Loads a full-size UIImage. Used when rendering the shareable journal card.
    func fullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            var didResume = false
            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded, !didResume else { return }
                didResume = true
                continuation.resume(returning: image)
            }
        }
    }
}
