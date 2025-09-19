//
//  EditScanViewController.swift
//  WeScan
//
//  Created by Boris Emorine on 2/12/18.
//  Copyright © 2018 WeTransfer. All rights reserved.
//

import AVFoundation
import UIKit

/// The `EditScanViewController` offers an interface for the user to edit the detected quadrilateral.
final class EditScanViewController: UIViewController {

    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.clipsToBounds = true
        imageView.isOpaque = true
        imageView.image = image
        imageView.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var quadView: QuadrilateralView = {
        let quadView = QuadrilateralView()
        quadView.editable = true
        quadView.translatesAutoresizingMaskIntoConstraints = false
        return quadView
    }()

    private lazy var nextButton: UIBarButtonItem = {
        let title = NSLocalizedString("wescan.edit.button.next",
                                      tableName: nil,
                                      bundle: Bundle(for: EditScanViewController.self),
                                      value: "Next",
                                      comment: "A generic next button"
        )
        let button = UIBarButtonItem(title: title, style: .plain, target: self, action: #selector(pushReviewController))
        button.tintColor = navigationController?.navigationBar.tintColor
        return button
    }()

    private lazy var cancelButton: UIBarButtonItem = {
        let title = WeScanLocalization.localizedString(for: .cancel, fallback: "Cancel")
        let button = UIBarButtonItem(title: title, style: .plain, target: self, action: #selector(cancelButtonTapped))
        button.tintColor = navigationController?.navigationBar.tintColor
        return button
    }()
    
    private lazy var customBackButton: UIButton = {
        let button = UIButton(type: .system)
        
        // Configuration de l'icône chevron.left
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let image = UIImage(systemName: "chevron.left", withConfiguration: config)
        button.setImage(image, for: .normal)
        
        // Couleurs (équivalent AppColors.textPrimary et AppColors.cardBackground)
        button.tintColor = .white // textPrimary en mode sombre
        button.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.2) // cardBackground equivalent
        
        // Style circulaire 44x44
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        button.layer.cornerRadius = 22
        button.clipsToBounds = true
        
        // Action
        button.addTarget(self, action: #selector(customBackButtonTapped), for: .touchUpInside)
        
        // Effet de scale (équivalent ScaleButtonStyle)
        button.addTarget(self, action: #selector(buttonTouchDown), for: .touchDown)
        button.addTarget(self, action: #selector(buttonTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        
        return button
    }()

    /// The image the quadrilateral was detected on.
    private let image: UIImage

    /// The detected quadrilateral that can be edited by the user. Uses the image's coordinates.
    private var quad: Quadrilateral

    private var zoomGestureController: ZoomGestureController!

    private var quadViewWidthConstraint = NSLayoutConstraint()
    private var quadViewHeightConstraint = NSLayoutConstraint()
    
    private lazy var confirmButton: UIButton = {
        let button = UIButton(type: .system)
        let confirmTitle = WeScanLocalization.localizedString(for: .confirm, fallback: "Valider")
        print("🔧 EditScanViewController: Setting confirm button title to: '\(confirmTitle)'")
        button.setTitle(confirmTitle, for: .normal)
        
        // Glutax V2 theme colors
        // Use dynamic AccentColor; final variant is updated against system style (not forced dark)
        button.backgroundColor = UIColor(named: "AccentColor") ?? UIColor.systemOrange
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.layer.shadowOpacity = 0.1
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(confirmEditTapped), for: .touchUpInside)
        
        // S'assurer que le bouton reçoit les touches
        button.isUserInteractionEnabled = true
        button.layer.zPosition = 1000
        if #available(iOS 13.0, *) {
            // Don't inherit forced dark from parent; keep it aligned to system style
            button.overrideUserInterfaceStyle = .unspecified
        }
        return button
    }()

    // MARK: - Life Cycle

    init(image: UIImage, quad: Quadrilateral?, rotateImage: Bool = true) {
        self.image = rotateImage ? image.applyingPortraitOrientation() : image
        self.quad = quad ?? EditScanViewController.defaultQuad(forImage: image)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = .dark
        }
        view.backgroundColor = .black
        navigationController?.navigationBar.barStyle = .black
        navigationController?.navigationBar.tintColor = .white
        setupViews()
        setupConstraints()
        let editTitle = WeScanLocalization.localizedString(for: .editScanTitle, fallback: "Edit Scan")
        print("🔧 EditScanViewController: Setting navigation title to: '\(editTitle)'")
        title = editTitle
        navigationItem.rightBarButtonItem = nil
        if let firstVC = self.navigationController?.viewControllers.first, firstVC == self {
            navigationItem.leftBarButtonItem = cancelButton
        } else {
            let customBackBarButtonItem = UIBarButtonItem(customView: customBackButton)
            navigationItem.leftBarButtonItem = customBackBarButtonItem
            navigationItem.hidesBackButton = true
        }

        zoomGestureController = ZoomGestureController(image: image, quadView: quadView)

        let touchDown = UILongPressGestureRecognizer(target: zoomGestureController, action: #selector(zoomGestureController.handle(pan:)))
        touchDown.minimumPressDuration = 0
        touchDown.delegate = self
        view.addGestureRecognizer(touchDown)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Disable interactive swipe-back to avoid accidental pop when dragging the left corner
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        
        // Équivalent de .navigationBarHidden(true) en SwiftUI pour masquer l'effet liquid glass
        navigationController?.navigationBar.isHidden = true
        
        navigationController?.navigationBar.isTranslucent = false
        navigationController?.navigationBar.prefersLargeTitles = false
        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .black
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
            appearance.shadowColor = .clear
            navigationController?.navigationBar.standardAppearance = appearance
            navigationController?.navigationBar.compactAppearance = appearance
            navigationController?.navigationBar.scrollEdgeAppearance = appearance
        } else {
            navigationController?.navigationBar.barTintColor = .black
            navigationController?.navigationBar.shadowImage = UIImage()
        }
        navigationController?.view.backgroundColor = .black
        updateConfirmButtonAccentForSystemStyle()
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        adjustQuadViewConstraints()
        displayQuad()
    }

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateConfirmButtonAccentForSystemStyle()
    }

