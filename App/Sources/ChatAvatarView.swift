import NtfyAppLogic
import SwiftUI

/// The round avatar of a conversation: its emoji or initial on a colour fixed by the topic name.
struct ChatAvatarView: View {
  private static let palette: [Color] = [
    .blue, .indigo, .purple, .pink, .orange, .teal, .green, .brown,
  ]

  let avatar: ConversationAvatar
  var size: CGFloat = 40

  var body: some View {
    Circle()
      .fill(Self.palette[avatar.colorIndex % Self.palette.count].gradient)
      .frame(width: size, height: size)
      .overlay {
        Text(verbatim: avatar.glyph)
          .font(.system(size: size * (avatar.isEmoji ? 0.5 : 0.42), weight: .semibold))
          .foregroundStyle(.white)
      }
      .accessibilityHidden(true)
  }
}

/// The avatar of the "All" entry.
struct ChatAllAvatarView: View {
  var size: CGFloat = 40

  var body: some View {
    Circle()
      .fill(Color.secondary.gradient)
      .frame(width: size, height: size)
      .overlay {
        Image(systemName: "tray.full.fill")
          .font(.system(size: size * 0.42))
          .foregroundStyle(.white)
      }
      .accessibilityHidden(true)
  }
}
