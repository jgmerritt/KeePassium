//
//  Entry.swift
//  KeePassium
//
//  Created by Andrei Popleteev on 2018-03-05.
//  Copyright © 2018 Andrei Popleteev. All rights reserved.
//

import Foundation

public class EntryField: Eraseable {
    public static let title    = "Title"
    public static let userName = "UserName"
    public static let password = "Password"
    public static let url      = "URL"
    public static let notes    = "Notes"
    public static let standardNames = [title, userName, password, url, notes]
    
    public var name: String
    public var value: String
    public var isProtected: Bool
    /// True if field's name is one of the fixed/standard KP2 fields.
    public var isStandardField: Bool {
        return EntryField.isStandardName(name: self.name)
    }
    public static func isStandardName(name: String) -> Bool {
        return standardNames.contains(name)
    }
    
    public init(name: String, value: String, isProtected: Bool) {
        self.name = name
        self.value = value
        self.isProtected = isProtected
    }
    deinit {
        erase()
    }
    
    public func clone() -> EntryField {
        return EntryField(name: self.name, value: self.value, isProtected: self.isProtected)
    }
    
    public func erase() {
        name.erase()
        value.erase()
        isProtected = false
    }
    /// Checks if the field name/value contains given `text`.
    public func matches(query: SearchQuery) -> Bool {
        return name.localizedCaseInsensitiveContains(query.text) || value.localizedCaseInsensitiveContains(query.text)
    }
}

public class Entry: Eraseable {
    public static let defaultIconID = IconID.key
    
    public unowned let database: Database
    public weak var parent: Group?
    public var uuid: UUID
    public var iconID: IconID

    public var fields: [EntryField]
    public var isSupportsExtraFields: Bool { get { return false } }
    public var title: String    {
        get{ return getField(with: EntryField.title)?.value ?? "" }
        set { setField(name: EntryField.title, value: newValue) }
    }
    public var userName: String {
        get{ return getField(with: EntryField.userName)?.value ?? "" }
        set { setField(name: EntryField.userName, value: newValue) }
    }
    public var password: String {
        get{ return getField(with: EntryField.password)?.value ?? "" }
        set { setField(name: EntryField.password, value: newValue) }
    }
    public var url: String {
        get{ return getField(with: EntryField.url)?.value ?? "" }
        set { setField(name: EntryField.url, value: newValue) }
    }
    public var notes: String {
        get{ return getField(with: EntryField.notes)?.value ?? "" }
        set { setField(name: EntryField.notes, value: newValue) }
    }

    public internal(set) var creationTime: Date
    public internal(set) var lastModificationTime: Date
    public internal(set) var lastAccessTime: Date
    public var expiryTime: Date
    /// Is this entry expirable? (`false` by default)
    /// This property is overriden by all subclasses.
    public var canExpire: Bool {
        get { return false }
        set { /* ignored */ }
    }
    public var isExpired: Bool { return canExpire && (Date() > expiryTime) }
    /// True if the entry is in Recycle Bin
    public var isDeleted: Bool
    
    /// Attachments of this entry
    public var attachments: Array<Attachment>
    
    public var description: String { return "Entry[\(title)]" }
    
    init(database: Database) {
        self.database = database
        parent = nil
        attachments = []
        fields = []

        uuid = UUID.ZERO
        iconID = Entry.defaultIconID
        isDeleted = false
        
        let now = Date()
        creationTime = now
        lastModificationTime = now
        lastAccessTime = now
        expiryTime = now
        
        canExpire = false
        populateStandardFields()
    }
    
    deinit {
        erase()
    }
    
    public func erase() {
        attachments.erase()
        fields.erase()
        populateStandardFields()
        
        uuid = UUID.ZERO
        iconID = Entry.defaultIconID
        isDeleted = false
        canExpire = false

        parent = nil

        let now = Date()
        creationTime = now
        lastModificationTime = now
        lastAccessTime = now
        expiryTime = now
    }
    
    /// Builds an appropriate child instance of `EntryField`.
    func makeEntryField(name: String, value: String, isProtected: Bool) -> EntryField {
        return EntryField(name: name, value: value, isProtected: isProtected)
    }
    
    /// Sets standard/fixed fields to empty values.
    public func populateStandardFields() {
        setField(name: EntryField.title, value: "")
        setField(name: EntryField.userName, value: "")
        setField(name: EntryField.password, value: "", isProtected: true)
        setField(name: EntryField.url, value: "")
        setField(name: EntryField.notes, value: "")
    }
    