    private func updateConfirmButtonAccentForSystemStyle() {
        guard #available(iOS 13.0, *) else { return }
        // Try to resolve against the windowScene (system) style, not the VC's forced dark
        let systemStyle = view.window?.windowScene?.traitCollection.userInterfaceStyle ?? .unspecified
        let trait = UITraitCollection(userInterfaceStyle: systemStyle)
        if let accent = UIColor(named: "AccentColor", in: Bundle(for: EditScanViewController.self), compatibleWith: trait) {
            confirmButton.backgroundColor = accent
        }
        // Make the button explicitly use that style
        confirmButton.overrideUserInterfaceStyle = systemStyle
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Remettre la navigation bar visible pour les autres écrans
        navigationController?.navigationBar.isHidden = false

        // Work around for an iOS 11.2 bug where UIBarButtonItems don't get back to their normal state after being pressed.
        navigationController?.navigationBar.tintAdjustmentMode = .normal
        navigationController?.navigationBar.tintAdjustmentMode = .automatic

        // Re-enable interactive swipe-back for other screens
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    // MARK: - Setups

    private func setupViews() {
        view.addSubview(imageView)
        view.addSubview(quadView)
        view.addSubview(confirmButton)
    }

    private func setupConstraints() {
        var imageViewConstraints: [NSLayoutConstraint] = []
        if #available(iOS 11.0, *) {
            imageViewConstraints = [
                imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                imageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: confirmButton.topAnchor, constant: -12),
                imageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
            ]
        } else {
            imageViewConstraints = [
                imageView.topAnchor.constraint(equalTo: view.topAnchor),
                imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: confirmButton.topAnchor, constant: -12),
                imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
            ]
        }

        quadViewWidthConstraint = quadView.widthAnchor.constraint(equalToConstant: 0.0)
        quadViewHeightConstraint = quadView.heightAnchor.constraint(equalToConstant: 0.0)

        let quadViewConstraints = [
            quadView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            quadView.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            quadViewWidthConstraint,
            quadViewHeightConstraint
        ]

        let confirmButtonConstraints = [
            confirmButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            confirmButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            confirmButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            confirmButton.heightAnchor.constraint(equalToConstant: 56)
        ]
        
        NSLayoutConstraint.activate(quadViewConstraints + imageViewConstraints + confirmButtonConstraints)
    }

    // MARK: - Actions
    @objc func cancelButtonTapped() {
        if let imageScannerController = navigationController as? ImageScannerController {
            imageScannerController.imageScannerDelegate?.imageScannerControllerDidCancel(imageScannerController)
        }
    }
    
    @objc private func customBackButtonTapped() {
        // Action de retour - pop du view controller actuel
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func buttonTouchDown(_ sender: UIButton) {
        // Effet de scale au touch down (équivalent ScaleButtonStyle)
        UIView.animate(withDuration: 0.1, delay: 0, options: [.allowUserInteraction, .curveEaseInOut], animations: {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        })
    }
    
    @objc private func buttonTouchUp(_ sender: UIButton) {
        // Retour à la taille normale au touch up
        UIView.animate(withDuration: 0.1, delay: 0, options: [.allowUserInteraction, .curveEaseInOut], animations: {
            sender.transform = CGAffineTransform.identity
        })
    }

    

    @objc func pushReviewController() {
        guard let quad = quadView.quad,
            let ciImage = CIImage(image: image) else {
                if let imageScannerController = navigationController as? ImageScannerController {
                    let error = ImageScannerControllerError.ciImageCreation
                    imageScannerController.imageScannerDelegate?.imageScannerController(imageScannerController, didFailWithError: error)
                }
                return
        }
        let cgOrientation = CGImagePropertyOrientation(image.imageOrientation)
        let orientedImage = ciImage.oriented(forExifOrientation: Int32(cgOrientation.rawValue))
        let scaledQuad = quad.scale(quadView.bounds.size, image.size)
        self.quad = scaledQuad

        // Cropped Image
        var cartesianScaledQuad = scaledQuad.toCartesian(withHeight: image.size.height)
        cartesianScaledQuad.reorganize()

        let filteredImage = orientedImage.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": CIVector(cgPoint: cartesianScaledQuad.bottomLeft),
            "inputTopRight": CIVector(cgPoint: cartesianScaledQuad.bottomRight),
            "inputBottomLeft": CIVector(cgPoint: cartesianScaledQuad.topLeft),
            "inputBottomRight": CIVector(cgPoint: cartesianScaledQuad.topRight)
        ])

        let croppedImage = UIImage.from(ciImage: filteredImage)
        // Enhanced Image
        let enhancedImage = filteredImage.applyingAdaptiveThreshold()?.withFixedOrientation()
        let enhancedScan = enhancedImage.flatMap { ImageScannerScan(image: $0) }

        let results = ImageScannerResults(
            detectedRectangle: scaledQuad,
            originalScan: ImageScannerScan(image: image),
            croppedScan: ImageScannerScan(image: croppedImage),
            enhancedScan: enhancedScan
        )

        // Appel direct du delegate pour supprimer l'écran de review
        if let imageScannerController = navigationController as? ImageScannerController {
            imageScannerController.imageScannerDelegate?.imageScannerController(imageScannerController, didFinishScanningWithResults: results)
        }
    }
    
    @objc private func confirmEditTapped() {
        // Utilise la même logique que le bouton Next original
        pushReviewController()
    }

    private func displayQuad() {
        let imageSize = image.size
        let imageFrame = CGRect(
            origin: quadView.frame.origin,
            size: CGSize(width: quadViewWidthConstraint.constant, height: quadViewHeightConstraint.constant)
        )

        let scaleTransform = CGAffineTransform.scaleTransform(forSize: imageSize, aspectFillInSize: imageFrame.size)
        let transforms = [scaleTransform]
        let transformedQuad = quad.applyTransforms(transforms)

        quadView.drawQuadrilateral(quad: transformedQuad, animated: false)
    }

    /// The quadView should be lined up on top of the actual image displayed by the imageView.
    /// Since there is no way to know the size of that image before run time, we adjust the constraints
    /// to make sure that the quadView is on top of the displayed image.
    private func adjustQuadViewConstraints() {
        // Leave safe space above the confirm button to avoid overlap for tall documents
        let availableBounds = imageView.bounds.inset(by: UIEdgeInsets(top: 0, left: 0, bottom: 8, right: 0))
        // Ensure the full image fits within the imageView bounds (below the navigation bar)
        let frame = AVMakeRect(aspectRatio: image.size, insideRect: availableBounds)
        quadViewWidthConstraint.constant = frame.size.width
        quadViewHeightConstraint.constant = frame.size.height
    }

    /// Generates a `Quadrilateral` object that's centered and 90% of the size of the passed in image.
    private static func defaultQuad(forImage image: UIImage) -> Quadrilateral {
        let topLeft = CGPoint(x: image.size.width * 0.05, y: image.size.height * 0.05)
        let topRight = CGPoint(x: image.size.width * 0.95, y: image.size.height * 0.05)
        let bottomRight = CGPoint(x: image.size.width * 0.95, y: image.size.height * 0.95)
        let bottomLeft = CGPoint(x: image.size.width * 0.05, y: image.size.height * 0.95)

        let quad = Quadrilateral(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft)

        return quad
    }

    /// A full-frame quad that matches the complete image bounds.
    static func fullFrameQuad(forImage image: UIImage) -> Quadrilateral {
        let topLeft = CGPoint(x: 0, y: 0)
        let topRight = CGPoint(x: image.size.width, y: 0)
        let bottomRight = CGPoint(x: image.size.width, y: image.size.height)
        let bottomLeft = CGPoint(x: 0, y: image.size.height)
        return Quadrilateral(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft)
    }

}

// MARK: - UIGestureRecognizerDelegate
extension EditScanViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Ne pas traiter les touches sur le bouton Valider
        return touch.view != confirmButton
    }
}
