import SwiftUI

private struct KeyboardKey: Identifiable {
    let code: Int
    let label: String
    var width: CGFloat = 1
    var id: Int { code }
}

struct KeyboardHeatmapView: View {
    let day: DayStats
    let periodLabel: String

    @State private var selectedCode: Int?

    private let gap: CGFloat = 3
    private let rows: [[KeyboardKey]] = [
        [
            KeyboardKey(code: 53, label: "esc"),
            KeyboardKey(code: 122, label: "F1"), KeyboardKey(code: 120, label: "F2"),
            KeyboardKey(code: 99, label: "F3"), KeyboardKey(code: 118, label: "F4"),
            KeyboardKey(code: 96, label: "F5"), KeyboardKey(code: 97, label: "F6"),
            KeyboardKey(code: 98, label: "F7"), KeyboardKey(code: 100, label: "F8"),
            KeyboardKey(code: 101, label: "F9"), KeyboardKey(code: 109, label: "F10"),
            KeyboardKey(code: 103, label: "F11"), KeyboardKey(code: 111, label: "F12")
        ],
        [
            KeyboardKey(code: 50, label: "~"), KeyboardKey(code: 18, label: "1"),
            KeyboardKey(code: 19, label: "2"), KeyboardKey(code: 20, label: "3"),
            KeyboardKey(code: 21, label: "4"), KeyboardKey(code: 23, label: "5"),
            KeyboardKey(code: 22, label: "6"), KeyboardKey(code: 26, label: "7"),
            KeyboardKey(code: 28, label: "8"), KeyboardKey(code: 25, label: "9"),
            KeyboardKey(code: 29, label: "0"), KeyboardKey(code: 27, label: "-"),
            KeyboardKey(code: 24, label: "="), KeyboardKey(code: 51, label: "⌫", width: 1.5)
        ],
        [
            KeyboardKey(code: 48, label: "tab", width: 1.4),
            KeyboardKey(code: 12, label: "Q"), KeyboardKey(code: 13, label: "W"),
            KeyboardKey(code: 14, label: "E"), KeyboardKey(code: 15, label: "R"),
            KeyboardKey(code: 17, label: "T"), KeyboardKey(code: 16, label: "Y"),
            KeyboardKey(code: 32, label: "U"), KeyboardKey(code: 34, label: "I"),
            KeyboardKey(code: 31, label: "O"), KeyboardKey(code: 35, label: "P"),
            KeyboardKey(code: 33, label: "["), KeyboardKey(code: 30, label: "]"),
            KeyboardKey(code: 42, label: "\\", width: 1.4)
        ],
        [
            KeyboardKey(code: 57, label: "caps", width: 1.7),
            KeyboardKey(code: 0, label: "A"), KeyboardKey(code: 1, label: "S"),
            KeyboardKey(code: 2, label: "D"), KeyboardKey(code: 3, label: "F"),
            KeyboardKey(code: 5, label: "G"), KeyboardKey(code: 4, label: "H"),
            KeyboardKey(code: 38, label: "J"), KeyboardKey(code: 40, label: "K"),
            KeyboardKey(code: 37, label: "L"), KeyboardKey(code: 41, label: ";"),
            KeyboardKey(code: 39, label: "'"), KeyboardKey(code: 36, label: "↩", width: 1.8)
        ],
        [
            KeyboardKey(code: 56, label: "⇧", width: 2.2),
            KeyboardKey(code: 6, label: "Z"), KeyboardKey(code: 7, label: "X"),
            KeyboardKey(code: 8, label: "C"), KeyboardKey(code: 9, label: "V"),
            KeyboardKey(code: 11, label: "B"), KeyboardKey(code: 45, label: "N"),
            KeyboardKey(code: 46, label: "M"), KeyboardKey(code: 43, label: ","),
            KeyboardKey(code: 47, label: "."), KeyboardKey(code: 44, label: "/"),
            KeyboardKey(code: 60, label: "⇧", width: 2.2)
        ],
        [
            KeyboardKey(code: 63, label: "fn"), KeyboardKey(code: 59, label: "⌃"),
            KeyboardKey(code: 58, label: "⌥"), KeyboardKey(code: 55, label: "⌘"),
            KeyboardKey(code: 49, label: "space", width: 5),
            KeyboardKey(code: 54, label: "⌘"), KeyboardKey(code: 61, label: "⌥"),
            KeyboardKey(code: 123, label: "←"), KeyboardKey(code: 125, label: "↓"),
            KeyboardKey(code: 126, label: "↑"), KeyboardKey(code: 124, label: "→")
        ]
    ]

    private var maximumCount: Int { day.keyCodeCounts.values.max() ?? 0 }
    private var selectedKey: KeyboardKey? {
        guard let selectedCode else { return nil }
        return rows.flatMap { $0 }.first { $0.code == selectedCode }
    }
    private var selectedCount: Int {
        guard let selectedCode else { return 0 }
        return day.keyCodeCounts[String(selectedCode)] ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("按键热力图").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(periodLabel) · 点击按键查看次数")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            VStack(spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { entry in
                    keyboardRow(entry.element)
                }
            }

            HStack(spacing: 7) {
                Text(selectedKey.map { "\($0.label)：\(selectedCount.formatted()) 次" } ?? "每个键帽下方显示次数")
                    .font(.caption.monospacedDigit())
                Spacer()
                Text("少")
                LinearGradient(colors: [heatColor(for: 1), heatColor(for: max(maximumCount, 1))], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 54, height: 8)
                    .clipShape(Capsule())
                Text("多")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text("功能行读取 HID 按键事件，常见 Mac 键盘上即使 F3 触发 Mission Control，也会按 F3 计数；左右修饰键分别计数。只记录次数，不读取字符。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private func keyboardRow(_ keys: [KeyboardKey]) -> some View {
        GeometryReader { geometry in
            let totalKeyWidth = keys.reduce(CGFloat.zero) { $0 + $1.width }
            let gaps = CGFloat(max(keys.count - 1, 0)) * gap
            let unitWidth = max(12, (geometry.size.width - gaps) / totalKeyWidth)

            HStack(spacing: gap) {
                ForEach(keys) { key in
                    keyButton(key, unitWidth: unitWidth)
                }
            }
        }
        .frame(height: 34)
    }

    private func keyButton(_ key: KeyboardKey, unitWidth: CGFloat) -> some View {
        let count = day.keyCodeCounts[String(key.code)] ?? 0
        let intensity = maximumCount > 0 ? sqrt(Double(count) / Double(maximumCount)) : 0
        let selected = selectedCode == key.code

        return Button {
            selectedCode = key.code
        } label: {
            VStack(spacing: 1) {
                Text(key.label)
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(compactCount(count))
                    .font(.system(size: 7, weight: .regular, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(intensity > 0.62 ? Color.white : Color.primary)
            .frame(width: unitWidth * key.width, height: 32)
            .background(heatColor(for: count), in: RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(selected ? Color.primary : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .help("\(key.label)：\(count.formatted()) 次")
    }

    private func compactCount(_ count: Int) -> String {
        guard count > 0 else { return "·" }
        if count >= 10_000 { return "\(count / 1_000)k" }
        return count.formatted()
    }

    private func heatColor(for count: Int) -> Color {
        guard count > 0 else { return Color.primary.opacity(0.09) }
        let t = maximumCount > 0 ? sqrt(Double(count) / Double(maximumCount)) : 0
        return Color(
            red: min(1, 0.2 + 0.8 * t),
            green: min(1, 0.45 + 0.35 * (1 - t)),
            blue: max(0.08, 0.95 * (1 - t))
        )
    }
}
