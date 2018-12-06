//
//  Group1.swift
//  KeePassium
//
//  Created by Andrei Popleteev on 2018-04-04.
//  Copyright © 2018 Andrei Popleteev. All rights reserved.
//

import Foundation

typealias Group1ID = Int32

/// Group in a kp1 database.
public class Group1: Group {
    private enum FieldID: UInt16 {
        case reserved  = 0x0000
        case groupID   = 0x0001
        case name      = 0x0002
        case creationTime     = 0x0003
        case lastModifiedTime = 0x0004
        case lastAccessTime   = 0x0005
        case expirationTime   = 0x0006
        case iconID           = 0x0007
        case groupLevel       = 0x0008
        case groupFlags       = 0x0009
        case end              = 0xFFFF
    }
    
    /// Fixed values of the Backup/RecycleBin group
    public static let backupGroupName = "Backup" // TODO: also use translated version
    public static let backupGroupIconID = IconID.trashBin
    
    private(set)  var id: Group1ID
    internal(set) var level: Int16
    private(set)  var flags: Int32 // some internal KeePass field
    //TODO: test if this (get/set) works correctly
    override public var canExpire: Bool {
        get { return expiryTime == Date.kp1Never }
        set {
            let never = Date.kp1Never
            if newValue {
                expiryTime = never
            } else {
                if expiryTime == never {
                    expiryTime = never
                } // else leave the original expiryTime
            }
        }
    }
    
    override init(database: Database) {
        id = -1
        level = 0
        flags = 0
        super.init(database: database)
    }
    deinit {
        erase()
    }
    override public func erase() {
        id = -1
        level = 0
        flags = 0
        super.erase()
    }
    
    /// Checks if a group name is reserved for internal use and cannot be assigned by the user.
    override public func isNameReserved(name: String) -> Bool {
        return name == Group1.backupGroupName
    }
    
    /// Creates a shallow copy of this group with the same properties, but no children items.
    /// The clone belongs to the same DB, but has no parent group.
    override public func clone() -> Group {
        let copy = Group1(database: database)
        apply(to: copy)
        return copy
    }
    
    /// Copies properties of this group to `target`. Complex properties are cloned.
    /// Does not affect children items, parent group or parent database.
    public func apply(to target: Group1) {
        super.apply(to: target)
        
        // Group1 specific stuff
        target.id = id
        target.level = level
        target.flags = flags
    }
    
    override public func add(group: Group) {
        super.add(group: group)
        (group as! Group1).level = self.level + 1
    }
    override public func remove(group: Group) {
        super.remove(group: group)
        // there is no suitable level value, so just reset to zero (root level) to simplify debug
        (group as! Group1).level = 0
    }
    override public func add(entry: Entry) {
        super.add(entry: entry)
        (entry as! Entry1).groupID = self.id
    }
    override public func remove(entry: Entry) {
        super.remove(entry: entry)
        // there is no suitable groupId, so just reset it to simplify debug
        (entry as! Entry1).groupID = -1
    }
    override public func moveEntry(entry: Entry) {
        super.moveEntry(entry: entry)
        (entry as! Entry1).groupID = self.id
    }
    
    /// Moves the group and all of its children to Backup group,
    /// subgroups are deleted.
    /// - Returns: true if successful, false otherwise.
    override public func moveToBackup() -> Bool {
        guard let parentGroup = self.parent else {
            Diag.warning("Failed to get parent group")
            return false
        }
        
        // Ensure backup group exists
        guard let _ = database.getBackupGroup(createIfMissing: true) else {
            Diag.warning("Failed to create backup group")
            return false
        }
        
        // detach this branch from the parent group
        parentGroup.remove(group: self)
        
        // flag the group and all its children deleted
        isDeleted = true
        var childGroups = [Group]()
        var childEntries = [Entry]()
        collectAllChildren(groups: &childGroups, entries: &childEntries)
        // kp1 does not backup subgroups, so move only entries
        for entry in childEntries {
            if !entry.moveToBackup() {
                Diag.warning("Failed on child entry")
                return false
            }
        }
        Eraser.erase(&childGroups)
        Eraser.erase(&childEntries)
        Diag.debug("moveToBackup OK")
        return true
    }

    /// Creates an entry in this group.
    /// - Returns: created entry
    override public func createEntry() -> Entry {
        let newEntry = Entry1(database: database)
        newEntry.uuid = UUID()
        
        // inherit the icon (or use default for default)
        if self.iconID == Group.defaultIconID {
            newEntry.iconID = Entry.defaultIconID
        } else {
            newEntry.iconID = self.iconID
        }
        
        // inherit the recycled status
        newEntry.isDeleted = isDeleted
        
        // set times
        newEntry.creationTime = Date.now
        newEntry.lastAccessTime = Date.now
        newEntry.lastModificationTime = Date.now
        // newEntry->setExpires(false); <- in kp1 is managed by setExpiryTime()
        newEntry.expiryTime = Date.kp1Never
        
        // set parent group
        newEntry.groupID = self.id
        self.add(entry: newEntry)
        return newEntry
    }
    
    /// Creates a group inside this group.
    /// - Returns: created group
    override public func createGroup() -> Group {
        let newGroup = Group1(database: database)
        newGroup.uuid = UUID()
        newGroup.flags = 0
        
        // create an ID that does not exist already
        newGroup.id = (database as! Database1).createNewGroupID()
        
        // inherit the icon and recycled status
        newGroup.iconID = self.iconID
        newGroup.isDeleted = self.isDeleted
        
        // set times
        newGroup.creationTime = Date.now
        newGroup.lastAccessTime = Date.now
        newGroup.lastModificationTime = Date.now
        // newGroup->setExpires(false); <- in kp1 is managed by setExpiryTime()
        newGroup.expiryTime = Date.kp1Never
        
        // set parent group
        newGroup.level = self.level + 1
        self.add(group: newGroup)
        return newGroup
    }
    
