import SwiftUI
import UIKit

enum Theme {
  static func color(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(
      uiColor: UIColor { traits in
        let hex = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(
          red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
          blue: CGFloat(hex & 255) / 255, alpha: 1)
      })
  }
  static let background = color(0xf6f1e9, 0x1d1a17)
  static let surface = color(0xfffdf9, 0x27231f)
  static let text = color(0x2b2620, 0xf1ebe3)
  static let muted = color(0x7a6f63, 0xa99d90)
  static let border = color(0xe6dccd, 0x3a342e)
  static let accent = color(0xc8553d, 0xe0765d)
  static let error = color(0xb42318, 0xff8a7a)
}
@MainActor struct WarmList: ViewModifier {
  func body(content: Content) -> some View {
    content.scrollContentBackground(.hidden).background(Theme.background).foregroundStyle(
      Theme.text)
  }
}
extension View { @MainActor func warmList() -> some View { modifier(WarmList()) } }
