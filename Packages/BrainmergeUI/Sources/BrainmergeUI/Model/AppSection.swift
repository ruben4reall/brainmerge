/// The window's four screens, in the sidebar's order. Kept with the model: the menu bar and the app menu ask for one
/// through AppModel.requestedScreen.
public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case accounts, memory, usage, settings
    public var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// Cmd-1 to Cmd-4, in the sidebar's order.
    var digit: Character { Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1)) }
    var symbol: String {
        switch self { case .accounts: "person.2"; case .memory: "brain"; case .usage: "chart.bar"; case .settings: "slider.horizontal.3" }
    }
}
