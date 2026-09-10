import SwiftUI

/// Picks where on the display a snapped window lands, by showing it.
///
/// This replaces a row of buttons labelled `TL TR BL BR` — abbreviations the
/// user has to decode on every visit. A miniature of the screen with the
/// destination filled in needs no decoding, and is the convention every other
/// window manager on macOS already uses.
struct PositionGrid: View {
    @Binding var selection: PositionPreset?
    /// The chosen size, so each miniature shows the frame that will actually
    /// result rather than a generic quadrant.
    var size: SizePreset
    /// Width and height used when `size == .custom`.
    var referenceSize: CGSize
    var isEnabled: Bool
    var onSelect: (PositionPreset) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(PositionPreset.allCases) { preset in
                PositionThumbnail(preset: preset,
                                  size: size,
                                  referenceSize: referenceSize,
                                  isSelected: selection == preset)
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
    let size: SizePreset
    let referenceSize: CGSize
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

    /// The frame the snap will actually produce, expressed as a fraction of the
    /// screen.
    ///
    /// This runs the same `ScreenService` calculation the window itself goes
    /// through, so the miniature cannot drift from the result. It used to draw
    /// a fixed quadrant for every preset, which meant choosing "50% width" or
    /// "Portrait" showed a picture of something that was never going to happen.
    private func frame(in area: CGRect) -> CGRect {
        guard let screen = ScreenService.primary else { return area }
        let bounds = screen.visibleFrame
        guard bounds.width > 0, bounds.height > 0 else { return area }

        let snapped = ScreenService.frame(position: preset,
                                          size: size,
                                          on: screen,
                                          currentSize: referenceSize)

        // AppKit counts y upward and the miniature draws downward, so the
        // vertical fraction is measured from the top edge.
        let unit = CGRect(x: (snapped.minX - bounds.minX) / bounds.width,
                          y: (bounds.maxY - snapped.maxY) / bounds.height,
                          width: snapped.width / bounds.width,
                          height: snapped.height / bounds.height)

        return CGRect(x: area.minX + unit.minX * area.width,
                      y: area.minY + unit.minY * area.height,
                      width: max(3, unit.width * area.width),
                      height: max(3, unit.height * area.height))
    }
}
