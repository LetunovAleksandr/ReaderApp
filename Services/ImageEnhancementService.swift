
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct ImageEnhancementSettings {
    var enabled = true
    var contrast: Float = 1.2
    var brightness: Float = 0.02
    var saturation: Float = 0.0
    var sharpness: Float = 0.4

    var cacheKey: String {
        [
            enabled ? "1" : "0",
            String(contrast),
            String(brightness),
            String(saturation),
            String(sharpness)
        ].joined(separator: "_")
    }
}

final class ImageEnhancementService {
    static let shared = ImageEnhancementService()

    private let context = CIContext()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.totalCostLimit = 64 * 1024 * 1024
        cache.countLimit = 12

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearCache()
        }
    }

    func cachedImage(
        for key: String,
        settings: ImageEnhancementSettings
    ) -> UIImage? {
        let fullKey = "\(key)|\(settings.cacheKey)" as NSString
        return cache.object(forKey: fullKey)
    }

    func enhance(
        _ image: UIImage,
        cacheKey: String? = nil,
        settings: ImageEnhancementSettings
    ) -> UIImage {
        guard settings.enabled else {
            return image
        }

        let key: NSString? = cacheKey.map {
            "\($0)|\(settings.cacheKey)" as NSString
        }

        if let key, let cached = cache.object(forKey: key) {
            return cached
        }

        guard let inputImage = CIImage(image: image) else {
            return image
        }

        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = inputImage
        colorControls.contrast = settings.contrast
        colorControls.brightness = settings.brightness
        colorControls.saturation = settings.saturation

        guard let colorOutput = colorControls.outputImage else {
            return image
        }

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = colorOutput
        sharpen.sharpness = settings.sharpness

        guard
            let outputImage = sharpen.outputImage,
            let cgImage = context.createCGImage(
                outputImage,
                from: outputImage.extent
            )
        else {
            return image
        }

        let result = UIImage(
            cgImage: cgImage,
            scale: image.scale,
            orientation: image.imageOrientation
        )

        if let key {
            let cost = cgImage.bytesPerRow * cgImage.height
            cache.setObject(result, forKey: key, cost: cost)
        }

        return result
    }

    func clearCache() {
        cache.removeAllObjects()
    }
}
