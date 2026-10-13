
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
    @State private var progressSaveWorkItem: DispatchWorkItem?
    @State private var readingDirection = 1

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
        .onChange(of: currentPage) { oldValue, newValue in
            readingDirection = newValue >= oldValue ? 1 : -1
            scheduleProgressSave(for: newValue)
            updateRenderWindow(
                around: newValue,
                direction: readingDirection
            )
        }
        .onDisappear {
            progressSaveWorkItem?.cancel()
            progressSaveWorkItem = nil
            saveProgress(currentPage)
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
                            prefetchDirection: readingDirection,
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

        updateRenderWindow(
            around: currentPage,
            direction: readingDirection
        )
    }

    /// Сохраняем прогресс после короткой паузы, а не при каждом свайпе.
    /// Финальная позиция дополнительно сохраняется при закрытии ридера.
    private func scheduleProgressSave(for page: Int) {
        progressSaveWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            saveProgress(page)
        }

        progressSaveWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.4,
            execute: workItem
        )
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

    /// Держим в очереди текущую страницу и две страницы по направлению свайпа.
    /// Следующая страница получает более высокий приоритет, чем дальняя.
    private func updateRenderWindow(
        around page: Int,
        direction: Int
    ) {
        guard let document else {
            return
        }

        let candidates: [(index: Int, previewPriority: Int, fullPriority: Int)] = [
            (page, 120, 60),
            (page + direction, 115, 45),
            (page + direction * 2, 100, 30)
        ]

        var priorities: [String: Int] = [:]

        for candidate in candidates
        where candidate.index >= 0 && candidate.index < document.pageCount {
            let fullKey = PDFPageRenderer.cacheKey(
                bookID: book.id,
                pageIndex: candidate.index
            )
            let previewKey = PDFPageRenderer.previewCacheKey(for: fullKey)
            priorities[previewKey] = candidate.previewPriority
            priorities[fullKey] = candidate.fullPriority
        }

        PDFRenderScheduler.shared.keepPendingRequests(
            withPriorities: priorities
        )
    }
}

private struct PDFPageView: View {
    let document: PDFDocument
    let bookID: UUID
    let pageIndex: Int
    let isCurrentPage: Bool
    let prefetchDirection: Int
    let settings: ImageEnhancementSettings
    let availableSize: CGSize

    @State private var renderedImage: UIImage?
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
        .onChange(of: isCurrentPage) { _, isCurrent in
            if isCurrent {
                renderFailed = false
            }
            // Сохраняем уже показанное изображение при уходе со страницы,
            // чтобы при возврате не возникало пустого кадра.
        }
        .task(id: "\(isCurrentPage)-\(renderAttempt)") {
            guard isCurrentPage else {
                return
            }

            await renderPageIfNeeded()
        }
    }

    @MainActor
    private func renderPageIfNeeded() async {
        guard isCurrentPage else {
            return
        }

        let service = ImageEnhancementService.shared

        if let cached = service.cachedImage(
            for: cacheKey,
            settings: settings
        ) {
            renderedImage = cached
            renderFailed = false
            prefetchAdjacentPages()
            return
        }

        renderFailed = false

        // Сначала показываем небольшое превью, если оно уже подготовлено.
        if let preview = service.cachedPreview(
            for: PDFPageRenderer.previewCacheKey(for: cacheKey)
        ) {
            renderedImage = preview
        } else {
            guard let page = document.page(at: pageIndex),
                  let previewSize = PDFPageRenderer.previewSize(for: page) else {
                renderFailed = true
                return
            }

            let previewKey = PDFPageRenderer.previewCacheKey(for: cacheKey)
            let preview = await PDFRenderScheduler.shared.render(
                key: previewKey,
                priority: 120
            ) {
                PDFPageRenderer.renderPreview(
                    page: page,
                    size: previewSize,
                    previewKey: previewKey
                )
            }

            guard !Task.isCancelled, isCurrentPage else {
                return
            }

            if let preview {
                renderedImage = preview
            }
        }

        // Запускаем подготовку следующих превью сразу после получения
        // текущего превью, не дожидаясь полноразмерного рендеринга.
        prefetchAdjacentPages()

        guard !Task.isCancelled, isCurrentPage,
              let page = document.page(at: pageIndex),
              let size = PDFPageRenderer.renderSize(for: page) else {
            return
        }

        // Превью уже видно. Полное улучшенное изображение заменит его,
        // когда рендеринг закончится, без индикатора поверх страницы.
        let image = await PDFRenderScheduler.shared.render(
            key: cacheKey,
            priority: 60
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
            prefetchAdjacentPages()
        } else if renderedImage == nil {
            renderFailed = true
        }
    }

    /// В первую очередь готовим маленькие превью следующих страниц.
    /// Полные изображения ставим в очередь после превью.
    private func prefetchAdjacentPages() {
        let candidates = [
            (pageIndex + prefetchDirection, 115, 45),
            (pageIndex + prefetchDirection * 2, 100, 30)
        ].filter {
            $0.0 >= 0 && $0.0 < document.pageCount
        }

        for (index, previewPriority, fullPriority) in candidates {
            guard let page = document.page(at: index),
                  let previewSize = PDFPageRenderer.previewSize(for: page),
                  let fullSize = PDFPageRenderer.renderSize(for: page) else {
                continue
            }

            let fullKey = PDFPageRenderer.cacheKey(
                bookID: bookID,
                pageIndex: index
            )
            let previewKey = PDFPageRenderer.previewCacheKey(for: fullKey)

            if ImageEnhancementService.shared.cachedPreview(
                for: previewKey
            ) == nil {
                Task {
                    _ = await PDFRenderScheduler.shared.render(
                        key: previewKey,
                        priority: previewPriority
                    ) {
                        PDFPageRenderer.renderPreview(
                            page: page,
                            size: previewSize,
                            previewKey: previewKey
                        )
                    }
                }
            }

            if ImageEnhancementService.shared.cachedImage(
                for: fullKey,
                settings: settings
            ) == nil {
                Task {
                    _ = await PDFRenderScheduler.shared.render(
                        key: fullKey,
                        priority: fullPriority
                    ) {
                        PDFPageRenderer.render(
                            page: page,
                            size: fullSize,
                            cacheKey: fullKey,
                            settings: settings
                        )
                    }
                }
            }
        }
    }
}

