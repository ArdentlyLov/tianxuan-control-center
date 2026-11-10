
import SwiftUI
import AppKit
import Combine


enum Palette {
    static let bg = Color.skin(0xF5F6F8, 0x111318, 0xF4F6FA)
    static let bgSoft = Color.skin(0xFAFBFC, 0x16191F, 0xF9FAFC)
    static let panelTop = Color.skin(0xFFFFFF, 0x1C2028, 0xFFFFFF)
    static let panelBottom = panelTop
    static let panelHi = Color.skin(0xEDF2FD, 0x252D3D, 0xEDF2FD)

    static let accent = Color.skin(0x416CE8, 0x8AA9FF, 0x416CE8)
    static let buttonAccent = Color.skin(0x416CE8, 0x5077E6, 0x416CE8)
    static let accent2 = Color.skin(0x568EAC, 0x86B8D1, 0x568EAC)
    static let ok = Color.skin(0x24845C, 0x72CDA6, 0x24845C)
    static let warn = Color.skin(0xAE7318, 0xE9BC75, 0xAE7318)
    static let bad = Color.skin(0xCD4C58, 0xF08A95, 0xCD4C58)

    static let violet = Color.skin(0x8673BE, 0xB4A3E2, 0x8673BE)
    static let teal   = Color.skin(0x4E9699, 0x7AC6C9, 0x4E9699)
    static let pink   = Color.skin(0xC77895, 0xDE9AB3, 0xC77895)
    static let indigo = Color.skin(0x6576BB, 0xA0AEE8, 0x6576BB)
    static let mint   = Color.skin(0x4D9B7E, 0x80CAAC, 0x4D9B7E)

    static let mLoad    = accent
    static let mFreq    = accent2
    static let mPower   = Color.skin(0xB98C4B, 0xDDB276, 0xB98C4B)
    static let mMem     = teal
    static let mFan     = accent2
    static let mBattery = ok
    static let mDisk    = Color.skin(0x7D8DA4, 0x9BAAC1, 0x7D8DA4)
    static let mGPU     = indigo
    static let mGPUPow  = mPower
    static let mVRAM    = violet
    static let mNet     = accent2
    static let mSysPower = mPower

    static let text = Color.skin(0x242B3A, 0xEDF0F7, 0x242B3A)
    static let textSecondary = Color.skin(0x687387, 0xADB6C8, 0x687387)
    static let textTertiary = Color.skin(0x818B9C, 0x8C97AC, 0x818B9C)

    static let cardStroke = Color.skin(0x233044, 0xFFFFFF, 0x233044, lightOpacity: 0.07, darkOpacity: 0.07, tianxuanOpacity: 0.07)
    static let subtle = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.05, darkOpacity: 0.04, tianxuanOpacity: 0.05)
    static let faintFill = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.07, darkOpacity: 0.07, tianxuanOpacity: 0.05)
    static let hairline = Color.skin(0x233044, 0xFFFFFF, 0x233044, lightOpacity: 0.08, darkOpacity: 0.08, tianxuanOpacity: 0.08)
    static let veil = Color.skin(0xFFFFFF, 0x000000, 0xFFFFFF, lightOpacity: 0.00, darkOpacity: 0.02, tianxuanOpacity: 0.9)
    static let ringBase = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.08, darkOpacity: 0.06, tianxuanOpacity: 0.1)
    static let ringTick = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.18, darkOpacity: 0.16, tianxuanOpacity: 0.22)
    static let trackFill = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.07, darkOpacity: 0.06, tianxuanOpacity: 0.06)

    static var isTianxuan: Bool { SkinFlag.tianxuan }

    static var cornerRadius: CGFloat { 10 }

    static func forTemp(_ t: Double?) -> Color {
        guard let t else { return textSecondary }
        switch t {
        case ..<72: return accent
        case ..<85: return warn
        default: return bad
        }
    }

    static func forStatus(_ s: CapStatus) -> Color {
        switch s {
        case .available: return ok
        case .limited: return warn
        case .unavailable: return textTertiary
        }
    }

    static func forDisk(_ f: Double) -> Color {
        switch f {
        case ..<0.7: return mDisk
        case ..<0.9: return warn
        default: return bad
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

