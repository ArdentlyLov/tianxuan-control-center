import SwiftUI

enum TianxuanFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
}
struct TianxuanTempShadow: View {
    let value: Double?
    var size: CGFloat = 96
    var body: some View { TempRing(value: value, size: size) }
}
