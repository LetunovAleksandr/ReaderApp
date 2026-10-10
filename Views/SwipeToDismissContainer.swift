
import SwiftUI

struct SwipeToDismissContainer<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    @State private var verticalOffset: CGFloat = 0
    @State private var isDismissing = false

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()
                    .opacity(backgroundOpacity)

                content
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: cornerRadius,
                            style: .continuous
                        )
                    )
                    .scaleEffect(scale)
                    .offset(y: verticalOffset)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                guard !isDismissing else { return }

                                let horizontal = abs(value.translation.width)
                                let vertical = value.translation.height

                                guard vertical > 0,
                                      vertical > horizontal * 1.2
                                else {
                                    return
                                }

                                verticalOffset = vertical
                            }
                            .onEnded { value in
                                guard !isDismissing else { return }

                                let horizontal = abs(value.translation.width)
                                let vertical = value.translation.height

                                guard vertical > 0,
                                      vertical > horizontal * 1.2
                                else {
                                    withAnimation(.spring(
                                        response: 0.3,
                                        dampingFraction: 0.86
                                    )) {
                                        verticalOffset = 0
                                    }
                                    return
                                }

                                let predicted =
                                    value.predictedEndTranslation.height

                                if vertical > 140 || predicted > 280 {
                                    closeReader(
                                        screenHeight: geometry.size.height
                                    )
                                } else {
                                    withAnimation(.spring(
                                        response: 0.3,
                                        dampingFraction: 0.86
                                    )) {
                                        verticalOffset = 0
                                    }
                                }
                            }
                    )
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
        }
        .ignoresSafeArea()
    }

    private var scale: CGFloat {
        let progress = min(max(verticalOffset / 600, 0), 0.18)
        return 1 - progress
    }

    private var cornerRadius: CGFloat {
        min(max(verticalOffset / 5, 0), 28)
    }

    private var backgroundOpacity: Double {
        let progress = min(max(verticalOffset / 350, 0), 1)
        return 1 - progress
    }

    private func closeReader(screenHeight: CGFloat) {
        guard !isDismissing else { return }
        isDismissing = true

        withAnimation(.easeOut(duration: 0.16)) {
            verticalOffset = screenHeight
        }

        // Не добавляем дополнительную паузу после анимации.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
            dismiss()
        }
    }
}