    /// Adds a named field (updates if `name` already exists).
    /// When `isProtected` is `nil`, it will not be updated (when adding, defaults to `false`)
    public func setField(name: String, value: String, isProtected: Bool? = nil) {
        for field in fields {
            if field.name == name {
                field.value = value
                if let isProtected = isProtected {
                    field.isProtected = isProtected
                } else {
                    // isProtected should remain unchanged
                }
                return
            }
        }
        // If undefined, memory protection defaults to `false`, because:
        // - for standard fields it will be updated according to DB Meta protection flags (on save)
        // - for other fields, it will be changed by some other method.
        fields.append(makeEntryField(name: name, value: value, isProtected: isProtected ?? false))
    }

    /// - Returns: first field with given name
    public func getField(with name: String) -> EntryField? {
        for field in fields {
            if field.name == name {
                return field
            }
        }
        return nil
    }
    
    /// Deletes field with the given name (ignores errors) without making backup.
    public func removeField(_ field: EntryField) {
        if let index = fields.index(where: {$0 === field}) {
            fields.remove(at: index)
        }
    }


    /// Loads the given file and attaches it to the entry.
    /// Makes a backup of the initial entry state.
    /// Returns true if successful, false in case of any error.
    ///
    /// (A pure virtual method, must be overriden)
    public func attachFile(filePath: String) -> Bool {
        fatalError("Pure virtual method")
    }
    
    /// Adds an attachment
    public func addAttachment(attachment: Attachment) {
        attachments.append(attachment)
    }
    
    /// Returns a new entry instance with the same property values.
    /// (A pure virtual method, must be overriden)
    public func clone() -> Entry {
        fatalError("Pure virtual method")
    }
    
    /// Copies properties of this entry to the `target`.
    /// Complex properties are cloned.
    /// Does not affect group membership.
    public func apply(to target: Entry) {
        // target.database and target.parent are not changed
        target.uuid = uuid
        target.iconID = iconID
        target.isDeleted = isDeleted
        target.lastModificationTime = lastModificationTime
        target.creationTime = creationTime
        target.lastAccessTime = lastAccessTime
        target.expiryTime = expiryTime
        target.canExpire = canExpire
        
        target.attachments.removeAll()
        for att in attachments {
            target.attachments.append(att.clone())
        }
        target.fields.removeAll()
        for field in fields {
            target.fields.append(field.clone())
        }
    }
    
    /// Makes a backup copy of the current values/state of the entry.
    /// Actual behavior is DB version specific.
    /// (A pure virtual method, must be overriden)
    /// - Returns: true if successful, false otherwise.
    public func backupState() -> Bool {
        fatalError("Pure virtual method")
    }
    
    /// Moves the entry to the Backup/Recycle Bin group.
    /// Actual behavior is DB version specific.
    /// (A pure virtual method, must be overriden)
    /// - Returns: true if successful, false otherwise.
    public func moveToBackup() -> Bool {
        fatalError("Pure virtual method")
    }
    
    /// Updates last access timestamp to current time
    public func accessed() {
        lastAccessTime = Date.now
    }
    /// Updates last modification timestamp to current time
    public func modified() {
        accessed()
        lastModificationTime = Date.now
    }
    
    /// Removes the entry from the parent group. Does NOT make a copy in Backup/Recycle Bin.
    public func deleteWithoutBackup() {
        parent?.remove(entry: self)
    }
    
    /// Returns the names of the groups this entry is in, much like a file system path.
    public func getGroupPath() -> String {
        var groupNames = Array<String>()
        var parentGroup = self.parent
        while parentGroup != nil {
            groupNames.append(parentGroup!.name)
            parentGroup = parentGroup!.parent
        }
        return groupNames.reversed().joined(separator: "/")
    }
    
    /// Checks if the entry matches given search `query`.
    /// (That is, each query word is present in at least one of the fields
    /// [title, user name, url, notes, attachment names].)
    public func matches(query: SearchQuery) -> Bool {
        for word in query.textWords {
            if title.contains(word) || userName.contains(word) || url.contains(word) || notes.contains(word) {
                continue
            }
            var wordFound = false
            for att in attachments {
                if att.name.contains(word) {
                    wordFound = true
                    break
                }
            }
            if !wordFound { return false }
        }
        return true
    }
}


extension Array where Element == Entry {
    mutating func remove(_ entry: Entry) {
        if let index = index(where: {$0 === entry}) {
            remove(at: index)
        }
    }
}