    /// Loads group fields from the stream.
    /// - Throws: Database1.FormatError
    func load(from stream: ByteArray.InputStream) throws {
        Diag.verbose("Loading group")
        erase()
        
        while stream.hasBytesAvailable {
            guard let fieldIDraw = stream.readUInt16() else {
                throw Database1.FormatError.prematureDataEnd
            }
            guard let fieldID = FieldID(rawValue: fieldIDraw) else {
                throw Database1.FormatError.corruptedField(fieldName: "Group/FieldID")
            }
            guard let _fieldSize = stream.readInt32() else {
                throw Database1.FormatError.prematureDataEnd
            }
            guard _fieldSize >= 0 else {
                throw Database1.FormatError.corruptedField(fieldName: "Group/FieldSize")
            }
            let fieldSize = Int(_fieldSize)
            
            //TODO: check fieldSize matches the amount of data we are actually reading
            switch fieldID {
            case .reserved:
                _ = stream.read(count: fieldSize) // just skipping whatever there was
            case .groupID:
                guard let _groupID: Group1ID = stream.readInt32() else {
                    throw Database1.FormatError.prematureDataEnd
                }
                self.id = _groupID
            case .name:
                guard let data = stream.read(count: fieldSize) else {
                    throw Database1.FormatError.prematureDataEnd
                }
                data.trim(toCount: data.count - 1) // drop the zero at the end
                guard let string = data.toString() else {
                    throw Database1.FormatError.corruptedField(fieldName: "Group/Name")
                }
                self.name = string
            case .creationTime:
                guard let rawTimeData = stream.read(count: Date.kp1TimestampSize) else {
                    throw Database1.FormatError.prematureDataEnd
                }
                guard let date = Date(kp1Bytes: rawTimeData) else {
                    throw Database1.FormatError.corruptedField(fieldName: "Group/CreationTime")
                }
                self.creationTime = date
            case .lastModifiedTime:
                guard let rawTimeData = stream.read(count: Date.kp1TimestampSize) else {
                    throw Database1.FormatError.prematureDataEnd
                }
                guard let date = Date(kp1Bytes: rawTimeData) else {
                    throw Database1.FormatError.corruptedField(fieldName: "Group/LastModifiedTime")
                }
                self.lastModificationTime = date
            case .lastAccessTime:
                guard let rawTimeData = stream.read(count: Date.kp1TimestampSize) else {
                    throw Database1.FormatError.prematureDataEnd
                }
                guard let date = Date(kp1Bytes: rawTimeData) else {
                    throw Database1.FormatError.corruptedField(fieldName: "Group/LastAccessTime")
                }
                self.lastAccessTime = date
            case .expirationTime:
                guard let rawTimeData = stream.read(count: Date.kp1TimestampSize) else {
                    throw Database1.FormatError.prematureDataEnd
                }
                guard let date = Date(kp1Bytes: rawTimeData) else {
                    throw Database1.FormatError.corruptedField(fieldName: "Group/ExpirationTime")
                }
                self.expiryTime = date
            case .iconID:
                guard let iconIDraw = stream.readUInt32(),
                    let _iconID = IconID(rawValue: iconIDraw) else {
                        throw Database1.FormatError.corruptedField(fieldName: "Group/IconID")
                }
                self.iconID = _iconID
            case .groupLevel:
                guard let _level = stream.readUInt16() else {
                    throw Database1.FormatError.corruptedField(fieldName: "Group/Level")
                }
                self.level = Int16(_level)
            case .groupFlags:
                guard let _flags = stream.readInt32() else {
                    throw Database1.FormatError.corruptedField(fieldName: "Group/Flags")
                }
                self.flags = _flags
            case .end:
                // group fields finished
                guard let _ = stream.read(count: fieldSize) else {
                    throw Database1.FormatError.prematureDataEnd
                }
                // a "Backup" group in the root is equivalent of kp2's "Recycle Bin"
                if (level == 0) && (name == Group1.backupGroupName) { //TODO: also check for translated "Backup"
                    self.isDeleted = true
                }
                return
            } // switch
        } // while
        
        // if we are here, there was no .end field
        Diag.warning("Group data missing the .end field")
        throw Database1.FormatError.prematureDataEnd
    }
    
    /// Writes group fields to the stream.
    func write(to stream: ByteArray.OutputStream) {
        func writeField(fieldID: FieldID, data: ByteArray, addTrailingZero: Bool = false) {
            stream.write(value: fieldID.rawValue)
            if addTrailingZero {
                // kp1 strings need an explicit \0 at the end
                stream.write(value: UInt32(data.count + 1))
                stream.write(data: data)
                stream.write(value: UInt8(0))
            } else {
                stream.write(value: UInt32(data.count))
                stream.write(data: data)
            }
        }

        writeField(fieldID: .groupID, data: self.id.data)
        writeField(fieldID: .name, data: ByteArray(utf8String: self.name)!, addTrailingZero: true)
        writeField(fieldID: .creationTime, data: self.creationTime.asKP1Bytes())
        writeField(fieldID: .lastModifiedTime, data: self.lastModificationTime.asKP1Bytes())
        writeField(fieldID: .lastAccessTime, data: self.lastAccessTime.asKP1Bytes())
        writeField(fieldID: .expirationTime, data: self.expiryTime.asKP1Bytes())
        writeField(fieldID: .iconID, data: self.iconID.rawValue.data)
        writeField(fieldID: .groupLevel, data: UInt16(self.level).data)
        writeField(fieldID: .groupFlags, data: self.flags.data)
        writeField(fieldID: .end, data: ByteArray())
    }
}