private enum PDFPageRenderer {
    static func cacheKey(bookID: UUID, pageIndex: Int) -> String {
        "pdf-\(bookID.uuidString)-page-\(pageIndex)-1200"
    }

    static func previewCacheKey(for fullKey: String) -> String {
        "\(fullKey)-preview-600"
    }

    static func previewSize(for page: PDFPage) -> CGSize? {
        renderSize(for: page, maxDimension: 600)
    }

    static func renderSize(for page: PDFPage) -> CGSize? {
        renderSize(for: page, maxDimension: 1200)
    }

    private static func renderSize(
        for page: PDFPage,
        maxDimension: CGFloat
    ) -> CGSize? {
        let bounds = page.bounds(for: .mediaBox)

        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let aspectRatio = bounds.width / bounds.height

        if aspectRatio >= 1 {
            return CGSize(
                width: maxDimension,
                height: max(1, maxDimension / aspectRatio)
            )
        }

        return CGSize(
            width: max(1, maxDimension * aspectRatio),
            height: maxDimension
        )
    }

    nonisolated static func renderPreview(
        page: PDFPage,
        size: CGSize,
        previewKey: String
    ) -> UIImage? {
        if let cached = ImageEnhancementService.shared.cachedPreview(
            for: previewKey
        ) {
            return cached
        }

        guard let image = drawPage(page: page, size: size) else {
            return nil
        }

        ImageEnhancementService.shared.storePreview(
            image,
            for: previewKey
        )
        return image
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

        guard let originalImage = drawPage(page: page, size: size) else {
            return nil
        }

        return ImageEnhancementService.shared.enhance(
            originalImage,
            cacheKey: cacheKey,
            settings: settings
        )
    }

    private nonisolated static func drawPage(
        page: PDFPage,
        size: CGSize
    ) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)

        guard bounds.width > 0,
              bounds.height > 0,
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { rendererContext in
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
    }
}

private final class PDFRenderScheduler {
    static let shared = PDFRenderScheduler()

    private typealias Continuation = CheckedContinuation<UIImage?, Never>

    private final class Job {
        let key: String
        var priority: Int
        let work: () -> UIImage?
        var waiters: [UUID: Continuation] = [:]
        let isPreview: Bool

        init(key: String, priority: Int, work: @escaping () -> UIImage?) {
            self.key = key
            self.priority = priority
            self.work = work
            self.isPreview = key.contains("-preview-600")
        }
    }

