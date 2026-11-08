import SwiftUI
struct TianxuanLogo: View {
    var height: CGFloat = 24
    var body: some View {
        HStack(spacing: 8) {
            TianxuanEmblem(height: height * 1.3)
            Text("天选").font(.system(size: height, weight: .black)).tracking(2)
                .foregroundStyle(Palette.text)
        }
    }
}
struct TianxuanCaption: View {
    var width: CGFloat = 250
    var body: some View {
        Text("TIANXUAN · CONTROL CENTER")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.2).foregroundStyle(Palette.textSecondary)
            .frame(width: width, alignment: .leading)
    }
}
struct TianxuanMark: View {
    var size: CGFloat = 22
    var body: some View { TianxuanEmblem(height: size) }
}
enum TianxuanText {
    static func code(_ text: String) -> String { text }
    static func codeList(_ text: String) -> String { text }
}
struct CodeLabel: View {
    let text: String
    var size: CGFloat = 9.5
    var body: some View {
        Text(text).font(.system(size: size, weight: .medium))
            .foregroundStyle(Palette.textSecondary).lineLimit(1)
    }
}
