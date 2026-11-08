
import SwiftUI
import AppKit
import Combine


enum Palette {
    static let bg = Color.skin(0xF0F4F4, 0x10181C, 0xEEF4F3)
    static let bgSoft = Color.skin(0xE4ECEB, 0x162126, 0xDFEBE8)
    static let panelTop = Color.skin(0xFFFFFF, 0x1B272D, 0xFFFFFF)
    static let panelBottom = Color.skin(0xF9FCFB, 0x172229, 0xF8FCFB)
    static let panelHi = Color.skin(0xE3EEEB, 0x26383E, 0xE2F2ED)

    static let accent = Color.skin(0x008C80, 0x68E7CD, 0x008C80)
    static let accent2 = Color.skin(0x219FAD, 0x85CFE6, 0x269EAF)
    static let ok = Color.skin(0x18805E, 0x72D6A4, 0x18805E)
    static let warn = Color.skin(0xC77F00, 0xFFB020, 0xB26A00)
    static let bad = Color.skin(0xD62A3C, 0xFF3B4E, 0xA4161F)

    static let violet = Color.skin(0x7C5CFF, 0xA78BFA, 0x6B4E71)
    static let teal   = Color.skin(0x0FA890, 0x2DD4BF, 0x2F6F6B)
    static let pink   = Color.skin(0xE0529C, 0xFF6FB5, 0xA8322D)
    static let indigo = Color.skin(0x4F46E5, 0x818CF8, 0x4A6FA5)
    static let mint   = Color.skin(0x00A884, 0x34E0B4, 0x2E7D4F)

    static let mLoad    = Color.skin(0x008C80, 0x68E7CD, 0x008C80)
    static let mFreq    = Color.skin(0x188FA6, 0x70CEDE, 0x188FA6)
    static let mPower   = Color.skin(0xD97706, 0xFBBF24, 0xB26A00)
    static let mMem     = Color.skin(0x608644, 0xA4C789, 0x608644)
    static let mFan     = Color.skin(0x14B8A6, 0x2DD4BF, 0x2F6F6B)
    static let mBattery = Color.skin(0x22C55E, 0x4ADE80, 0x2E7D4F)
    static let mDisk    = Color.skin(0x64748B, 0x94A3B8, 0x6E7378)
    static let mGPU     = Color.skin(0x6471BB, 0xABAEEF, 0x6471BB)
    static let mGPUPow  = Color.skin(0x977044, 0xD5AB79, 0x977044)
    static let mVRAM    = Color.skin(0x667DA6, 0xA0B8DF, 0x667DA6)
    static let mNet     = Color.skin(0x0EA5E9, 0x38BDF8, 0x4A6FA5)
    static let mSysPower = Color.skin(0xB26B37, 0xE8B585, 0xB26B37)

    static let text = Color.skin(0x1C3034, 0xEBF5F3, 0x1C3034)
    static let textSecondary = Color.skin(0x526B70, 0xA4BBBF, 0x526B70)
    static let textTertiary = Color.skin(0x75898D, 0x789398, 0x75898D)

    static let cardStroke = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.11, darkOpacity: 0.09, tianxuanOpacity: 0.12)
    static let subtle = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.05, darkOpacity: 0.04, tianxuanOpacity: 0.05)
    static let faintFill = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.07, darkOpacity: 0.07, tianxuanOpacity: 0.05)
    static let hairline = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.10, darkOpacity: 0.08, tianxuanOpacity: 0.10)
    static let veil = Color.skin(0xFFFFFF, 0x000000, 0xFFFFFF, lightOpacity: 0.00, darkOpacity: 0.02, tianxuanOpacity: 0.9)
    static let ringBase = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.08, darkOpacity: 0.06, tianxuanOpacity: 0.1)
    static let ringTick = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.18, darkOpacity: 0.16, tianxuanOpacity: 0.22)
    static let trackFill = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.07, darkOpacity: 0.06, tianxuanOpacity: 0.06)

    static var isTianxuan: Bool { SkinFlag.tianxuan }

    static var cornerRadius: CGFloat { isTianxuan ? 4 : 12 }

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

