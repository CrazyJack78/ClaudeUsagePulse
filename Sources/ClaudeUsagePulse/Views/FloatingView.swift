import SwiftUI

struct FloatingView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var metricStore = MetricConfigStore.shared
    @AppStorage("windowStyle")   private var windowStyle:   String = "bars"
    @AppStorage("menubarTop")    private var menubarTop:    String = "five_hour"
    @AppStorage("menubarBottom") private var menubarBottom: String = "seven_day"

    var body: some View {
        VStack(spacing: 12) {
            if store.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if windowStyle == "bars" {
                barsView
            } else {
                circlesView
            }

            Text(lastUpdatedText)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(minWidth: 260, maxWidth: .infinity)
    }

    // MARK: - Balken-Ansicht

    private var barsView: some View {
        VStack(spacing: 10) {
            let configs = metricStore.configs.filter { $0.visibleInFloat }
            ForEach(Array(configs.enumerated()), id: \.element.id) { idx, config in
                let metric = store.data[config.key]
                usageRow(
                    label:      config.name,
                    percentage: metric.percentage,
                    info:       infoText(for: config, metric: metric)
                )
                if idx < configs.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func infoText(for config: MetricConfig, metric: MetricData) -> String {
        if let credit = metric.creditInfo, credit.limit > 0 {
            return String(format: "%.2f€ / %.2f€ verbraucht", credit.used, credit.limit)
        }
        return metric.resetStr
    }

    private func usageRow(label: String, percentage: Double, info: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(percentage))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(colorFor(percentage))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.18))
                        .frame(height: 7)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colorFor(percentage))
                        .frame(width: geo.size.width * CGFloat(min(percentage, 100) / 100), height: 7)
                        .animation(.easeOut(duration: 0.4), value: percentage)
                }
            }
            .frame(height: 7)

            Text(info.isEmpty ? " " : info)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(info.isEmpty ? 0 : 1))
        }
    }

    // MARK: - Kreis-Ansicht

    private var circlesView: some View {
        HStack(spacing: 28) {
            circleIndicator(key: menubarTop)
            Divider().frame(height: 80)
            if menubarBottom == "none" {
                Spacer()
            } else {
                circleIndicator(key: menubarBottom)
            }
        }
        .padding(.vertical, 4)
    }

    private func circleIndicator(key: String) -> some View {
        let metric = store.data[key]
        let label  = metricStore.name(for: key)
        let reset  = metric.resetStr
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.18), lineWidth: 7)
                    .frame(width: 70, height: 70)
                Circle()
                    .trim(from: 0, to: CGFloat(min(metric.percentage, 100) / 100))
                    .stroke(colorFor(metric.percentage), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: metric.percentage)
                Text("\(Int(metric.percentage))%")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(colorFor(metric.percentage))
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(reset.isEmpty ? "–" : reset)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(reset.isEmpty ? 0.4 : 1.0))
        }
    }

    // MARK: - Helpers

    private func colorFor(_ pct: Double) -> Color {
        if pct >= 90 { return .red }
        if pct >= 75 { return .orange }
        return .green
    }

    private var lastUpdatedText: String {
        let diff = Date().timeIntervalSince(store.data.fetchedAt)
        if diff < 60  { return "Gerade aktualisiert" }
        let min = Int(diff / 60)
        return "Vor \(min) min aktualisiert"
    }
}
