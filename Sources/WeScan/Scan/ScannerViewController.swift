//
//  ScannerViewController.swift
//  WeScan
//
//  Created by Boris Emorine on 2/8/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//
//  swiftlint:disable line_length

import AVFoundation
import UIKit
import UniformTypeIdentifiers
import PDFKit

/// The `ScannerViewController` offers an interface to give feedback to the user regarding quadrilaterals that are detected. It also gives the user the opportunity to capture an image with a detected rectangle.
public final class ScannerViewController: UIViewController {

    private var captureSessionManager: CaptureSessionManager?
    private let videoPreviewLayer = AVCaptureVideoPreviewLayer()

    /// (Disabled) Previously showed a yellow focus rectangle on tap
    private var focusRectangle: FocusRectangleView?

    /// The view that draws the detected rectangles.
    private let quadView = QuadrilateralView()

    /// Whether flash is enabled
    private var flashEnabled = false

    /// The original bar style that was set by the host app
    private var originalBarStyle: UIBarStyle?

    private lazy var shutterButton: ShutterButton = {
        let button = ShutterButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(captureImage(_:)), for: .touchUpInside)
        return button
    }()

    private lazy var cancelButton: UIButton = {
        let button = UIButton()
        let cancelTitle = WeScanLocalization.localizedString(for: .scanningCancel, fallback: "Cancel")
        print("🔧 ScannerViewController: Setting cancel button title to: '\(cancelTitle)'")
        button.setTitle(cancelTitle, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(cancelImageScannerController), for: .touchUpInside)
        return button
    }()

    private lazy var autoScanButton: UIBarButtonItem = {
        let title = WeScanLocalization.localizedString(for: .auto, fallback: "Auto")
        print("🔧 ScannerViewController: Setting auto button title to: '\(title)'")
        let button = UIBarButtonItem(title: title, style: .plain, target: self, action: #selector(toggleAutoScan))
        button.tintColor = .white

        return button
    }()

    private lazy var flashButton: UIBarButtonItem = {
        let image = UIImage(systemName: "bolt.fill", named: "flash", in: Bundle(for: ScannerViewController.self), compatibleWith: nil)
        let button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(toggleFlash))
        button.tintColor = .white

        return button
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView(style: .gray)
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        return activityIndicator
    }()

    // MARK: - Import Button System
    
    private lazy var importButton: UIButton = {
        let button = UIButton(type: .system)
        let image = UIImage(systemName: "plus") ?? UIImage(systemName: "add")
        button.setImage(image, for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor(named: "AccentColor") ?? UIColor.systemOrange
        button.layer.cornerRadius = 25
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.layer.shadowOpacity = 0.1
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(importButtonTapped), for: .touchUpInside)
        print("📱 ScannerViewController: Import button created with Glutax AccentColor")
        return button
    }()
    
    private lazy var filesButton: UIButton = {
        let button = UIButton(type: .system)
        let image = UIImage(systemName: "folder.fill") ?? UIImage(systemName: "doc")
        button.setImage(image, for: .normal)
        button.tintColor = UIColor(named: "TextPrimaryColor") ?? UIColor.label
        button.backgroundColor = UIColor(named: "CardBackgroundColor") ?? UIColor.systemBackground
        button.layer.cornerRadius = 22
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.layer.shadowOpacity = 0.1
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(openFiles), for: .touchUpInside)
        button.alpha = 0
        button.isHidden = true
        button.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        print("📁 ScannerViewController: Files button created with Glutax theme")
        return button
    }()
    
    private lazy var photosButton: UIButton = {
        let button = UIButton(type: .system)
        let image = UIImage(systemName: "photo.fill") ?? UIImage(systemName: "photo")
        button.setImage(image, for: .normal)
        button.tintColor = UIColor(named: "TextPrimaryColor") ?? UIColor.label
        button.backgroundColor = UIColor(named: "CardBackgroundColor") ?? UIColor.systemBackground
        button.layer.cornerRadius = 22
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.layer.shadowOpacity = 0.1
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(openPhotos), for: .touchUpInside)
        button.alpha = 0
        button.isHidden = true
        button.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        print("📸 ScannerViewController: Photos button created with Glutax theme")
        return button
    }()
    
    private var isImportMenuOpen = false
    private var importButtonConstraints: [NSLayoutConstraint] = []

    // MARK: - Life Cycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        title = nil
        view.backgroundColor = UIColor.clear

        setupViews()
        setupNavigationBar()
        setupConstraints()

        captureSessionManager = CaptureSessionManager(videoPreviewLayer: videoPreviewLayer, delegate: self)

        originalBarStyle = navigationController?.navigationBar.barStyle

        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: Notification.Name.AVCaptureDeviceSubjectAreaDidChange, object: nil)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setNeedsStatusBarAppearanceUpdate()

        CaptureSession.current.isEditing = false
        quadView.removeQuadrilateral()
        captureSessionManager?.start()
        UIApplication.shared.isIdleTimerDisabled = true

        navigationController?.navigationBar.barStyle = .blackTranslucent
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        videoPreviewLayer.frame = view.layer.bounds
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false

        navigationController?.navigationBar.isTranslucent = false
        navigationController?.navigationBar.barStyle = originalBarStyle ?? .default
        captureSessionManager?.stop()
        guard let device = AVCaptureDevice.default(for: AVMediaType.video) else { return }
        if device.torchMode == .on {
            toggleFlash()
        }
    }

    // MARK: - Setups

    private func setupViews() {
        view.backgroundColor = .darkGray
        view.layer.addSublayer(videoPreviewLayer)
        quadView.translatesAutoresizingMaskIntoConstraints = false
        quadView.editable = false
        view.addSubview(quadView)
        view.addSubview(cancelButton)
        view.addSubview(shutterButton)
        view.addSubview(activityIndicator)
        view.addSubview(importButton)
        view.addSubview(filesButton)
        view.addSubview(photosButton)
        print("🔧 ScannerViewController: All UI elements added to view")
    }

    private func setupNavigationBar() {
        navigationItem.setLeftBarButton(flashButton, animated: false)
        navigationItem.setRightBarButton(autoScanButton, animated: false)

        if UIImagePickerController.isFlashAvailable(for: .rear) == false {
            let flashOffImage = UIImage(systemName: "bolt.slash.fill", named: "flashUnavailable", in: Bundle(for: ScannerViewController.self), compatibleWith: nil)
            flashButton.image = flashOffImage
            flashButton.tintColor = UIColor.lightGray
        }
    }

    private func setupConstraints() {
        var quadViewConstraints = [NSLayoutConstraint]()
        var cancelButtonConstraints = [NSLayoutConstraint]()
        var shutterButtonConstraints = [NSLayoutConstraint]()
        var activityIndicatorConstraints = [NSLayoutConstraint]()

        quadViewConstraints = [
            quadView.topAnchor.constraint(equalTo: view.topAnchor),
            view.bottomAnchor.constraint(equalTo: quadView.bottomAnchor),
            view.trailingAnchor.constraint(equalTo: quadView.trailingAnchor),
            quadView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        ]

        shutterButtonConstraints = [
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.widthAnchor.constraint(equalToConstant: 65.0),
            shutterButton.heightAnchor.constraint(equalToConstant: 65.0)
        ]

        activityIndicatorConstraints = [
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ]
        
        setupImportButtonConstraints()

        if #available(iOS 11.0, *) {
            cancelButtonConstraints = [
                cancelButton.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 24.0),
                view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: cancelButton.bottomAnchor, constant: (65.0 / 2) - 10.0)
            ]

            let shutterButtonBottomConstraint = view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: shutterButton.bottomAnchor, constant: 8.0)
            shutterButtonConstraints.append(shutterButtonBottomConstraint)
        } else {
            cancelButtonConstraints = [
                cancelButton.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 24.0),
                view.bottomAnchor.constraint(equalTo: cancelButton.bottomAnchor, constant: (65.0 / 2) - 10.0)
            ]

            let shutterButtonBottomConstraint = view.bottomAnchor.constraint(equalTo: shutterButton.bottomAnchor, constant: 8.0)
            shutterButtonConstraints.append(shutterButtonBottomConstraint)
        }

        NSLayoutConstraint.activate(quadViewConstraints + cancelButtonConstraints + shutterButtonConstraints + activityIndicatorConstraints + importButtonConstraints)
    }

    // MARK: - Tap to Focus

    /// Called when the AVCaptureDevice detects that the subject area has changed significantly. When it's called, we reset the focus so the camera is no longer out of focus.
    @objc private func subjectAreaDidChange() {
        /// Reset the focus and exposure back to automatic
        do {
            try CaptureSession.current.resetFocusToAuto()
        } catch {
            let error = ImageScannerControllerError.inputDevice
            guard let captureSessionManager else { return }
            captureSessionManager.delegate?.captureSessionManager(captureSessionManager, didFailWithError: error)
            return
        }

        /// Previously removed the focus rectangle if one existed. Feature disabled.
    }

    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        guard let touch = touches.first else { return }
        let touchPoint = touch.location(in: view)
        let convertedTouchPoint: CGPoint = videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: touchPoint)

        // Hide visual focus rectangle UX. Keep tap-to-focus behavior only.
        do {
            try CaptureSession.current.setFocusPointToTapPoint(convertedTouchPoint)
        } catch {
            let error = ImageScannerControllerError.inputDevice
            guard let captureSessionManager else { return }
            captureSessionManager.delegate?.captureSessionManager(captureSessionManager, didFailWithError: error)
            return
        }
    }

    // MARK: - Actions

    @objc private func captureImage(_ sender: UIButton) {
        (navigationController as? ImageScannerController)?.flashToBlack()
        shutterButton.isUserInteractionEnabled = false
        captureSessionManager?.capturePhoto()
    }

    @objc private func toggleAutoScan() {
        if CaptureSession.current.isAutoScanEnabled {
            CaptureSession.current.isAutoScanEnabled = false
            autoScanButton.title = WeScanLocalization.localizedString(for: .manual, fallback: "Manual")
        } else {
            CaptureSession.current.isAutoScanEnabled = true
            autoScanButton.title = WeScanLocalization.localizedString(for: .auto, fallback: "Auto")
        }
    }

    @objc private func toggleFlash() {
        let state = CaptureSession.current.toggleFlash()

        let flashImage = UIImage(systemName: "bolt.fill", named: "flash", in: Bundle(for: ScannerViewController.self), compatibleWith: nil)
        let flashOffImage = UIImage(systemName: "bolt.slash.fill", named: "flashUnavailable", in: Bundle(for: ScannerViewController.self), compatibleWith: nil)

        switch state {
        case .on:
            flashEnabled = true
            flashButton.image = flashImage
            flashButton.tintColor = .yellow
        case .off:
            flashEnabled = false
            flashButton.image = flashImage
            flashButton.tintColor = .white
        case .unknown, .unavailable:
            flashEnabled = false
            flashButton.image = flashOffImage
            flashButton.tintColor = UIColor.lightGray
        }
    }

    @objc private func cancelImageScannerController() {
        guard let imageScannerController = navigationController as? ImageScannerController else { return }
        imageScannerController.imageScannerDelegate?.imageScannerControllerDidCancel(imageScannerController)
    }
    
    // MARK: - Import Button Setup
    
    private func setupImportButtonConstraints() {
        if #available(iOS 11.0, *) {
            importButtonConstraints = [
                importButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24.0),
                view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: importButton.bottomAnchor, constant: (65.0 / 2) - 10.0),
                importButton.widthAnchor.constraint(equalToConstant: 50.0),
                importButton.heightAnchor.constraint(equalToConstant: 50.0)
            ]
        } else {
            importButtonConstraints = [
                importButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24.0),
                view.bottomAnchor.constraint(equalTo: importButton.bottomAnchor, constant: (65.0 / 2) - 10.0),
                importButton.widthAnchor.constraint(equalToConstant: 50.0),
                importButton.heightAnchor.constraint(equalToConstant: 50.0)
            ]
        }
        print("📐 ScannerViewController: Import button constraints setup")
    }

    // MARK: - Import Actions
    
    @objc private func importButtonTapped() {
        print("🎯 ScannerViewController: Import button tapped, isMenuOpen: \(isImportMenuOpen)")
        
        if isImportMenuOpen {
            hideImportOptions()
        } else {
            showImportOptions()
        }
    }
    
    private func showImportOptions() {
        print("📱 ScannerViewController: Showing import options with modern animation")
        isImportMenuOpen = true
        
        // Transform import button to X with rotation animation
        let xImage = UIImage(systemName: "xmark") ?? UIImage(systemName: "multiply")
        
        // Show buttons
        filesButton.isHidden = false
        photosButton.isHidden = false
        
        // Position buttons above import button (closer positioning)
        NSLayoutConstraint.activate([
            filesButton.centerXAnchor.constraint(equalTo: importButton.centerXAnchor),
            filesButton.bottomAnchor.constraint(equalTo: importButton.topAnchor, constant: -20),
            filesButton.widthAnchor.constraint(equalToConstant: 44),
            filesButton.heightAnchor.constraint(equalToConstant: 44),
            
            photosButton.centerXAnchor.constraint(equalTo: importButton.centerXAnchor),
            photosButton.bottomAnchor.constraint(equalTo: filesButton.topAnchor, constant: -15),
            photosButton.widthAnchor.constraint(equalToConstant: 44),
            photosButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        // Modern spring animation
        UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: [.curveEaseOut]) {
            // Transform import button to X
            self.importButton.setImage(xImage, for: .normal)
            self.importButton.transform = CGAffineTransform(rotationAngle: .pi * 0.25)
            
            // Animate buttons in with scale and alpha
            self.filesButton.alpha = 1
            self.photosButton.alpha = 1
            self.filesButton.transform = CGAffineTransform.identity
            self.photosButton.transform = CGAffineTransform.identity
        } completion: { _ in
            // Add subtle bounce effect
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut]) {
                self.importButton.transform = CGAffineTransform(rotationAngle: .pi * 0.25).scaledBy(x: 1.1, y: 1.1)
            } completion: { _ in
                UIView.animate(withDuration: 0.1) {
                    self.importButton.transform = CGAffineTransform(rotationAngle: .pi * 0.25)
                }
            }
        }
        
        print("✨ ScannerViewController: Modern import options animated in")
    }
    
    private func hideImportOptions() {
        print("📱 ScannerViewController: Hiding import options with reverse animation")
        isImportMenuOpen = false
        
        let originalImage = UIImage(systemName: "plus") ?? UIImage(systemName: "add")
        
        // Reverse spring animation
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3, options: [.curveEaseIn]) {
            // Transform back to original button
            self.importButton.setImage(originalImage, for: .normal)
            self.importButton.transform = CGAffineTransform.identity
            
            // Scale down and fade out buttons
            self.filesButton.alpha = 0
            self.photosButton.alpha = 0
            self.filesButton.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
            self.photosButton.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        } completion: { _ in
            self.filesButton.isHidden = true
            self.photosButton.isHidden = true
            // Clean up constraints
            self.filesButton.removeFromSuperview()
            self.photosButton.removeFromSuperview()
            self.view.addSubview(self.filesButton)
            self.view.addSubview(self.photosButton)
            // Reset transforms for next time
            self.filesButton.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
            self.photosButton.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        }
        
        print("✨ ScannerViewController: Modern import options animated out")
    }
    
    @objc private func openFiles() {
        print("📁 ScannerViewController: Opening file picker")
        hideImportOptions()
        
        if #available(iOS 14.0, *) {
            let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.image, UTType.pdf], asCopy: true)
            documentPicker.delegate = self
            documentPicker.allowsMultipleSelection = false
            present(documentPicker, animated: true)
            print("📄 ScannerViewController: Document picker presented with PDF support (iOS 14+)")
        } else {
            let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.image", "com.adobe.pdf"], in: .import)
            documentPicker.delegate = self
            documentPicker.allowsMultipleSelection = false
            present(documentPicker, animated: true)
            print("📄 ScannerViewController: Document picker presented with PDF support (iOS <14)")
        }
    }
    
    @objc private func openPhotos() {
        print("📸 ScannerViewController: Opening photo picker")
        hideImportOptions()
        
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self
            imagePicker.sourceType = .photoLibrary
            imagePicker.allowsEditing = false
            present(imagePicker, animated: true)
            print("📷 ScannerViewController: Image picker presented")
        } else {
            print("❌ ScannerViewController: Photo library not available")
        }
    }
    
    private func processImportedImage(_ image: UIImage, preferFullFrameQuad: Bool = false) {
        print("🖼️ ScannerViewController: Processing imported image of size: \(image.size)")
        
        guard let imageScannerController = navigationController as? ImageScannerController else {
            print("❌ ScannerViewController: Could not get ImageScannerController")
            return
        }
        
        print("✅ ScannerViewController: Using imported image in scanner controller")
        imageScannerController.useImage(image: image, preferFullFrameQuad: preferFullFrameQuad)
    }
    
    private func isPDF(url: URL) -> Bool {
        if url.pathExtension.lowercased() == "pdf" { return true }
        if #available(iOS 14.0, *) {
            if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .pdf) {
                return true
            }
        }
        return false
    }

    private func convertPDFToImage(from url: URL) -> UIImage? {
        print("📄 ScannerViewController: Converting PDF to image from: \(url.lastPathComponent)")

        guard let document = PDFDocument(url: url),
              let page = document.page(at: 0) else {
            print("❌ ScannerViewController: Could not load PDF document")
            return nil
        }

        // Determine target rendering size while preserving original aspect
        let pageSize = page.bounds(for: .mediaBox).size
        let maxDimension: CGFloat = 2200
        let longSide = max(pageSize.width, pageSize.height)
        let scale = min(maxDimension / max(longSide, 1), 4.0)
        let targetSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)

        // Option A: Use PDFKit thumbnail (handles transforms/rotation/boxes)
        let thumbnail = page.thumbnail(of: targetSize, for: .mediaBox)
        if thumbnail.size.width > 1, thumbnail.size.height > 1 {
            print("✅ ScannerViewController: PDF converted via thumbnail with size: \(thumbnail.size)")
            return thumbnail
        }

        // Option B: Manual rendering using getDrawingTransform as a robust fallback
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let rendered = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(origin: .zero, size: targetSize))

            cg.saveGState()
            let drawingRect = CGRect(origin: .zero, size: targetSize)
            let transform = page.getDrawingTransform(.mediaBox, rect: drawingRect, rotate: 0, preserveAspectRatio: true)
            cg.concatenate(transform)
            page.draw(with: .mediaBox, to: cg)
            cg.restoreGState()
        }

        print("✅ ScannerViewController: PDF converted via transform with size: \(rendered.size)")
        return rendered
    }

}

