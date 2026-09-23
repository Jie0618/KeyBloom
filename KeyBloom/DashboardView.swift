import Charts
import AppKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: StatsStore

    private var today: DayStats { store.stats(for: Date()) }
    private var categories: [(name: String, count: Int)] { store.categoryCounts(for: today) }
    private var largestCategory: Int { max(categories.map(\.count).max() ?? 1, 1) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                permissionCard
                startupCard
                todayCard
                hourlyCard
                KeyboardHeatmapView(day: today)
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

    private var todayCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("今天的按键次数")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(store.todayCount.formatted())
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("近 7 天平均")
                    .font(.caption).foregroundStyle(.secondary)
                Text((store.sevenDayTotal / 7).formatted())
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("次 / 天")
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
            sectionTitle("今天每小时", subtitle: "按键次数")
            Chart(0..<24, id: \.self) { hour in
                BarMark(
                    x: .value("小时", hour),
                    y: .value("按键次数", store.hourlyCount(hour))
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
            sectionTitle("近 7 天", subtitle: "每天的总次数")
            Chart(store.lastSevenDays) { day in
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
            sectionTitle("按键类型", subtitle: "今天")
            if categories.isEmpty {
                Text("开始统计后，这里会显示按键类型分布。")
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
