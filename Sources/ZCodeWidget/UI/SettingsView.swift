import SwiftUI

/// Settings sheet: daily token budget for the menu bar glance.
struct SettingsSheet: View {
    @ObservedObject var settings: WidgetSettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var budgetText = ""
    @State private var todayTokens = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Daily token budget")
                    .font(.system(size: 12, weight: .medium))
                TextField("0 = disabled", text: $budgetText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Text("The menu bar icon turns orange at 80% of the budget and red when exceeded. Set 0 to disable.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("Today: \(formatTokens(todayTokens))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    settings.dailyBudget = Int(budgetText) ?? 0
                    settings.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380, height: 230)
        .onAppear {
            budgetText = settings.dailyBudget > 0 ? "\(settings.dailyBudget)" : ""
            todayTokens = (try? TokenUsageRepository().todayTokens()) ?? 0
        }
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
