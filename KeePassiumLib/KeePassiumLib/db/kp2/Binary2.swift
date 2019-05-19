//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation
//import AEXML

/// Binary data stored in DB metadata
public class Binary2: Eraseable {
    public typealias ID = Int

    /// The ID is used to refer to binaries from entries.
    private(set) var id: Binary2.ID
    
    /// `data` must always be decrypted (`isProtected` is only a recommendation),
    /// but can be compressed (`isCompressed` is applied only on export operations)
    private(set) var data: ByteArray
    
    /// True iff the `data` is gzipped
    private(set) var isCompressed: Bool
    
    /// True iff the binary is labelled as protected.
    /// Some apps use it to encrypt `data` while it is in memory (e.g. KeePass 2)
    /// others ignore it for performance reasons (e.g. KeePassDroid)
    /// Like other mobile apps, KeePassium does not enforce memory protection.
    private(set) var isProtected: Bool
    
    /// KP2 v4 inner header flags
    public var flags: UInt8 {
        return isProtected ? 1 : 0
    }
    
    /// - Parameters:
    ///   - id: ID in binary pool
    ///   - data: *decrypted* but possibly compressed data.
    ///         Alternatively, can be decrypted after initialization, using `decrypt`.
    ///   - isCompressed: `true` iff `data` is compressed
    ///   - isProtected: `true` iff `data` should be encrypted/decrypted in read/write operations
    init(id: Binary2.ID, data: ByteArray, isCompressed: Bool, isProtected: Bool) {
        self.id = id
        self.data = data.clone()
        self.isCompressed = isCompressed
        self.isProtected = isProtected
    }
    
    deinit {
        erase()
    }
    
    public func erase() {
        id = -1
        isCompressed = false
        isProtected = false
        data.erase()
    }
    
    /// - Throws: `Xml2.ParsingError`, `ProgressInterruption`
    static func load(xml: AEXMLElement, streamCipher: StreamCipher) throws -> Binary2 {
        assert(xml.name == Xml2.binary)
        Diag.verbose("Loading XML: binary")
        
        let idString = xml.attributes[Xml2.id]
        guard let id = Int(idString) else {
            Diag.error("Cannot parse Meta/Binary/ID as Int")
            throw Xml2.ParsingError.malformedValue(tag: "Meta/Binary/ID", value: idString)
        }
        let isCompressedString = xml.attributes[Xml2.compressed]
        let isProtectedString = xml.attributes[Xml2.protected]
        let isCompressed: Bool = Bool(string: isCompressedString ?? "")
        let isProtected: Bool = Bool(string: isProtectedString ?? "")
        let base64 = xml.value ?? ""
        guard var data = ByteArray(base64Encoded: base64) else {
            Diag.error("Cannot parse Meta/Binary/Value as Base64 string")
            throw Xml2.ParsingError.malformedValue(tag: "Meta/Binary/ValueBase64", value: String(base64.prefix(16)))
        }
        // Note: data can actually be empty
        
        if isProtected {
            // `data` is stored in plain text, so decrypt it
            Diag.verbose("Decrypting binary")
            data = try streamCipher.decrypt(data: data, progress: nil) // throws ProgressInterruption
        }
        
        return Binary2(id: id, data: data, isCompressed: isCompressed, isProtected: isProtected)
    }
    
    /// Throws: `ProgressInterruption`
    func toXml(streamCipher: StreamCipher) throws -> AEXMLElement {
        Diag.verbose("Generating XML: binary")
        var attributes = [
            Xml2.id: String(id),
            Xml2.compressed: isCompressed ? Xml2._true : Xml2._false
        ]
        
        let value: ByteArray
        if isProtected {
            Diag.verbose("Encrypting binary")
            value = try streamCipher.encrypt(data: data, progress: nil) // throws ProgressInterruption
            attributes[Xml2.protected] = Xml2._true
        } else {
            value = data
        }
        return AEXMLElement(
            name: Xml2.binary,
            value: value.base64EncodedString(),
            attributes: attributes)
    }
}
