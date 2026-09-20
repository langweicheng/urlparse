import Foundation
import CoreImage

public enum QRCode {
    public static func image(for text: String) throws -> CGImage {
        guard !text.isEmpty else { throw Failure("请先输入 URL") }
        guard text.utf8.count <= 2953 else { throw Failure("URL 太长，无法生成单个二维码。请缩短 URL 后重试。") }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw Failure("系统二维码滤镜不可用") }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("L", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { throw Failure("无法生成二维码，请检查 URL 长度") }
        let scale = max(1, floor(440 / (output.extent.width + 8)))
        let extent = output.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent)
        // Render only the small QR module grid in Core Image; scale with Core Graphics.
        // This avoids a large intermediate CI render and retained rendering caches.
        let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
        defer { context.clearCaches() }
        let padded = output.composited(over: white)
        guard let modules = context.createCGImage(padded, from: extent),
              let bitmap = CGContext(data: nil, width: Int(extent.width * scale), height: Int(extent.height * scale),
                                     bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                     bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw Failure("二维码图像生成失败") }
        bitmap.interpolationQuality = .none
        bitmap.draw(modules, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        guard let image = bitmap.makeImage() else { throw Failure("二维码图像生成失败") }
        return image
    }
}
