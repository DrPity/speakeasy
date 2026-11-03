import Foundation

/// Works out which input device ought to be active, based on what is present.
public enum DeviceSelectionPolicy {
    /// Priority order: the user's stored device, then the system default, then
    /// whichever comes first. Answers "" when no input device exists at all.
    public static func resolve(
        saved: String?,
        available: [String],
        systemDefault: String?
    ) -> String {
        if let saved, available.contains(saved) { return saved }
        if let systemDefault, available.contains(systemDefault) { return systemDefault }
        return available.first ?? ""
    }

    /// UID prefix of the throwaway aggregate Core Audio builds for an app whose
    /// audio engine pairs an input with an output ("CADefaultDeviceAggregate-
    /// <pid>-<n>"). Speakeasy's own engine creates one while capturing.
    public static let internalAggregatePrefix = "CADefaultDeviceAggregate"

    /// Whether a device should be left out of the microphone list: private
    /// aggregates belong to some app's audio engine (often our own) and are not
    /// something a person can meaningfully pick. Aggregates the user built in
    /// Audio MIDI Setup are not private and stay listed.
    public static func isHidden(uid: String, isPrivateAggregate: Bool) -> Bool {
        isPrivateAggregate || uid.hasPrefix(internalAggregatePrefix)
    }
}
