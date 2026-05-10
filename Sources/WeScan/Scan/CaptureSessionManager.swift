//
//  CaptureManager.swift
//  WeScan
//
//  Created by Boris Emorine on 2/8/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMotion
import Foundation
import UIKit

/// A set of functions that inform the delegate object of the state of the detection.
protocol RectangleDetectionDelegateProtocol: NSObjectProtocol {

    /// Called when the capture of a picture has started.
    ///
    /// - Parameters:
    ///   - captureSessionManager: The `CaptureSessionManager` instance that started capturing a picture.
    func didStartCapturingPicture(for captureSessionManager: CaptureSessionManager)

    /// Called when a quadrilateral has been detected.
    /// - Parameters:
    ///   - captureSessionManager: The `CaptureSessionManager` instance that has detected a quadrilateral.
    ///   - quad: The detected quadrilateral in the coordinates of the image.
    ///   - imageSize: The size of the image the quadrilateral has been detected on.
    func captureSessionManager(_ captureSessionManager: CaptureSessionManager, didDetectQuad quad: Quadrilateral?, _ imageSize: CGSize)

    /// Called when a picture with or without a quadrilateral has been captured.
    ///
    /// - Parameters:
    ///   - captureSessionManager: The `CaptureSessionManager` instance that has captured a picture.
    ///   - picture: The picture that has been captured.
    ///   - quad: The quadrilateral that was detected in the picture's coordinates if any.
    func captureSessionManager(
        _ captureSessionManager: CaptureSessionManager,
        didCapturePicture picture: UIImage,
        withQuad quad: Quadrilateral?
    )

    /// Called when an error occurred with the capture session manager.
    /// - Parameters:
    ///   - captureSessionManager: The `CaptureSessionManager` that encountered an error.
    ///   - error: The encountered error.
    func captureSessionManager(_ captureSessionManager: CaptureSessionManager, didFailWithError error: Error)
}

