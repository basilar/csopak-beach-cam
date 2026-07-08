import SwiftUI
import AppKit

/// Fetches the AROME map forecast images shown on
/// https://met.hu/idojaras/tavaink/balaton/ ("Térképes modell előrejelzés").
/// The embedded page lists frames like `mwWB20260708_0000+00700.jpg`:
/// `<runYYYYMMDD>_<runHHMM>` is the model run in UTC and `+HHHMM` the lead
/// time, so the valid time is run + lead. Only frames whose valid time falls
/// on the current Budapest calendar day are kept.
@MainActor
final class BalatonMapViewModel: ObservableObject {
    struct Frame: Equatable {
        let url: URL
        let validTime: Date
    }

    @Published private(set) var frames: [Frame] = []
    @Published private(set) var images: [URL: NSImage] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var error = ""
    @Published var index = 0

    private static let pageURL = URL(string: "https://met.hu/idojaras/tavaink/balaton/modellek/main.php?frm=1")!
    private var loadedDay: Date?

    var currentFrame: Frame? {
        frames.indices.contains(index) ? frames[index] : nil
    }

    var currentImage: NSImage? {
        currentFrame.flatMap { images[$0.url] }
    }

    func loadIfNeeded() async {
        let today = calendar().startOfDay(for: Date())
        if loadedDay == today, !frames.isEmpty { return }
        await load()
    }

    func load() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var request = URLRequest(url: Self.pageURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                error = "Map page could not be decoded"
                return
            }
            let parsed = Self.parseTodayFrames(html: html, now: Date())
            guard !parsed.isEmpty else {
                error = "No map images for today"
                return
            }
            error = ""
            frames = parsed
            loadedDay = calendar().startOfDay(for: Date())

            // Start at the frame closest to now so the map opens on current weather.
            let now = Date()
            index = parsed.firstIndex(where: { $0.validTime >= now }) ?? (parsed.count - 1)

            await prefetchImages(for: parsed)
        } catch {
            self.error = "Map load failed: \(error.localizedDescription)"
        }
    }

    func goToFirst() {
        index = 0
    }

    func stepBack() {
        if index > 0 { index -= 1 }
    }

    func stepForward() {
        if index < frames.count - 1 { index += 1 }
    }

    private func prefetchImages(for frames: [Frame]) async {
        await withTaskGroup(of: (URL, NSImage?).self) { group in
            for frame in frames where images[frame.url] == nil {
                group.addTask {
                    let image = (try? await URLSession.shared.data(from: frame.url))
                        .flatMap { NSImage(data: $0.0) }
                    return (frame.url, image)
                }
            }
            for await (url, image) in group {
                if let image {
                    images[url] = image
                }
            }
        }
    }

    nonisolated private static func parseTodayFrames(html: String, now: Date) -> [Frame] {
        var basePath = "/img/mwWB/"
        if let match = html.firstMatch(of: #/var keplink="([^"]+)"/#) {
            basePath = String(match.1)
        }

        let runFormatter = DateFormatter()
        runFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        runFormatter.dateFormat = "yyyyMMdd_HHmm"

        let cal = calendar()
        var seen = Set<URL>()
        var frames: [Frame] = []
        for match in html.matches(of: #/(mw\w+(\d{8}_\d{4})\+(\d{3})(\d{2})\.jpg)/#) {
            guard let runTime = runFormatter.date(from: String(match.2)),
                  let leadHours = Int(match.3),
                  let leadMinutes = Int(match.4),
                  let url = URL(string: "https://met.hu\(basePath)\(match.1)"),
                  !seen.contains(url) else { continue }
            seen.insert(url)
            let validTime = runTime.addingTimeInterval(TimeInterval(leadHours * 3600 + leadMinutes * 60))
            if cal.isDate(validTime, inSameDayAs: now) {
                frames.append(Frame(url: url, validTime: validTime))
            }
        }
        return frames.sorted { $0.validTime < $1.validTime }
    }

    nonisolated private static func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = WeatherConstants.timeZone
        return cal
    }

    private func calendar() -> Calendar {
        Self.calendar()
    }
}

struct BalatonMapView: View {
    @ObservedObject var viewModel: BalatonMapViewModel

    private let pageSize = 6
    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black

            if !viewModel.frames.isEmpty {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    mapGrid
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 36)
            } else if viewModel.isLoading {
                ProgressView("Loading map…")
                    .progressViewStyle(.circular)
                    .foregroundColor(.white)
                    .colorScheme(.dark)
            } else if !viewModel.error.isEmpty {
                VStack(spacing: 12) {
                    Text(viewModel.error)
                        .foregroundColor(.white)
                    Button("Retry") {
                        Task { await viewModel.load() }
                    }
                }
            }

            if !viewModel.frames.isEmpty {
                controls
                    .padding(.bottom, 10)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !viewModel.frames.isEmpty {
                Text(timeLabel)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding(10)
            }
        }
        .task { await viewModel.loadIfNeeded() }
    }

    // Page of six frames containing the current selection; stepping the
    // selection across a page boundary flips to the next/previous page.
    private var mapGrid: some View {
        let pageStart = (viewModel.index / pageSize) * pageSize
        let pageEnd = min(pageStart + pageSize, viewModel.frames.count)
        return LazyVGrid(columns: gridColumns, spacing: 4) {
            ForEach(pageStart..<pageEnd, id: \.self) { i in
                tile(for: i)
            }
        }
        .padding(6)
    }

    @ViewBuilder
    private func tile(for index: Int) -> some View {
        let frame = viewModel.frames[index]
        let isSelected = index == viewModel.index
        Group {
            if let image = viewModel.images[frame.url] {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Color.white.opacity(0.06)
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)
                }
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text(Self.timeFormatter.string(from: frame.validTime))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(isSelected ? .yellow : .white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .padding(3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(isSelected ? Color.yellow : Color.white.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1)
        )
        .opacity(isSelected ? 1 : 0.55)
        .onTapGesture { viewModel.index = index }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = WeatherConstants.timeZone
        f.dateFormat = "HH:mm"
        return f
    }()

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.goToFirst()
            } label: {
                Image(systemName: "chevron.left.2")
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(viewModel.index <= 0)
            .opacity(viewModel.index <= 0 ? 0.35 : 1)

            Button {
                viewModel.stepBack()
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(viewModel.index <= 0)
            .opacity(viewModel.index <= 0 ? 0.35 : 1)

            Text("\(viewModel.index + 1)/\(viewModel.frames.count)")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.5))
                .cornerRadius(8)

            Button {
                viewModel.stepForward()
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(viewModel.index >= viewModel.frames.count - 1)
            .opacity(viewModel.index >= viewModel.frames.count - 1 ? 0.35 : 1)
        }
    }

    private var timeLabel: String {
        guard let frame = viewModel.currentFrame else { return "—" }
        return Self.timeFormatter.string(from: frame.validTime)
    }
}
