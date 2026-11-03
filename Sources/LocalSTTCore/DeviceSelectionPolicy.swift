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
}
