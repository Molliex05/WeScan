//
//  VisionRectangleDetector.swift
//  WeScan
//
//  Created by Julian Schiavo on 28/7/2018.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import CoreImage
import Foundation
import Vision

/// Enum encapsulating static functions to detect rectangles from an image.
@available(iOS 11.0, *)
enum VisionRectangleDetector {

    private static func completeImageRequest(
        for request: VNImageRequestHandler,
        width: CGFloat,
        height: CGFloat,
        completion: @escaping ((Quadrilateral?) -> Void)
    ) {
        let rectangleDetectionRequest: VNDetectRectanglesRequest = {
            let rectDetectRequest = VNDetectRectanglesRequest(completionHandler: { request, error in
                guard error == nil, let results = request.results as? [VNRectangleObservation], !results.isEmpty else {
                    completion(nil)
                    return
                }

                let quads: [Quadrilateral] = results.map(Quadrilateral.init)

                guard let biggest = quads.biggest() else {
                    completion(nil)
                    return
                }

                let transform = CGAffineTransform.identity
                    .scaledBy(x: width, y: height)

                completion(biggest.applying(transform))
            })

            rectDetectRequest.minimumConfidence = 0.5   // raised from 0.3 — real receipts score 0.7+
            rectDetectRequest.maximumObservations = 8    // reduced from 15 — less noise
            rectDetectRequest.minimumAspectRatio = 0.1   // narrow receipts (58mm wide)
            rectDetectRequest.maximumAspectRatio = 0.65  // excludes A4 (~0.71) and letter (~0.77)
            rectDetectRequest.quadratureTolerance = 40   // tolerate shadow-distorted corners
            rectDetectRequest.minimumSize = 0.15         // raised from 0.1 — paper must occupy ≥15% of frame

            return rectDetectRequest
        }()

        do {
            try request.perform([rectangleDetectionRequest])
        } catch {
            completion(nil)
            return
        }
    }

    /// Detects rectangles from the given CVPixelBuffer (live camera feed).
    static func rectangle(forPixelBuffer pixelBuffer: CVPixelBuffer, completion: @escaping ((Quadrilateral?) -> Void)) {
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        VisionRectangleDetector.completeImageRequest(
            for: imageRequestHandler,
            width: CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
            height: CGFloat(CVPixelBufferGetHeight(pixelBuffer)),
            completion: completion)
    }

    /// Detects rectangles from a single image.
    static func rectangle(forImage image: CIImage, completion: @escaping ((Quadrilateral?) -> Void)) {
        let imageRequestHandler = VNImageRequestHandler(ciImage: image, options: [:])
        VisionRectangleDetector.completeImageRequest(
            for: imageRequestHandler,
            width: image.extent.width,
            height: image.extent.height,
            completion: completion)
    }

    /// Detects rectangles from a single image with orientation.
    static func rectangle(
        forImage image: CIImage,
        orientation: CGImagePropertyOrientation,
        completion: @escaping ((Quadrilateral?) -> Void)
    ) {
        let imageRequestHandler = VNImageRequestHandler(ciImage: image, orientation: orientation, options: [:])
        let orientedImage = image.oriented(orientation)
        VisionRectangleDetector.completeImageRequest(
            for: imageRequestHandler,
            width: orientedImage.extent.width,
            height: orientedImage.extent.height,
            completion: completion)
    }
}
