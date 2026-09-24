import SwiftUI
import BrainmergeCore

/// A colored sphere with the account's initial, or its photo.
public struct OrbView: View {
    public var name: String
    public var tint: Tint
    public var logo: NSImage?
    public var size: CGFloat
    public init(name: String, tint: Tint, logo: NSImage? = nil, size: CGFloat = 72) {
        self.name = name; self.tint = tint; self.logo = logo; self.size = size
    }

    public static func initial(for name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "?" }
        return String(first).uppercased()
    }

    public var body: some View {
        let color = Theme.color(for: tint)
        ZStack {
            Circle().fill(color.opacity(0.9))
            if let logo {
                Image(nsImage: logo).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
            } else {
                Text(Self.initial(for: name))
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}
