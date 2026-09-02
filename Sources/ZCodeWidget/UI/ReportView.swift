import SwiftUI
import AppKit
import Charts

// MARK: - ReportViewModel

@MainActor
final class ReportViewModel: ObservableObject {
    @Published var dailyTotals: [DailyUsage] = []
    @Published var heatmapTotals: [DailyUsage] = []
    @Published var topModels: [ModelTotal] = []
    @Published var weeklyCalls = 0

    private let repository = TokenUsageRepository()
    private var watcher: TokenTailWatcher?

    init() {
        watcher = TokenTailWatcher()
        watcher?.onNewRecord = { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        do {
            dailyTotals = try repository.dailyTotals(days: 7)
            heatmapTotals = try repository.dailyTotals(days: 119)
            topModels = try repository.topModels(days: 7, limit: 3)
            weeklyCalls = try repository.turnCount(days: 7)
        } catch {
            print("ReportViewModel.refresh error: \(error)")
        }
    }

    var weeklyInput: Int { dailyTotals.reduce(0) { $0 + $1.inputTokens } }
    var weeklyOutput: Int { dailyTotals.reduce(0) { $0 + $1.outputTokens } }
    var weeklyTotal: Int { dailyTotals.reduce(0) { $0 + $1.computedTotal } }

    /// The weekday of the largest day in the last 7 days, e.g. "Mon"
    var busiestDay: String? {
        guard let busiest = dailyTotals.max(by: { $0.computedTotal < $1.computedTotal }),
              busiest.computedTotal > 0 else { return nil }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: busiest.date)
    }

    var weekRangeText: String {
        guard let first = dailyTotals.first, let last = dailyTotals.last else { return "No data yet" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: first.date)) – \(f.string(from: last.date))"
    }
}

// MARK: - ReportView