/// The CaptureSessionManager is responsible for setting up and managing the AVCaptureSession and the functions related to capturing.
final class CaptureSessionManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    private let videoPreviewLayer: AVCaptureVideoPreviewLayer
    private let captureSession = AVCaptureSession()
    private let rectangleFunnel = RectangleFeaturesFunnel()
    weak var delegate: RectangleDetectionDelegateProtocol?
    private var displayedRectangleResult: RectangleDetectorResult?
    private var photoOutput = AVCapturePhotoOutput()
    private var hasLoggedFirstFrame = false

    /// Whether the CaptureSessionManager should be detecting quadrilaterals.
    private var isDetecting = true

    /// Filtres Core Image créés une seule fois et réutilisés à chaque frame (évite les allocations).
    private let shadowFilter: CIFilter = {
        let f = CIFilter.highlightShadowAdjust()
        f.shadowAmount = 0.85
        f.highlightAmount = 0.1
        return f
    }()
    private let colorFilter: CIFilter = {
        let f = CIFilter.colorControls()
        f.contrast = 1.2
        f.brightness = 0.1
        f.saturation = 1.0
        return f
    }()

    // swiftlint:disable:next line_length
    private let wescanBuildTag = "WeScan@doc-seg-ios13 conf=0.5 minSize=0.15 maxObs=8 noRectThresh=12"

    /// Seuil ISO au-delà duquel on considère que la scène est trop sombre (active le torch).
    private let lowLightISOThreshold: Float = 800
    /// True si l'utilisateur a éteint le flash manuellement — on ne le rallume plus.
    private var userDisabledTorch = false

    /// The number of times no rectangles have been found in a row.
    private var noRectangleCount = 0

    /// The minimum number of time required by `noRectangleCount` to validate that no rectangles have been found.
    /// Raised from 8 → 12: requires more consecutive empty frames before resetting, reducing flicker and false resets.
    private let noRectangleThreshold = 12

    // MARK: Life Cycle

    init?(videoPreviewLayer: AVCaptureVideoPreviewLayer, delegate: RectangleDetectionDelegateProtocol? = nil) {
        self.videoPreviewLayer = videoPreviewLayer

        if delegate != nil {
            self.delegate = delegate
        }

        super.init()

        NSLog("🎥 %@", wescanBuildTag)
        guard let device = AVCaptureDevice.default(for: AVMediaType.video) else {
            let error = ImageScannerControllerError.inputDevice
            delegate?.captureSessionManager(self, didFailWithError: error)
            print("❌ CaptureSessionManager: No video device available")
            return nil
        }

        captureSession.beginConfiguration()

        photoOutput.isHighResolutionCaptureEnabled = true

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true

        defer {
            device.unlockForConfiguration()
            captureSession.commitConfiguration()
        }

        guard let deviceInput = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(deviceInput),
            captureSession.canAddOutput(photoOutput),
            captureSession.canAddOutput(videoOutput) else {
                let error = ImageScannerControllerError.inputDevice
                delegate?.captureSessionManager(self, didFailWithError: error)
                print("❌ CaptureSessionManager: Cannot add input/output to session")
                return
        }

        do {
            try device.lockForConfiguration()
        } catch {
            let error = ImageScannerControllerError.inputDevice
            delegate?.captureSessionManager(self, didFailWithError: error)
            print("❌ CaptureSessionManager: lockForConfiguration failed: \(error)")
            return
        }

        device.isSubjectAreaChangeMonitoringEnabled = true

        captureSession.addInput(deviceInput)
        captureSession.addOutput(photoOutput)
        captureSession.addOutput(videoOutput)

        let photoPreset = AVCaptureSession.Preset.photo

        if captureSession.canSetSessionPreset(photoPreset) {
            captureSession.sessionPreset = photoPreset

            if photoOutput.isLivePhotoCaptureSupported {
                photoOutput.isLivePhotoCaptureEnabled = true
            }
        }

        videoPreviewLayer.session = captureSession
        videoPreviewLayer.videoGravity = .resizeAspectFill
        print("🎛️ CaptureSessionManager: Session configured. preset=\(captureSession.sessionPreset.rawValue), livePhoto=\(photoOutput.isLivePhotoCaptureEnabled), gravity=\(videoPreviewLayer.videoGravity)")

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video_ouput_queue"))
    }

    // MARK: Capture Session Life Cycle

    /// Starts the camera and detecting quadrilaterals.
    internal func start() {
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch authorizationStatus {
        case .authorized:
            print("▶️ CaptureSessionManager: Starting session… authorized")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                self.captureSession.startRunning()
                let running = self.captureSession.isRunning
                DispatchQueue.main.async {
                    self.isDetecting = true
                    print("✅ CaptureSessionManager: Session started. isRunning=\(running)")
                    if let conn = self.videoPreviewLayer.connection {
                        print("🔗 Preview connection: isEnabled=\(conn.isEnabled) isActive=\(conn.isActive) vidOrientation=\(conn.videoOrientation.rawValue)")
                    } else {
                        print("⚠️ CaptureSessionManager: No preview connection")
                    }
                }
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if granted {
                        self.start()
                    } else {
                        let error = ImageScannerControllerError.authorization
                        self.delegate?.captureSessionManager(self, didFailWithError: error)
                        print("❌ CaptureSessionManager: Camera access denied")
                    }
                }
            })
        default:
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let error = ImageScannerControllerError.authorization
                self.delegate?.captureSessionManager(self, didFailWithError: error)
                print("❌ CaptureSessionManager: Authorization status not allowed: \(authorizationStatus.rawValue)")
            }
        }
    }

    internal func stop() {
      print("⏹️ CaptureSessionManager: Stopping session…")
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
          guard let self = self else { return }
          if self.captureSession.isRunning {
              self.captureSession.stopRunning()
              print("✅ CaptureSessionManager: Session stopped")
          }
      }
      }

    internal func capturePhoto() {
        guard let connection = photoOutput.connection(with: .video), connection.isEnabled, connection.isActive else {
            let error = ImageScannerControllerError.capture
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }
        CaptureSession.current.setImageOrientation()
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.isHighResolutionPhotoEnabled = true
        photoSettings.isAutoStillImageStabilizationEnabled = true
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isDetecting == true,
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let imageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))

        if hasLoggedFirstFrame == false {
            hasLoggedFirstFrame = true
            print("📸 CaptureSessionManager: First frame received. imageSize=\(imageSize)")
        }

        adjustTorchForLighting()

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let processedImage = preprocessFrameForDetection(ciImage)

        if #available(iOS 11.0, *) {
            VisionRectangleDetector.rectangle(forImage: processedImage) { rectangle in
                self.processRectangle(rectangle: rectangle, imageSize: imageSize)
            }
        } else {
            CIRectangleDetector.rectangle(forImage: processedImage) { rectangle in
                self.processRectangle(rectangle: rectangle, imageSize: imageSize)
            }
        }
    }

    /// Active le torch si la scène est sombre. Ne le rallume jamais si l'user l'a éteint.
    private func adjustTorchForLighting() {
        guard !userDisabledTorch,
              let device = CaptureSession.current.device,
              device.isTorchAvailable,
              device.torchMode == .off,
              let avDevice = device as? AVCaptureDevice,
              avDevice.iso > lowLightISOThreshold else { return }

        try? device.lockForConfiguration()
        device.torchMode = .on
        device.unlockForConfiguration()
    }

    /// Appelé quand l'user éteint le flash manuellement — bloque le flash auto pour la session.
    func userDidDisableTorch() {
        userDisabledTorch = true
    }

    /// Corrige les images à contre-jour avant la détection de contours.
    /// Réutilise les filtres pré-créés pour éviter les allocations à chaque frame.
    private func preprocessFrameForDetection(_ image: CIImage) -> CIImage {
        shadowFilter.setValue(image, forKey: kCIInputImageKey)
        guard let shadowOutput = shadowFilter.outputImage else { return image }
        colorFilter.setValue(shadowOutput, forKey: kCIInputImageKey)
        return colorFilter.outputImage ?? shadowOutput
    }

    private func processRectangle(rectangle: Quadrilateral?, imageSize: CGSize) {
        if let rectangle {

            self.noRectangleCount = 0
            self.rectangleFunnel
                .add(rectangle, currentlyDisplayedRectangle: self.displayedRectangleResult?.rectangle) { [weak self] result, rectangle in

                guard let self else {
                    return
                }

                let shouldAutoScan = (result == .showAndAutoScan)
                self.displayRectangleResult(rectangleResult: RectangleDetectorResult(rectangle: rectangle, imageSize: imageSize))
                if shouldAutoScan, CaptureSession.current.isAutoScanEnabled, !CaptureSession.current.isEditing {
                    capturePhoto()
                }
            }

        } else {

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.noRectangleCount += 1

                if self.noRectangleCount > self.noRectangleThreshold {
                    // Reset the currentAutoScanPassCount, so the threshold is restarted the next time a rectangle is found
                    self.rectangleFunnel.currentAutoScanPassCount = 0

                    // Remove the currently displayed rectangle as no rectangles are being found anymore
                    self.displayedRectangleResult = nil
                    self.delegate?.captureSessionManager(self, didDetectQuad: nil, imageSize)
                }
            }
            return

        }
    }

    @discardableResult private func displayRectangleResult(rectangleResult: RectangleDetectorResult) -> Quadrilateral {
        displayedRectangleResult = rectangleResult

        let quad = rectangleResult.rectangle.toCartesian(withHeight: rectangleResult.imageSize.height)

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.delegate?.captureSessionManager(self, didDetectQuad: quad, rectangleResult.imageSize)
        }

        return quad
    }

}

