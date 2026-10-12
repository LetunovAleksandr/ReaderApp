
import SwiftUI
import PDFKit
import UIKit

struct PDFReaderView: View {
    let book: Book
    let onClose: () -> Void

    @AppStorage("readerApp.currentBookID")
    private var currentBookID = ""

    @State private var document: PDFDocument?
    @State private var currentPage = 0
    @State private var loadError = false

    private let storage = BookStorageService()

    private let enhancementSettings = ImageEnhancementSettings(
        enabled: true,
        contrast: 1.2,
        brightness: 0.02,
        saturation: 0.0,
        sharpness: 0.4
    )

    var body: some View {
        SwipeToDismissContainer(onDismiss: onClose) {
            Group {
                if let document {
                    pageReader(document)
                } else if loadError {
                    ContentUnavailableView(
                        "Не удалось открыть PDF",
                        systemImage: "doc.text",
                        description: Text(
                            "Файл не найден или повреждён."
                        )
                    )
                } else {
                    ProgressView("Открываем книгу…")
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            currentBookID = book.id.uuidString
        }
        .task {
            loadDocument()
        }
        .onChange(of: currentPage) { _, newValue in
            saveProgress(newValue)
            updateRenderWindow(around: newValue)
        }
        .onDisappear {
            PDFRenderScheduler.shared.cancelAll()
        }
    }

    private func pageReader(_ document: PDFDocument) -> some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                TabView(selection: $currentPage) {
                    ForEach(
                        0..<document.pageCount,
                        id: \.self
                    ) { index in
                        PDFPageView(
                            document: document,
                            bookID: book.id,
                            pageIndex: index,
                            currentPage: currentPage,
                            settings: enhancementSettings,
                            availableSize: geometry.size
                        )
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(
                    .page(indexDisplayMode: .never)
                )
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )

                VStack {
                    Spacer()

                    Text(
                        "\(currentPage + 1) / \(document.pageCount)"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.7))
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
                }
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
        }
        .ignoresSafeArea()
    }

    private func loadDocument() {
        guard document == nil, !loadError else {
            return
        }

        let url = storage.fileURL(for: book)

        guard let pdf = PDFDocument(url: url),
              pdf.pageCount > 0 else {
            loadError = true
            return
        }

        var restoredPage = 0

        do {
            let books = try storage.loadLibrary()

            if let savedBook = books.first(
                where: { $0.id == book.id }
            ) {
                restoredPage = Int(
                    (
                        savedBook.readingProgress *
                        Double(max(pdf.pageCount - 1, 0))
                    ).rounded()
                )
            }
        } catch {
            restoredPage = 0
        }

        currentPage = min(
            max(restoredPage, 0),
            pdf.pageCount - 1
        )

        document = pdf

        updateRenderWindow(around: currentPage)
    }

    private func saveProgress(_ page: Int) {
        guard let document,
              document.pageCount > 0 else {
            return
        }

        do {
            var books = try storage.loadLibrary()

            guard let index = books.firstIndex(
                where: { $0.id == book.id }
            ) else {
                return
            }

            books[index].readingProgress =
                Double(page) /
                Double(max(document.pageCount - 1, 1))

            try storage.saveLibrary(books)
        } catch {
            print(
                "Не удалось сохранить прогресс PDF: \(error)"
            )
        }
    }

    private func updateRenderWindow(around page: Int) {
        guard let document else {
            return
        }

        let indices = Set(
            [
                page - 1,
                page,
                page + 1
            ].filter {
                $0 >= 0 && $0 < document.pageCount
            }
        )

        let keys = Set(
            indices.map {
                PDFPageRenderer.cacheKey(
                    bookID: book.id,
                    pageIndex: $0
                )
            }
        )

        PDFRenderScheduler.shared.keepPendingRequests(for: keys)

        ImageEnhancementService.shared.trimPDFCache(
            bookID: book.id,
            pageCount: document.pageCount,
            keepingPageIndices: indices,
            settings: enhancementSettings
        )
    }
}

private struct PDFPageView: View {
    let document: PDFDocument
    let bookID: UUID
    let pageIndex: Int
    let currentPage: Int
    let settings: ImageEnhancementSettings
    let availableSize: CGSize

    @State private var renderedImage: UIImage?

    private var distance: Int {
        abs(pageIndex - currentPage)
    }

    private var shouldRender: Bool {
        distance <= 1
    }

