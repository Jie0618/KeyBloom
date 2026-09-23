import Charts
import AppKit
import SwiftUI

private enum UsagePeriod: String, CaseIterable, Identifiable {
    case day
    case week

    var id: String { rawValue }
    var title: String { self == .day ? "日" : "周" }
    var calendarComponent: Calendar.Component { self == .day ? .day : .weekOfYear }
}

struct DashboardView: View {
    @EnvironmentObject private var store: StatsStore
    @State private var usagePeriod: UsagePeriod = .day
    @State private var selectedDate = Date()
    @State private var isDatePickerPresented = false

    private var today: DayStats { store.stats(for: Date()) }
    private var selectedStats: DayStats {
        usagePeriod == .day ? store.stats(for: selectedDate) : store.stats(forWeekContaining: selectedDate)
    }
    private var trendDays: [DayStats] {
        usagePeriod == .week ? store.days(inWeekContaining: selectedDate) : store.lastSevenDays
    }
    private var categories: [(name: String, count: Int)] { store.categoryCounts(for: selectedStats) }
    private var largestCategory: Int { max(categories.map(\.count).max() ?? 1, 1) }
    private var selectedPeriodLabel: String {
        switch usagePeriod {
        case .day:
            return selectedDate.formatted(date: .numeric, time: .omitted)
        case .week:
            let calendar = Calendar.current
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
                return selectedDate.formatted(date: .numeric, time: .omitted)
            }
            let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            let format = Date.FormatStyle.dateTime.month(.defaultDigits).day()
            return "\(interval.start.formatted(format))–\(lastDay.formatted(format))"
        }
    }
    private var canAdvancePeriod: Bool {
        guard let next = Calendar.current.date(byAdding: usagePeriod.calendarComponent, value: 1, to: selectedDate) else {
            return false
        }
        return Calendar.current.startOfDay(for: next) <= Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                permissionCard
                startupCard
                historyFilterCard
                summaryCard
                hourlyCard
                KeyboardHeatmapView(
                    day: selectedStats,
                    periodLabel: usagePeriod == .day ? "所选日期" : "所选周"
                )
                weeklyCard
                categoryCard
                footer
            }
            .padding(16)
        }
        .frame(width: 390, height: 610)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            store.refreshLaunchAtLoginStatus()
            store.refreshPermission()
        }
    }

    private var historyFilterCard: some View {
        HStack(spacing: 6) {
            Picker("范围", selection: $usagePeriod) {
                ForEach(UsagePeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 76)

            Button {
                movePeriod(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .help("上一个\(usagePeriod == .day ? "日期" : "星期")")

            Text(selectedPeriodLabel)
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Button(usagePeriod == .day ? "今天" : "本周") {
                selectedDate = Date()
            }
            .buttonStyle(.plain)

            Button {
                movePeriod(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(!canAdvancePeriod)
            .help("下一个\(usagePeriod == .day ? "日期" : "星期")")

            Button {
                isDatePickerPresented = true
            } label: {
                Image(systemName: "calendar")
            }
            .buttonStyle(.plain)
            .help("选择日期")
            .popover(isPresented: $isDatePickerPresented, arrowEdge: .bottom) {
                DatePicker(
                    "选择日期",
                    selection: $selectedDate,
                    in: Date.distantPast...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding(8)
                .frame(width: 280)
            }
        }
        .font(.caption)
        .padding(9)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private func movePeriod(by amount: Int) {
        guard let next = Calendar.current.date(
            byAdding: usagePeriod.calendarComponent,
            value: amount,
            to: selectedDate
        ) else { return }
        if amount < 0 || Calendar.current.startOfDay(for: next) <= Calendar.current.startOfDay(for: Date()) {
            selectedDate = next
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("KeyBloom").font(.title2.bold())
                Text(Date.now.formatted(date: .complete, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(store.isMonitoring ? Color.green : Color.gray)
                .frame(width: 9, height: 9)
            Text(store.isMonitoring ? "统计中" : "已暂停")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.permissionGranted {
                HStack {
                    Label("输入监控权限已开启", systemImage: "checkmark.shield.fill")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button(store.isMonitoring ? "暂停" : "刷新并开始") {
                        if store.isMonitoring {
                            store.toggleMonitoring()
                        } else {
                            store.checkPermissionAndStart()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                if store.isMonitoring {
                    HStack(alignment: .center) {
                        Text(store.lastKeyEventAt.map {
                            "最近收到按键：\($0.formatted(date: .omitted, time: .standard))"
                        } ?? "监听已连接；请在其他 App 按键测试。")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Button("重新连接") { store.checkPermissionAndStart() }
                            .controlSize(.small)
                    }
                }
                Button("打开输入监控设置") { store.openInputMonitoringSettings() }
                    .controlSize(.small)
            } else {
                Label("需要输入监控授权", systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.medium))
                Text("macOS 需要你的明确授权，才能统计你在其他 App 中按下的按键。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("申请授权") { store.requestPermissionAndStart() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("刷新并开始") { store.checkPermissionAndStart() }
                        .controlSize(.small)
                }
            }
            if let message = store.statusMessage {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var summaryCard: some View {
        let usedKeyCount = selectedStats.keyCodeCounts.values.filter { $0 > 0 }.count
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(usagePeriod == .day ? "所选日期按键次数" : "所选周按键次数")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(selectedStats.total.formatted())
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("有记录的键位")
                    .font(.caption).foregroundStyle(.secondary)
                Text(usedKeyCount.formatted())
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("种")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var startupCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(
                "登录时自动启动",
                isOn: Binding(
                    get: { store.launchAtLoginEnabled },
                    set: { store.setLaunchAtLogin($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)

            if let message = store.launchAtLoginMessage {
                Text(message)
                    .font(.caption).foregroundStyle(.secondary)
            } else if store.launchAtLoginEnabled {
                Text("启动后会自动开始统计。关闭此面板不影响统计。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private var hourlyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(
                usagePeriod == .day ? "所选日期每小时" : "所选周按小时累计",
                subtitle: "按键次数"
            )
            Chart(0..<24, id: \.self) { hour in
                BarMark(
                    x: .value("小时", hour),
                    y: .value("按键次数", selectedStats.hourlyCounts[String(format: "%02d", hour)] ?? 0)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 4)) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) { Text("\(hour)") }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 105)
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private var weeklyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(
                usagePeriod == .week ? "所选周逐日" : "近 7 天",
                subtitle: "每天的总次数"
            )
            Chart(trendDays) { day in
                BarMark(
                    x: .value("日期", day.dateKey),
                    y: .value("按键次数", day.total)
                )
                .foregroundStyle(day.dateKey == today.dateKey ? Color.accentColor : Color.accentColor.opacity(0.48))
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 7)) { value in
                    AxisValueLabel {
                        if let key = value.as(String.self) {
                            Text(String(key.suffix(5)))
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 95)
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("按键类型", subtitle: usagePeriod == .day ? selectedPeriodLabel : "所选周")
            if categories.isEmpty {
                Text("所选范围暂无记录。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(categories.enumerated()), id: \.offset) { entry in
                    let item = entry.element
                    HStack(spacing: 8) {
                        Text(item.name).font(.caption).frame(width: 76, alignment: .leading)
                        ProgressView(value: Double(item.count), total: Double(largestCategory))
                            .tint(.accentColor)
                        Text(item.count.formatted())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 55, alignment: .trailing)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack(alignment: .center) {
            Text("关闭面板仍会统计；退出程序后暂停。数据只保存在本机。")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Button("退出并停止") {
                store.stopAndSave()
                NSApplication.shared.terminate(nil)
            }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
