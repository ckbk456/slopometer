import Foundation

/// A theme the person saved under their own name.
public struct SavedTheme: Codable, Equatable, Identifiable, Sendable {
    /// Also the theme's `presetID`, so the saved theme stays selected until it is edited.
    public var id: String
    public var name: String
    public var theme: ColorTheme

    public init(id: String = UUID().uuidString, name: String, theme: ColorTheme) {
        self.id = id
        self.name = name
        self.theme = theme
        self.theme.presetID = id
    }
}
