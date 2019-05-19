//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation
import KeePassiumLib

/// Helper class to manage reloading of `URLReference` attributes.
class FileInfoReloader {
    
    private let refreshQueue = DispatchQueue(
        label: "com.keepassium.FileInfoReloader",
        qos: .background,
        attributes: .concurrent)
    
    /// Refreshes `info` field of each given URL reference,
    /// by opening and immediately closing a corresponding UIDocument.
    /// Expensive operation: requires network traffic, and potentially
    /// downloads each changed file.
    ///
    /// - Parameters:
    ///   - refs: references to refresh
    ///   - completion: called (in main dispatch queue) after all references have been processed
    public func reload(_ refs: [URLReference], completion: @escaping (() -> Void)) {
        for urlRef in refs {
            refreshQueue.async { [weak self] in
                self?.refreshFileAttributes(urlRef: urlRef)
            }
        }
        refreshQueue.asyncAfter(deadline: .now(), qos: .background, flags: .barrier) {
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    /// Refreshes `info` attributes of the given URLReference,
    /// by quickly opening and closing the corresponding document.
    ///
    /// - Parameters:
    ///   - urlRef: file to refresh
    private func refreshFileAttributes(urlRef: URLReference)
    {
        guard let url = try? urlRef.resolve() else {
            // Refresh to reflect there was a problem.
            urlRef.refreshInfo()
            return
        }
        
        let document = FileDocument(fileURL: url)
        document.open(
            successHandler: {
                urlRef.refreshInfo()
                document.close(completionHandler: nil)
            },
            errorHandler: { (error) in
                urlRef.refreshInfo()
            }
        )
    }
}