    var body: some View {
        ZStack {
            Color.black

            if let renderedImage {
                Image(uiImage: renderedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: availableSize.width,
                        height: availableSize.height
                    )
            } else if pageIndex == currentPage {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(
            width: availableSize.width,
            height: availableSize.height
        )
        .task(id: distance) {
            guard shouldRender else {
                renderedImage = nil
                return
            }

            await renderPageIfNeeded()
        }
    }

    @MainActor
    private func renderPageIfNeeded() async {
        guard shouldRender,
              renderedImage == nil else {
            return
        }

        let key = PDFPageRenderer.cacheKey(
            bookID: bookID,
            pageIndex: pageIndex
        )

        if let cached = ImageEnhancementService.shared.cachedImage(
            for: key,
            settings: settings
        ) {
            renderedImage = cached
            return
        }

        guard let page = document.page(at: pageIndex) else {
            return
        }

        let bounds = page.bounds(for: .mediaBox)

        guard bounds.width > 0,
              bounds.height > 0 else {
            return
        }

        let maxDimension: CGFloat = 1400
        let aspectRatio = bounds.width / bounds.height

        let size: CGSize

        if aspectRatio >= 1 {
            size = CGSize(
                width: maxDimension,
                height: max(1, maxDimension / aspectRatio)
            )
        } else {
            size = CGSize(
                width: max(1, maxDimension * aspectRatio),
                height: maxDimension
            )
        }

        let image = await PDFRenderScheduler.shared.render(
            key: key,
            priority: distance == 0 ? 0 : 1
        ) {
            PDFPageRenderer.renderSynchronously(
                page: page,
                size: size,
                cacheKey: key,
                settings: settings
            )
        }

        guard !Task.isCancelled,
              shouldRender else {
            return
        }

        renderedImage = image
    }
}

private enum PDFPageRenderer {
    static func cacheKey(
        bookID: UUID,
        pageIndex: Int
    ) -> String {
        "pdf-\(bookID.uuidString)-page-\(pageIndex)-1400"
    }

    nonisolated static func renderSynchronously(
        page: PDFPage,
        size: CGSize,
        cacheKey: String,
        settings: ImageEnhancementSettings
    ) -> UIImage? {
        if let cached = ImageEnhancementService.shared.cachedImage(
            for: cacheKey,
            settings: settings
        ) {
            return cached
        }

        let bounds = page.bounds(for: .mediaBox)

        guard bounds.width > 0,
              bounds.height > 0 else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(size: size)

        let originalImage = renderer.image { rendererContext in
            UIColor.white.setFill()

            rendererContext.fill(
                CGRect(origin: .zero, size: size)
            )

            let context = rendererContext.cgContext

            context.saveGState()

            context.translateBy(
                x: 0,
                y: size.height
            )

            context.scaleBy(
                x: size.width / bounds.width,
                y: -size.height / bounds.height
            )

            context.translateBy(
                x: -bounds.minX,
                y: -bounds.minY
            )

            page.draw(
                with: .mediaBox,
                to: context
            )

            context.restoreGState()
        }

        return ImageEnhancementService.shared.enhance(
            originalImage,
            cacheKey: cacheKey,
            settings: settings
        )
    }
}

private final class PDFRenderRequest {
    let key: String
    let priority: Int
    let work: () -> UIImage?

    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var completed = false

    var operation: Operation?

    init(
        key: String,
        priority: Int,
        work: @escaping () -> UIImage?,
        continuation: CheckedContinuation<UIImage?, Never>
    ) {
        self.key = key
        self.priority = priority
        self.work = work
        self.continuation = continuation
    }

    func finish(_ image: UIImage?) {
        lock.lock()

        guard !completed else {
            lock.unlock()
            return
        }

        completed = true
        let continuation = self.continuation
        self.continuation = nil

        lock.unlock()

        continuation?.resume(returning: image)
    }

    func cancel() {
        operation?.cancel()
        finish(nil)
    }
}

private final class PDFRenderScheduler {
    static let shared = PDFRenderScheduler()

    private let lock = NSLock()

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "ReaderApp.PDFRenderQueue"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private var pending: [String: PDFRenderRequest] = [:]
    private var runningKeys = Set<String>()

    private init() {}

    func render(
        key: String,
        priority: Int,
        work: @escaping () -> UIImage?
    ) async -> UIImage? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let request = PDFRenderRequest(
                    key: key,
                    priority: priority,
                    work: work,
                    continuation: continuation
                )

                lock.lock()

                if let existing = pending[key] {
                    lock.unlock()
                    existing.cancel()
                    enqueue(request)
                    return
                }

                if runningKeys.contains(key) {
                    lock.unlock()
                    request.finish(nil)
                    return
                }

                pending[key] = request
                lock.unlock()

                enqueueOperation(for: request)
            }
        } onCancel: {
            self.cancel(key: key)
        }
    }

    private func enqueue(_ request: PDFRenderRequest) {
        lock.lock()
        pending[request.key] = request
        lock.unlock()

        enqueueOperation(for: request)
    }

    private func enqueueOperation(for request: PDFRenderRequest) {
        let operation = BlockOperation { [weak self, weak request] in
            guard let self,
                  let request else {
                return
            }

            self.lock.lock()

            let isCurrent = self.pending[request.key] === request

            if isCurrent {
                self.pending.removeValue(forKey: request.key)
                self.runningKeys.insert(request.key)
            }

            self.lock.unlock()

            guard isCurrent, !request.operation!.isCancelled else {
                request.finish(nil)
                return
            }

            let image = request.work()
            request.finish(image)

            self.lock.lock()
            self.runningKeys.remove(request.key)
            self.lock.unlock()
        }

        operation.queuePriority = request.priority == 0 ? .veryHigh : .normal
        request.operation = operation

        lock.lock()
        let stillPending = pending[request.key] === request
        lock.unlock()

        if stillPending {
            queue.addOperation(operation)
        } else {
            request.cancel()
        }
    }

    func cancel(key: String) {
        lock.lock()
        let request = pending.removeValue(forKey: key)
        lock.unlock()

        request?.cancel()
    }

    func keepPendingRequests(for keys: Set<String>) {
        lock.lock()

        let obsolete = pending.values.filter {
            !keys.contains($0.key)
        }

        for request in obsolete {
            pending.removeValue(forKey: request.key)
        }

        lock.unlock()

        obsolete.forEach {
            $0.cancel()
        }
    }

    func cancelAll() {
        lock.lock()

        let requests = Array(pending.values)
        pending.removeAll()

        lock.unlock()

        requests.forEach {
            $0.cancel()
        }
    }
}