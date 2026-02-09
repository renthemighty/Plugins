// ShareViewController.swift
// ShareExtension
//
// Minimal share extension skeleton for Kira receipt ingestion.
// Receives shared images (JPEG/PNG) from other apps, saves them to the
// app group container so the main Kira app can pick them up on next launch.
//
// NOTE: This file alone is not sufficient. You must manually add a
// "Share Extension" target in Xcode (File > New > Target > Share Extension)
// and replace the generated ShareViewController with this file.
// Ensure the target's bundle identifier is e.g. com.kira.receipts.ShareExtension
// and that both the main app and this extension belong to the same app group
// (group.com.kira.receiptshare). The main app's Runner.entitlements must also
// include the com.apple.security.application-groups entitlement with the same
// group identifier.

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    // MARK: - App Group

    /// Shared app group container used to pass images from the extension to the main app.
    private let appGroupIdentifier = "group.com.kira.receiptshare"

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        handleSharedItems()
    }

    // MARK: - Shared Item Handling

    private func handleSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            completeRequest()
            return
        }

        let typeIdentifiers = [
            UTType.jpeg.identifier,
            UTType.png.identifier,
        ]

        var pendingCount = 0

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                for typeIdentifier in typeIdentifiers {
                    if provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                        pendingCount += 1
                        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] data, error in
                            defer {
                                pendingCount -= 1
                                if pendingCount == 0 {
                                    self?.completeRequest()
                                }
                            }

                            guard error == nil else { return }
                            self?.saveToAppGroup(data: data, typeIdentifier: typeIdentifier)
                        }
                        break // Only load once per provider
                    }
                }
            }
        }

        if pendingCount == 0 {
            completeRequest()
        }
    }

    // MARK: - Persistence

    /// Saves the shared image data to the app group container's "ShareInbox" directory.
    private func saveToAppGroup(data: Any?, typeIdentifier: String) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return }

        let inboxURL = containerURL.appendingPathComponent("ShareInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        let fileExtension: String
        if typeIdentifier == UTType.png.identifier {
            fileExtension = "png"
        } else {
            fileExtension = "jpg"
        }

        let fileName = UUID().uuidString + "." + fileExtension
        let fileURL = inboxURL.appendingPathComponent(fileName)

        // The data can arrive as Data, URL, or UIImage depending on the source app.
        if let url = data as? URL {
            try? FileManager.default.copyItem(at: url, to: fileURL)
        } else if let imageData = data as? Data {
            try? imageData.write(to: fileURL)
        } else if let image = data as? UIImage {
            let imageData: Data?
            if typeIdentifier == UTType.png.identifier {
                imageData = image.pngData()
            } else {
                imageData = image.jpegData(compressionQuality: 0.95)
            }
            try? imageData?.write(to: fileURL)
        }
    }

    // MARK: - Completion

    private func completeRequest() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