extension ScannerViewController: RectangleDetectionDelegateProtocol {
    func captureSessionManager(_ captureSessionManager: CaptureSessionManager, didFailWithError error: Error) {

        activityIndicator.stopAnimating()
        shutterButton.isUserInteractionEnabled = true

        guard let imageScannerController = navigationController as? ImageScannerController else { return }
        imageScannerController.imageScannerDelegate?.imageScannerController(imageScannerController, didFailWithError: error)
    }

    func didStartCapturingPicture(for captureSessionManager: CaptureSessionManager) {
        activityIndicator.startAnimating()
        captureSessionManager.stop()
        shutterButton.isUserInteractionEnabled = false
    }

    func captureSessionManager(_ captureSessionManager: CaptureSessionManager, didCapturePicture picture: UIImage, withQuad quad: Quadrilateral?) {
        activityIndicator.stopAnimating()

        let editVC = EditScanViewController(image: picture, quad: quad)
        navigationController?.pushViewController(editVC, animated: false)

        shutterButton.isUserInteractionEnabled = true
    }

    func captureSessionManager(_ captureSessionManager: CaptureSessionManager, didDetectQuad quad: Quadrilateral?, _ imageSize: CGSize) {
        guard let quad else {
            // If no quad has been detected, we remove the currently displayed on on the quadView.
            quadView.removeQuadrilateral()
            return
        }

        let portraitImageSize = CGSize(width: imageSize.height, height: imageSize.width)

        let scaleTransform = CGAffineTransform.scaleTransform(forSize: portraitImageSize, aspectFillInSize: quadView.bounds.size)
        let scaledImageSize = imageSize.applying(scaleTransform)

        let rotationTransform = CGAffineTransform(rotationAngle: CGFloat.pi / 2.0)

        let imageBounds = CGRect(origin: .zero, size: scaledImageSize).applying(rotationTransform)

        let translationTransform = CGAffineTransform.translateTransform(fromCenterOfRect: imageBounds, toCenterOfRect: quadView.bounds)

        let transforms = [scaleTransform, rotationTransform, translationTransform]

        let transformedQuad = quad.applyTransforms(transforms)

        quadView.drawQuadrilateral(quad: transformedQuad, animated: true)
    }

}

