//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

/// Convenience helpers to enforce premium features
public extension Settings {
    
    // predefined limits for the free tier
    private static let heavyUseDatabaseLockTimeout = DatabaseLockTimeout.after5minutes
    private static let lightUseDatabaseLockTimeout = DatabaseLockTimeout.after1hour
    
    /// Returns the value of `databaseLockTimeout`, adjusted to the premium subscription status.
    var premiumDatabaseLockTimeout: Settings.DatabaseLockTimeout {
        let actualTimeout = Settings.current.databaseLockTimeout
        switch PremiumManager.shared.status {
        case .initialGracePeriod,
             .freeLightUse:
            return min(actualTimeout, Settings.lightUseDatabaseLockTimeout)
        case .freeHeavyUse:
            return min(actualTimeout, Settings.heavyUseDatabaseLockTimeout)
        case .subscribed,
             .lapsed:
            return actualTimeout
        }
    }
    
    var premiumIsBiometricAppLockEnabled: Bool {
        // unlimited
        return isBiometricAppLockEnabled
    }
    
    var premiumIsKeepKeyFileAssociations: Bool {
        // unlimited
        return isKeepKeyFileAssociations
    }
    
    func premiumGetKeyFileForDatabase(databaseRef: URLReference) -> URLReference? {
        // unlimited
        return getKeyFileForDatabase(databaseRef: databaseRef)
    }
    
    /// Checks whether given timeout value is available for the given premium status.
    func isAvailable(timeout: Settings.DatabaseLockTimeout, for status: PremiumManager.Status) -> Bool {
        switch status {
        case .initialGracePeriod,
             .freeLightUse:
            return timeout <= Settings.lightUseDatabaseLockTimeout
        case .freeHeavyUse:
            return timeout <= Settings.heavyUseDatabaseLockTimeout && timeout != .never
        case .subscribed,
             .lapsed:
            return true
        }
    }
}
