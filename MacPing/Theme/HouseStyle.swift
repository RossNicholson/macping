@_exported import HouseStyle
import SwiftUI

extension AppInfo {
    static let macPing = AppInfo(name: "MacPing", repo: "macping", cask: "macping",
                                 coffeeLine: "If MacPing keeps an eye on things for you")
}

/// Colours for each status, from the house pastels
extension ProbeStatus {
    var fill: Color {
        switch self {
        case .inactive: return AppColors.surface
        case .waiting: return AppColors.periwinkle
        case .up: return AppColors.mint
        case .indeterminate: return AppColors.butter
        case .down: return AppColors.coral
        case .error: return AppColors.lilac
        }
    }

    /// Text on the fill: ink on the pastels, the normal text colour on a stopped tile
    var foreground: Color {
        self == .inactive ? AppColors.text : AppColors.ink
    }

    var symbol: String {
        switch self {
        case .inactive: return "pause.circle"
        case .waiting: return "ellipsis.circle"
        case .up: return "checkmark.circle.fill"
        case .indeterminate: return "exclamationmark.circle.fill"
        case .down: return "xmark.circle.fill"
        case .error: return "questionmark.circle.fill"
        }
    }
}
