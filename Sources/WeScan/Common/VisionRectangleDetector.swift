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

    // MARK: - Rectangle Detection (fallback for iOS 11-12 + imported images)

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

    // MARK: - Document Segmentation (iOS 13+, ML-based paper detection)

    /// Converts a VNDocumentObservation's bounding box to a Quadrilateral.
    /// VNDocumentObservation only exposes `boundingBox` (not individual corner points like
    /// VNRectangleObservation). We construct an axis-aligned quad from the bounding rect.
    /// This is accurate enough for initial detection — the Edit screen allows fine-tuning.
    private static func quad(from observation: VNDocumentObservation) -> Quadrilateral {
        let bbox = observation.boundingBox
        return Quadrilateral(
            topLeft:     CGPoint(x: bbox.minX, y: bbox.maxY),
            topRight:    CGPoint(x: bbox.maxX, y: bbox.maxY),
            bottomRight: CGPoint(x: bbox.maxX, y: bbox.minY),
            bottomLeft:  CGPoint(x: bbox.minX, y: bbox.minY)
        )
    }

    /// Uses VNDetectDocumentSegmentationRequest — an ML model specifically trained to detect
    /// paper documents in real-world scenes. Unlike VNDetectRectanglesRequest (which finds any
    /// rectangular shape), this detector only fires on actual paper/document regions.
    /// This eliminates false positives from windows, doors, shelves, screens, etc.
    @available(iOS 13.0, *)
    private static func detectDocument(
        forPixelBuffer pixelBuffer: CVPixelBuffer,
        width: CGFloat,
        height: CGFloat,
        completion: @escaping ((Quadrilateral?) -> Void)
    ) {
        let request = VNDetectDocumentSegmentationRequest { request, error in
            guard error == nil,
                  let results = request.results as? [VNDocumentObservation],
                  let observation = results.first else {
                // No document found — return nil, don't fall back to rectangle detection.
                // This is intentional: we don't want to hallucinate shapes when there's no paper.
                completion(nil)
                return
            }

            let quad = self.quad(from: observation)
            let transform = CGAffineTransform.identity.scaledBy(x: width, y: height)
            completion(quad.applying(transform))
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }

    /// Same as detectDocument(forPixelBuffer:) but for CIImage (used by CaptureSessionManager's
    /// live camera feed after preprocessing).
    @available(iOS 13.0, *)
    private static func detectDocument(
        forImage image: CIImage,
        width: CGFloat,
        height: CGFloat,
        completion: @escaping ((Quadrilateral?) -> Void)
    ) {
        let request = VNDetectDocumentSegmentationRequest { request, error in
            guard error == nil,
                  let results = request.results as? [VNDocumentObservation],
                  let observation = results.first else {
                completion(nil)
                return
            }

            let quad = self.quad(from: observation)
            let transform = CGAffineTransform.identity.scaledBy(x: width, y: height)
            completion(quad.applying(transform))
        }

        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try? handler.perform([request])
    }

    // MARK: - Public API

    /// Detects rectangles from the given CVPixelBuffer (live camera feed).
    /// On iOS 13+, uses ML-based document segmentation to only detect actual paper.
    /// Falls back to rectangle detection on iOS 11-12 with stricter thresholds.
    static func rectangle(forPixelBuffer pixelBuffer: CVPixelBuffer, completion: @escaping ((Quadrilateral?) -> Void)) {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        if #available(iOS 13.0, *) {
            // Primary: ML document segmentation (paper only, no hallucinations)
            detectDocument(forPixelBuffer: pixelBuffer, width: width, height: height, completion: completion)
        } else {
            // iOS 11-12 fallback: rectangle detection with stricter thresholds
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            VisionRectangleDetector.completeImageRequest(
                for: imageRequestHandler,
                width: width,
                height: height,
                completion: completion)
        }
    }

    /// Detects rectangles from a single image (live camera feed after preprocessing, or imports).
    /// On iOS 13+, uses ML-based document segmentation for the live feed to avoid hallucinations.
    /// Falls back to rectangle detection on iOS 11-12 with stricter thresholds.
    static func rectangle(forImage image: CIImage, completion: @escaping ((Quadrilateral?) -> Void)) {
        if #available(iOS 13.0, *) {
            // Primary: ML document segmentation (paper only, no hallucinations)
            detectDocument(forImage: image, width: image.extent.width, height: image.extent.height, completion: completion)
        } else {
            // iOS 11-12 fallback: rectangle detection with stricter thresholds
            let imageRequestHandler = VNImageRequestHandler(ciImage: image, options: [:])
            VisionRectangleDetector.completeImageRequest(
                for: imageRequestHandler,
                width: image.extent.width,
                height: image.extent.height,
                completion: completion)
        }
    }

    /// Detects rectangles from a single imported image with orientation.
    /// Used by ImageScannerController for images passed at init or via useImage().
    /// Uses rectangle detection with strict thresholds — appropriate for one-shot imports
    /// where the user has explicitly chosen an image they expect to contain a document.
    static func rectangle(
        forImage image: CIImage,
        orientation: CGImagePropertyOrientation,
        completion: @escaping ((Quadrilateral?) -> Void)
    ) {
        let imageRequestHandler = VNImageRequestHandler(ciImage: image, orientation: orientation, options: [:])
        let orientedImage = image.oriented(orientation)
        VisionRectangleDetector.completeImageRequest(
            for: imageRequestHandler, width: orientedImage.extent.width,
            height: orientedImage.extent.height, completion: completion)
    }
}