struct ReportView: View {
    @StateObject private var viewModel = ReportViewModel()
    @State private var toastMessage: String?
    @State private var cardWidth: CGFloat = 300

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Your week in tokens — copy it as an image and share it.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    ReportCardView(
                        dailyTotals: viewModel.dailyTotals,
                        weeklyInput: viewModel.weeklyInput,
                        weeklyOutput: viewModel.weeklyOutput,
                        weeklyTotal: viewModel.weeklyTotal,
                        weeklyCalls: viewModel.weeklyCalls,
                        topModels: viewModel.topModels,
                        busiestDay: viewModel.busiestDay,
                        weekRangeText: viewModel.weekRangeText,
                        width: cardWidth
                    )
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)

                    Button(action: copyReportImage) {
                        Label("Copy Report Image", systemImage: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Divider()

                    Text("Last 17 Weeks")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    heatmapGrid
                    heatmapLegend
                }
                .padding(16)
            }
            .onAppear {
                cardWidth = max(240, geo.size.width - 34)
                viewModel.refresh()
            }
            .onChange(of: geo.size.width) { newWidth in
                cardWidth = max(240, newWidth - 34)
            }
        }
        .overlay(alignment: .bottom) {
            if let msg = toastMessage {
                ToastView(message: msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Heatmap

    /// 17-ish columns (weeks) x 7 rows (days), oldest column first, Mon-aligned.
    private var heatmapGrid: some View {
        let columns = heatmapCells
        let maxTotal = columns.flatMap { $0.compactMap { $0?.total } }.max() ?? 0
        return HStack(alignment: .top, spacing: 2) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(spacing: 2) {
                    ForEach(column.indices, id: \.self) { row in
                        let total = column[row]?.total ?? 0
                        RoundedRectangle(cornerRadius: 2)
                            .frame(width: 10, height: 10)
                            .foregroundStyle(heatColor(total: total, maxTotal: maxTotal))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// 119 consecutive UTC days ending today, aligned to ISO weeks (Mon start).
    private var heatmapCells: [[HeatmapCell?]] {
        var utcCal = Calendar(identifier: .iso8601)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!

        var byDay: [String: Int] = [:]
        for item in viewModel.heatmapTotals {
            byDay[Self.dayKeyFormatter.string(from: item.date)] = item.computedTotal
        }

        let today = utcCal.startOfDay(for: Date())
        let first = utcCal.date(byAdding: .day, value: -118, to: today)!
        let leadingEmpty = utcCal.component(.weekday, from: first) - 1  // 1 = Mon in iso8601

        var cells: [HeatmapCell?] = (0..<leadingEmpty).map { _ in nil }
        for offset in 0..<119 {
            let date = utcCal.date(byAdding: .day, value: offset, to: first)!
            let key = Self.dayKeyFormatter.string(from: date)
            cells.append(HeatmapCell(total: byDay[key] ?? 0))
        }

        var columns: [[HeatmapCell?]] = []
        var index = 0
        while index < cells.count {
            let end = min(index + 7, cells.count)
            var column: [HeatmapCell?] = []
            for i in index..<end { column.append(cells[i]) }
            while column.count < 7 { column.append(nil) }
            columns.append(column)
            index = end
        }
        return columns
    }

    private func heatColor(total: Int, maxTotal: Int) -> Color {
        guard maxTotal > 0, total > 0 else {
            return Color.gray.opacity(0.15)
        }
        let level = min(4, Int(Double(total) / Double(maxTotal) * 5))
        let greens: [Color] = [
            .green.opacity(0.25), .green.opacity(0.45),
            .green.opacity(0.65), .green.opacity(0.85), .green
        ]
        return greens[level]
    }

    private var heatmapLegend: some View {
        HStack(spacing: 4) {
            Text("Less")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: 9, height: 9)
                    .foregroundStyle(heatColor(total: i + 1, maxTotal: 5))
            }
            Text("More")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 6)
    }

    // MARK: Copy to clipboard

    private func copyReportImage() {
        let card = ReportCardView(
            dailyTotals: viewModel.dailyTotals,
            weeklyInput: viewModel.weeklyInput,
            weeklyOutput: viewModel.weeklyOutput,
            weeklyTotal: viewModel.weeklyTotal,
            weeklyCalls: viewModel.weeklyCalls,
            topModels: viewModel.topModels,
            busiestDay: viewModel.busiestDay,
            weekRangeText: viewModel.weekRangeText,
            width: cardWidth
        )

        // ImageRenderer first (reliable on macOS 14+); fall back to an offscreen
        // NSHostingView snapshot for macOS 13 where ImageRenderer + Charts was buggy.
        // scale 2 → crisp PNG on Retina displays.
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        if let nsImage = renderer.nsImage {
            writeToClipboard(nsImage)
            return
        }
        let hosting = NSHostingView(rootView: card)
        hosting.frame = NSRect(x: 0, y: 0, width: cardWidth, height: 430)
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            showToast("Could not render image")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage(size: hosting.bounds.size)
        image.addRepresentation(rep)
        // Match the ImageRenderer's 2x output on the 1x fallback path.
        let scaled = NSImage(size: NSSize(width: hosting.bounds.width * 2, height: hosting.bounds.height * 2), flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
        writeToClipboard(scaled)
    }

    private func writeToClipboard(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            showToast("Could not encode image")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        showToast("Report image copied")
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toastMessage = nil }
        }
    }

    private static let dayKeyFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}

// MARK: - ReportCardView

/// The shareable weekly card. Fixed size so it renders identically on screen
/// and in the clipboard snapshot.
struct ReportCardView: View {
    let dailyTotals: [DailyUsage]
    let weeklyInput: Int
    let weeklyOutput: Int
    let weeklyTotal: Int
    let weeklyCalls: Int
    let topModels: [ModelTotal]
    let busiestDay: String?
    let weekRangeText: String
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MY ZCODE WEEK")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(weekRangeText)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Text(formatTokens(weeklyTotal))
                .font(.system(size: 44, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("TOKENS USED THIS WEEK")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.45))

            HStack(spacing: 8) {
                miniStat("Input", weeklyInput)
                miniStat("Output", weeklyOutput)
                miniStat("Calls", weeklyCalls)
            }
            .padding(.top, 14)

            if !dailyTotals.isEmpty {
                Chart(dailyTotals) { item in
                    BarMark(
                        x: .value("Day", item.date, unit: .day),
                        y: .value("Tokens", item.computedTotal)
                    )
                    .foregroundStyle(Color(red: 0.30, green: 0.95, blue: 0.65).gradient)
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine().foregroundStyle(.white.opacity(0.1))
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.1))
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text(formatTokens(v))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                }
                .frame(height: 110)
                .padding(.top, 14)
            }

            Spacer()

            HStack(spacing: 8) {
                if let day = busiestDay {
                    highlightChip(icon: "flame.fill", text: "Busiest: \(day)")
                }
                if let top = topModels.first {
                    highlightChip(icon: "crown.fill", text: top.id)
                }
            }
        }
        .padding(22)
        .frame(width: width, height: 430)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.13, blue: 0.22),
                    Color(red: 0.05, green: 0.06, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(20)
    }

    private func miniStat(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.45))
            Text(formatTokens(value))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.07))
        .cornerRadius(8)
    }

    private func highlightChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.7))
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.08))
        .cornerRadius(8)
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}

// MARK: - HeatmapCell

private struct HeatmapCell {
    let total: Int
}