extension CaptureSessionManager: AVCapturePhotoCaptureDelegate {

    // swiftlint:disable function_parameter_count
    func photoOutput(_ captureOutput: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photoSampleBuffer: CMSampleBuffer?,
                     previewPhoto previewPhotoSampleBuffer: CMSampleBuffer?,
                     resolvedSettings: AVCaptureResolvedPhotoSettings,
                     bracketSettings: AVCaptureBracketedStillImageSettings?,
                     error: Error?
    ) {
        if let error {
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }

        isDetecting = false
        rectangleFunnel.currentAutoScanPassCount = 0
        delegate?.didStartCapturingPicture(for: self)

        if let sampleBuffer = photoSampleBuffer,
            let imageData = AVCapturePhotoOutput.jpegPhotoDataRepresentation(
                forJPEGSampleBuffer: sampleBuffer,
                previewPhotoSampleBuffer: nil
            ) {
            completeImageCapture(with: imageData)
        } else {
            let error = ImageScannerControllerError.capture
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }

    }

    @available(iOS 11.0, *)
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }

        isDetecting = false
        rectangleFunnel.currentAutoScanPassCount = 0
        delegate?.didStartCapturingPicture(for: self)

        if let imageData = photo.fileDataRepresentation() {
            completeImageCapture(with: imageData)
        } else {
            let error = ImageScannerControllerError.capture
            delegate?.captureSessionManager(self, didFailWithError: error)
            return
        }
    }

    /// Completes the image capture by processing the image, and passing it to the delegate object.
    /// This function is necessary because the capture functions for iOS 10 and 11 are decoupled.
    private func completeImageCapture(with imageData: Data) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            CaptureSession.current.isEditing = true
            guard let image = UIImage(data: imageData) else {
                let error = ImageScannerControllerError.capture
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }
                    self.delegate?.captureSessionManager(self, didFailWithError: error)
                }
                return
            }

            var angle: CGFloat = 0.0

            switch image.imageOrientation {
            case .right:
                angle = CGFloat.pi / 2
            case .up:
                angle = CGFloat.pi
            default:
                break
            }

            var quad: Quadrilateral?
            if let displayedRectangleResult = self?.displayedRectangleResult {
                quad = self?.displayRectangleResult(rectangleResult: displayedRectangleResult)
                quad = quad?.scale(displayedRectangleResult.imageSize, image.size, withRotationAngle: angle)
            }

            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.delegate?.captureSessionManager(self, didCapturePicture: image, withQuad: quad)
            }
        }
    }
}

/// Data structure representing the result of the detection of a quadrilateral.
private struct RectangleDetectorResult {

    /// The detected quadrilateral.
    let rectangle: Quadrilateral

    /// The size of the image the quadrilateral was detected on.
    let imageSize: CGSize

}