    private let lock = NSLock()
    // Превью и полноразмерные страницы обрабатываются независимо.
    // Тяжёлый полноразмерный рендер больше не блокирует подготовку превью.
    private let previewQueue = DispatchQueue(
        label: "ReaderApp.PDFPreviewScheduler",
        qos: .userInitiated
    )
    private let fullQueue = DispatchQueue(
        label: "ReaderApp.PDFFullRenderScheduler",
        qos: .userInitiated
    )

    private var jobs: [String: Job] = [:]
    private var pendingKeys: Set<String> = []
    private var runningPreviewKey: String?
    private var runningFullKey: String?

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
                if pendingKeys.contains(key) {
                    existingJob.priority = max(existingJob.priority, priority)
                }
                let nextPreview = takeNextJobLocked(isPreview: true)
                let nextFull = takeNextJobLocked(isPreview: false)
                lock.unlock()
                if let nextPreview { start(nextPreview) }
                if let nextFull { start(nextFull) }
                return
            }

            let job = Job(key: key, priority: priority, work: work)
            job.waiters[waiterID] = continuation
            jobs[key] = job
            pendingKeys.insert(key)

            let nextPreview = takeNextJobLocked(isPreview: true)
            let nextFull = takeNextJobLocked(isPreview: false)
            lock.unlock()

            if let nextPreview { start(nextPreview) }
            if let nextFull { start(nextFull) }
        }
    }

    func keepPendingRequests(withPriorities priorities: [String: Int]) {
        var continuations: [Continuation] = []

        lock.lock()
        let keysToRemove = pendingKeys.filter { priorities[$0] == nil }
        for key in keysToRemove {
            guard let job = jobs.removeValue(forKey: key) else {
                pendingKeys.remove(key)
                continue
            }
            pendingKeys.remove(key)
            continuations.append(contentsOf: job.waiters.values)
            job.waiters.removeAll()
        }

        for key in pendingKeys {
            if let priority = priorities[key] {
                jobs[key]?.priority = priority
            }
        }

        let nextPreview = takeNextJobLocked(isPreview: true)
        let nextFull = takeNextJobLocked(isPreview: false)
        lock.unlock()

        continuations.forEach { $0.resume(returning: nil) }
        if let nextPreview { start(nextPreview) }
        if let nextFull { start(nextFull) }
    }

    func cancelAll() {
        var continuations: [Continuation] = []
        lock.lock()

        for key in pendingKeys {
            guard let job = jobs.removeValue(forKey: key) else { continue }
            continuations.append(contentsOf: job.waiters.values)
            job.waiters.removeAll()
        }
        pendingKeys.removeAll()

        if let key = runningPreviewKey, let job = jobs[key] {
            continuations.append(contentsOf: job.waiters.values)
            job.waiters.removeAll()
        }
        if let key = runningFullKey, let job = jobs[key] {
            continuations.append(contentsOf: job.waiters.values)
            job.waiters.removeAll()
        }

        lock.unlock()
        continuations.forEach { $0.resume(returning: nil) }
    }

    private func takeNextJobLocked(isPreview: Bool) -> Job? {
        if (isPreview ? runningPreviewKey != nil : runningFullKey != nil) {
            return nil
        }

        let nextKey = pendingKeys
            .filter { jobs[$0]?.isPreview == isPreview }
            .sorted { lhs, rhs in
                let leftPriority = jobs[lhs]?.priority ?? 0
                let rightPriority = jobs[rhs]?.priority ?? 0
                return leftPriority == rightPriority ? lhs < rhs : leftPriority > rightPriority
            }
            .first

        guard let nextKey, let job = jobs[nextKey] else { return nil }
        pendingKeys.remove(nextKey)
        if isPreview {
            runningPreviewKey = nextKey
        } else {
            runningFullKey = nextKey
        }
        return job
    }

    private func start(_ job: Job) {
        let queue = job.isPreview ? previewQueue : fullQueue
        queue.async {
            let image = job.work()
            self.complete(job: job, image: image)
        }
    }

    private func complete(job: Job, image: UIImage?) {
        var continuations: [Continuation] = []
        lock.lock()

        if jobs[job.key] === job {
            jobs.removeValue(forKey: job.key)
        }
        if runningPreviewKey == job.key { runningPreviewKey = nil }
        if runningFullKey == job.key { runningFullKey = nil }

        continuations = Array(job.waiters.values)
        job.waiters.removeAll()

        let nextPreview = takeNextJobLocked(isPreview: true)
        let nextFull = takeNextJobLocked(isPreview: false)
        lock.unlock()

        continuations.forEach { $0.resume(returning: image) }
        if let nextPreview { start(nextPreview) }
        if let nextFull { start(nextFull) }
    }
}
