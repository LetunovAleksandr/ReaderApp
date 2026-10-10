
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct ImageEnhancementSettings {
    var enabled = true

    // Контраст: 1.0 — без изменений
    var contrast: Float = 1.2

    // Яркость: 0.0 — без изменений
    var brightness: Float = 0.02

    // Насыщенность: 0.0 — чёрно-белое изображение
    var saturation: Float = 0.0

    // Резкость: 0.0 — без дополнительной резкости
    var sharpness: Float = 0.4
}

final class ImageEnhancementService {
    static let shared = ImageEnhancementService()

    private let context = CIContext()

    private init() {}

    func enhance(
        _ image: UIImage,
        settings: ImageEnhancementSettings
    ) -> UIImage {
        guard settings.enabled,
              let inputImage = CIImage(image: image)
        else {
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

        guard let outputImage = sharpen.outputImage,
              let cgImage = context.createCGImage(
                  outputImage,
                  from: outputImage.extent
              )
        else {
            return image
        }

        return UIImage(
            cgImage: cgImage,
            scale: image.scale,
            orientation: image.imageOrientation
        )
    }
}
