import SwiftUI

struct FloatingView: View {
    @ObservedObject var store: UsageStore
    @AppStorage("windowStyle") private var windowStyle: String = "bars"

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
            usageRow(
                label: "Session (5h)",
                percentage: store.data.sessionPercentage,
                resetAt: store.data.sessionResetAt
            )
            Divider()
            usageRow(
                label: "Wöchentlich (7d)",
                percentage: store.data.weeklyPercentage,
                resetAt: store.data.weeklyResetAt
            )
        }
    }

    private func usageRow(label: String, percentage: Double, resetAt: Date?) -> some View {
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

            if let reset = resetAt, reset > Date() {
                Text("Reset in \(timeUntil(reset))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Kreis-Ansicht

    private var circlesView: some View {
        HStack(spacing: 28) {
            circleIndicator(label: "Session", value: store.data.sessionPercentage, reset: store.data.sessionResetAt)
            Divider().frame(height: 80)
            circleIndicator(label: "Wöchentlich", value: store.data.weeklyPercentage, reset: store.data.weeklyResetAt)
        }
        .padding(.vertical, 4)
    }

    private func circleIndicator(label: String, value: Double, reset: Date?) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.18), lineWidth: 7)
                    .frame(width: 70, height: 70)
                Circle()
                    .trim(from: 0, to: CGFloat(min(value, 100) / 100))
                    .stroke(colorFor(value), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: value)
                Text("\(Int(value))%")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(colorFor(value))
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            if let reset = reset, reset > Date() {
                Text(timeUntil(reset))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func colorFor(_ pct: Double) -> Color {
        if pct >= 90 { return .red }
        if pct >= 75 { return .orange }
        return .green
    }

    private func timeUntil(_ date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return "Jetzt" }
        let h = Int(diff / 3600)
        let m = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
        if h > 0 { return "\(h)h \(m)min" }
        return "\(m) min"
    }

    private var lastUpdatedText: String {
        let diff = Date().timeIntervalSince(store.data.fetchedAt)
        if diff < 60  { return "Gerade aktualisiert" }
        let min = Int(diff / 60)
        return "Vor \(min) min aktualisiert"
    }
}
