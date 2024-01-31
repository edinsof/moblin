import AVFoundation
import HaishinKit
import UIKit

private let appleLogLutQueue = DispatchQueue(label: "com.eerimoq.widget.cubeLut")

private func convertLut(image: UIImage) -> (Float, Data)? {
    let width = image.size.width * image.scale
    let height = image.size.height * image.scale
    let dimension = Int(cbrt(Double(width * height)))
    guard Int(width) % dimension == 0, Int(height) % dimension == 0 else {
        logger.info("apple-log-lut: Image is not a cube")
        return nil
    }
    guard dimension * dimension * dimension == Int(width * height) else {
        logger.info("apple-log-lut: Image is not a cube")
        return nil
    }
    guard image.cgImage?.bitsPerComponent == 8 else {
        logger.info("apple-log-lut: Image is not 8 bits per component")
        return nil
    }
    guard let data = image.cgImage?.dataProvider?.data else {
        logger.info("apple-log-lut: Failed to get data")
        return nil
    }
    guard var pixels = CFDataGetBytePtr(data) else {
        logger.info("apple-log-lut: Failed to get pixels")
        return nil
    }
    let length = CFDataGetLength(data)
    let original = pixels
    let rows = Int(height) / dimension
    let columns = Int(width) / dimension
    var cube = UnsafeMutablePointer<Float>.allocate(capacity: length)
    let origCube = cube
    for row in 0 ..< rows {
        for column in 0 ..< columns {
            pixels = original
            pixels += Int(width) * (row * dimension) * 4 + column * dimension * 4
            for lr in 0 ..< dimension {
                pixels = original
                let rowStrides = Int(width) * (row * dimension + lr) * 4
                let columnStrides = column * dimension * 4
                pixels += (rowStrides + columnStrides)
                for _ in 0 ..< dimension {
                    cube.pointee = Float(pixels.pointee) / 255.0
                    cube += 1
                    pixels += 1
                    cube.pointee = Float(pixels.pointee) / 255.0
                    cube += 1
                    pixels += 1
                    cube.pointee = Float(pixels.pointee) / 255.0
                    cube += 1
                    pixels += 1
                    cube.pointee = Float(pixels.pointee) / 255.0
                    cube += 1
                    pixels += 1
                }
            }
        }
    }
    return (Float(dimension), Data(bytes: origCube, count: length * 4))
}

final class AppleLogLutEffect: VideoEffect {
    private var filter = CIFilter.colorCube()

    func setLut(name: String) {
        guard let path = Bundle.main.path(forResource: "LUTs.bundle/\(name).png", ofType: nil) else {
            logger.info("apple-log-lut: Image \(name) does not exist")
            return
        }
        guard let image = UIImage(contentsOfFile: path) else {
            logger.info("apple-log-lut: Failed to load image \(name)")
            return
        }
        guard let (dimension, data) = convertLut(image: image) else {
            return
        }
        logger
            .info("apple-log-lut: Applying filter \(name) with dimension \(dimension) and data \(data.count)")
        let filter = CIFilter.colorCube()
        filter.cubeDimension = dimension
        filter.cubeData = data
        appleLogLutQueue.sync {
            self.filter = filter
        }
    }

    override func execute(_ image: CIImage, info _: CMSampleBuffer?) -> CIImage {
        let filter = appleLogLutQueue.sync {
            self.filter
        }
        filter.inputImage = image
        return filter.outputImage ?? image
    }
}