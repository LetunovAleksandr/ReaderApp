import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.06, blue: 0.07)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.8))

                    Text("Твоя библиотека")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Text("Здесь будут книги, манга и манхва")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)

                    Button(action: {}) {
                        Label("Добавить книгу", systemImage: "plus")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.white)
                            .clipShape(
                                RoundedRectangle(cornerRadius: 14)
                            )
                    }
                    .padding(.horizontal, 32)
                }
                .padding()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    LibraryView()
}
