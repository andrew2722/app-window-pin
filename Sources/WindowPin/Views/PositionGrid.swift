import SwiftUI

/// Picks where on the display a snapped window lands, by showing it.
///
/// This replaces a row of buttons labelled `TL TR BL BR` — abbreviations the
/// user has to decode on every visit. A miniature of the screen with the
/// destination filled in needs no decoding, and is the convention every other
/// window manager on macOS already uses.
struct PositionGrid: View {
    @Binding var selection: PositionPreset?
    var isEnabled: Bool
    var onSelect: (PositionPreset) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(PositionPreset.allCases) { preset in
                PositionThumbnail(preset: preset, isSelected: selection == preset)
                    .onTapGesture {
                        guard isEnabled else { return }
                        onSelect(preset)
                    }
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct PositionThumbnail: View {
    let preset: PositionPreset
    let isSelected: Bool

    @State private var hovering = false

    /// Proportions of a real display, so the miniature is read as a screen
    /// rather than as an abstract square.
    private static let size = CGSize(width: 52, height: 34)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? AnyShapeStyle(Theme.brand.opacity(0.16))
                                 : AnyShapeStyle(Theme.surface))
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isSelected ? Theme.brand : Theme.hairline,
                              lineWidth: isSelected ? 1.5 : 1)

            occupiedRegion
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .scaleEffect(hovering && !isSelected ? 1.05 : 1)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(Theme.transition, value: isSelected)
        .animation(Theme.transition, value: hovering)
        .help(preset.label)
        .accessibilityLabel(preset.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The block showing which part of the screen the window will occupy.
    private var occupiedRegion: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 4
            let area = CGRect(x: inset, y: inset,
                              width: proxy.size.width - inset * 2,
                              height: proxy.size.height - inset * 2)
            let block = frame(in: area)

            RoundedRectangle(cornerRadius: 2.5)
                .fill(isSelected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.secondary.opacity(0.55)))
                .frame(width: block.width, height: block.height)
                .offset(x: block.minX, y: block.minY)
        }
    }

    /// Mirrors what the snap actually does: corners take a quadrant, centre
    /// takes a smaller block floating in the middle.
    private func frame(in area: CGRect) -> CGRect {
        let half = CGSize(width: area.width / 2, height: area.height / 2)
        switch preset {
        case .topLeft:
            return CGRect(origin: CGPoint(x: area.minX, y: area.minY), size: half)
        case .topRight:
            return CGRect(origin: CGPoint(x: area.midX, y: area.minY), size: half)
        case .bottomLeft:
            return CGRect(origin: CGPoint(x: area.minX, y: area.midY), size: half)
        case .bottomRight:
            return CGRect(origin: CGPoint(x: area.midX, y: area.midY), size: half)
        case .center:
            let size = CGSize(width: area.width * 0.56, height: area.height * 0.62)
            return CGRect(x: area.midX - size.width / 2,
                          y: area.midY - size.height / 2,
                          width: size.width, height: size.height)
        }
    }
}