// MARK: - UIDocumentPickerDelegate

extension ScannerViewController: UIDocumentPickerDelegate {
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        print("📄 ScannerViewController: Document picker did pick documents: \(urls)")

        guard let url = urls.first else {
            print("❌ ScannerViewController: No URL selected")
            return
        }

        // Dismiss the picker before heavy work to avoid UI transition conflicts
        controller.dismiss(animated: true) {
            print("📁 ScannerViewController: Loading file from URL: \(url.lastPathComponent)")
            print("🌍 ScannerViewController: Full URL path: \(url.path)")
            print("📂 ScannerViewController: URL is file URL: \(url.isFileURL)")

            // Kick off import on a background queue to keep UI responsive
            self.activityIndicator.startAnimating()

            DispatchQueue.global(qos: .userInitiated).async {
                let didStartScope = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartScope { url.stopAccessingSecurityScopedResource() }
                }

                var importedImage: UIImage?

                if self.isPDF(url: url) {
                    print("📄 ScannerViewController: Detected PDF, converting to image…")
                    importedImage = self.convertPDFToImage(from: url)
                } else {
                    do {
                        let data = try Data(contentsOf: url)
                        importedImage = UIImage(data: data)
                    } catch {
                        print("❌ ScannerViewController: Failed reading file data: \(error.localizedDescription)")
                    }
                }

                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    if let image = importedImage {
                        // When importing a PDF, prefer a full-frame quad, since documents may already be cropped.
                        let preferFullFrame = self.isPDF(url: url)
                        self.processImportedImage(image, preferFullFrameQuad: preferFullFrame)
                    } else {
                        print("❌ ScannerViewController: Could not import file: \(url.lastPathComponent)")
                    }
                }
            }
        }
    }
    
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print("📄 ScannerViewController: Document picker was cancelled")
    }
}

// MARK: - UIImagePickerControllerDelegate

extension ScannerViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        print("📸 ScannerViewController: Image picker did finish picking")
        
        picker.dismiss(animated: true) {
            if let image = info[.originalImage] as? UIImage {
                print("✅ ScannerViewController: Successfully got image from photo library")
                self.processImportedImage(image)
            } else {
                print("❌ ScannerViewController: Could not get image from picker")
            }
        }
    }
    
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        print("📸 ScannerViewController: Image picker was cancelled")
        picker.dismiss(animated: true)
    }
}
