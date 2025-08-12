//
//  WeScanLocalization.swift
//  WeScan
//
//  Created for injectable localization support
//  Allows host app to provide translations via LanguageManager
//

import Foundation

public protocol WeScanLocalizationProviding: AnyObject {
    func localizedString(for key: WeScanLocalization.Key) -> String
}

public enum WeScanLocalization {
    public enum Key {
        case confirm
        case cancel
        case retake
        case save
        case next
        case back
        case edit
        case scan
        case crop
        case rotate
        case enhance
        case done
        case flashOn
        case flashOff
        case auto
        case manual
        case cameraUnavailableTitle
        case cameraUnavailableMessage
        case permissionsDeniedTitle
        case permissionsDeniedMessage
        case ok
        case editScanTitle
        case flash
        case scanningCancel
        // Add any other visible UI labels as needed
    }
    
    // The host app sets this provider at startup
    public static weak var provider: WeScanLocalizationProviding?
    
    // Convenience method to get localized string with fallback
    public static func localizedString(for key: Key, fallback: String) -> String {
        return provider?.localizedString(for: key) ?? fallback
    }
}