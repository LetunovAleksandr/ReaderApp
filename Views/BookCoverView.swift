
import SwiftUI
import UIKit

struct BookCoverView: View {
    let book: Book

    var width: CGFloat
    var height: CGFloat

    private let storage = BookStorageService()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            Color.black.opacity(0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let coverURL = storage.coverURL(for: book),
               let image = UIImage(contentsOfFile: coverURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                VStack(spacing: 10) {
                    Image(
                        systemName: book.format == .cbz
                            ? "photo.on.rectangle.angled"
                            : "book.closed"
                    )
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.8))

                    Text(book.format.rawValue)
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }
}
