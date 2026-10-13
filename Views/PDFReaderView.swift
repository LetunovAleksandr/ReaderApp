
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
                            isCurrentPage: index == currentPage,
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

        let currentKey = PDFPageRenderer.cacheKey(
            bookID: book.id,
            pageIndex: page
        )

        PDFRenderScheduler.shared.keepPendingRequests(
            for: keys,
            prioritizing: currentKey
        )

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
    let isCurrentPage: Bool
    let settings: ImageEnhancementSettings
    let availableSize: CGSize

    @State private var renderedImage: UIImage?
    @State private var isRendering = false
    @State private var renderFailed = false
    @State private var renderAttempt = 0

    private var cacheKey: String {
        PDFPageRenderer.cacheKey(
            bookID: bookID,
            pageIndex: pageIndex
        )
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
            } else if isCurrentPage && renderFailed {
                VStack(spacing: 12) {
                    Text("Не удалось загрузить страницу")
                        .font(.footnote)
                        .foregroundStyle(.white)

                    Button("Повторить") {
                        renderFailed = false
                        renderAttempt += 1
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            } else if isCurrentPage {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(
            width: availableSize.width,
            height: availableSize.height
        )
        .task(id: "\(isCurrentPage)-\(renderAttempt)") {
            guard isCurrentPage else {
                return
            }

            await renderPageIfNeeded()
        }
    }

    @MainActor
    private func renderPageIfNeeded() async {
        guard isCurrentPage, renderedImage == nil else {
            return
        }

        renderFailed = false

        if let cached = ImageEnhancementService.shared.cachedImage(
            for: cacheKey,
            settings: settings
        ) {
            renderedImage = cached
            return
        }

        guard let page = document.page(at: pageIndex) else {
            renderFailed = true
            return
        }

        let bounds = page.bounds(for: .mediaBox)

        guard bounds.width > 0, bounds.height > 0 else {
            renderFailed = true
            return
        }

        let aspectRatio = bounds.width / bounds.height
        let maxDimension: CGFloat = 1400

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

        isRendering = true
        defer {
            isRendering = false
        }

        let image = await PDFRenderScheduler.shared.render(
            key: cacheKey,
            priority: 100
        ) {
            PDFPageRenderer.render(
                page: page,
                size: size,
                cacheKey: cacheKey,
                settings: settings
            )
        }

        guard !Task.isCancelled, isCurrentPage else {
            return
        }

        if let image {
            renderedImage = image
            renderFailed = false
        } else {
            renderFailed = true
        }
    }
}

private enum PDFPageRenderer {
    static func cacheKey(bookID: UUID, pageIndex: Int) -> String {
        "pdf-\(bookID.uuidString)-page-\(pageIndex)-1400"
    }

    nonisolated static func render(
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
              bounds.height > 0,
              size.width > 0,
              size.height > 0 else {
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

            context.translateBy(x: 0, y: size.height)
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

private final class PDFRenderScheduler {
    static let shared = PDFRenderScheduler()

    private typealias Continuation =
        CheckedContinuation<UIImage?, Never>

    private final class Job {
        let key: String
        var priority: Int
        let work: () -> UIImage?

        var waiters: [UUID: Continuation] = [:]
        var isRunning = false

        init(
            key: String,
            priority: Int,
            work: @escaping () -> UIImage?
        ) {
            self.key = key
            self.priority = priority
            self.work = work
        }
    }

    private let lock = NSLock()

    private let workerQueue = DispatchQueue(
        label: "ReaderApp.PDFRenderScheduler",
        qos: .userInitiated
    )

    private var jobs: [String: Job] = [:]
    private var pendingKeys: Set<String> = []
    private var runningKey: String?

    private init() {}

    func render(
        key: String,
        priority: Int,
        work: @escaping () -> UIImage?
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            lock.lock()

            let waiterID = UUID()

            if let existingJob = jobs[key] {
                existingJob.waiters[waiterID] = continuation

                lock.unlock()
                return
            }

            let job = Job(
                key: key,
                priority: priority,
                work: work
            )

            job.waiters[waiterID] = continuation
            jobs[key] = job
            pendingKeys.insert(key)

            let nextJob = takeNextJobLocked()

            lock.unlock()

            if let nextJob {
                start(nextJob)
            }
        }
    }

    /// Оставляет в очереди только страницы текущего окна.
    func keepPendingRequests(
        for allowedKeys: Set<String>,
        prioritizing currentKey: String
    ) {
        var continuations: [Continuation] = []
        var nextJob: Job?

        lock.lock()

        let keysToRemove = pendingKeys.filter {
            !allowedKeys.contains($0)
        }

        for key in keysToRemove {
            guard let job = jobs.removeValue(forKey: key) else {
                pendingKeys.remove(key)
                continue
            }

            pendingKeys.remove(key)
            continuations.append(contentsOf: job.waiters.values)
            job.waiters.removeAll()
        }

        // Поднимаем актуальную страницу над устаревшими запросами,
        // которые всё ещё находятся в допустимом окне.
        for key in pendingKeys {
            jobs[key]?.priority = (key == currentKey) ? 100 : 10
        }

        if runningKey == nil {
            nextJob = takeNextJobLocked()
        }

        lock.unlock()

        for continuation in continuations {
            continuation.resume(returning: nil)
        }

        if let nextJob {
            start(nextJob)
        }
    }

    func cancelAll() {
        var continuations: [Continuation] = []

        lock.lock()

        for key in pendingKeys {
            guard let job = jobs.removeValue(forKey: key) else {
                continue
            }

            continuations.append(contentsOf: job.waiters.values)
            job.waiters.removeAll()
        }

        pendingKeys.removeAll()

        if let runningKey,
           let runningJob = jobs[runningKey] {
            continuations.append(
                contentsOf: runningJob.waiters.values
            )
            runningJob.waiters.removeAll()
        }

        lock.unlock()

        for continuation in continuations {
            continuation.resume(returning: nil)
        }
    }

    private func takeNextJobLocked() -> Job? {
        guard runningKey == nil else {
            return nil
        }

        let nextKey = pendingKeys
            .sorted { lhs, rhs in
                let leftPriority = jobs[lhs]?.priority ?? 0
                let rightPriority = jobs[rhs]?.priority ?? 0

                if leftPriority == rightPriority {
                    return lhs < rhs
                }

                return leftPriority > rightPriority
            }
            .first

        guard let nextKey,
              let job = jobs[nextKey] else {
            return nil
        }

        pendingKeys.remove(nextKey)
        runningKey = nextKey
        job.isRunning = true

        return job
    }

    private func start(_ job: Job) {
        workerQueue.async {
            let image = job.work()
            self.complete(job: job, image: image)
        }
    }

    private func complete(job: Job, image: UIImage?) {
        var continuations: [Continuation] = []
        var nextJob: Job?

        lock.lock()

        // Не удаляем более новую задачу с таким же ключом.
        if jobs[job.key] === job {
            jobs.removeValue(forKey: job.key)
        }

        if runningKey == job.key {
            runningKey = nil
        }

        continuations = Array(job.waiters.values)
        job.waiters.removeAll()

        nextJob = takeNextJobLocked()

        lock.unlock()

        for continuation in continuations {
            continuation.resume(returning: image)
        }

        if let nextJob {
            start(nextJob)
        }
    }
}
