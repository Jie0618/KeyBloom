import Combine
import CoreGraphics
import Foundation
import AppKit
import ServiceManagement
import IOKit.hidsystem

struct DayStats: Codable, Identifiable {
    let dateKey: String
    var total: Int = 0
    var hourlyCounts: [String: Int] = [:]
    var keyCodeCounts: [String: Int] = [:]

    var id: String { dateKey }
}

private struct StoredStats: Codable {
    var days: [String: DayStats] = [:]
}

@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var days: [String: DayStats] = [:]
    @Published private(set) var permissionGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    @Published private(set) var isMonitoring = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginMessage: String?
    @Published private(set) var lastKeyEventAt: Date?

    private let monitor = KeyboardMonitor()
    private var userPausedMonitoring = false
    private var saveTimer: Timer?
    private var terminationObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private let fileURL: URL
    private let loginItemOptOutKey = "launchAtLoginDisabledByUser"

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("KeyTrack", isDirectory: true)
        fileURL = directory.appendingPathComponent("keyboard-stats.json")
        load()
        updateLaunchAtLoginState()

        monitor.onKeyDown = { [weak self] keyCode, date in
            self?.record(keyCode: keyCode, at: date)
        }

        saveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.save() }
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.monitor.stop()
                self?.save()
            }
        }

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApplication.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPermission() }
        }

        DispatchQueue.main.async { [weak self] in
            Task { @MainActor [weak self] in self?.activateOnLaunch() }
        }
    }

    var todayCount: Int { stats(for: Date()).total }

    var lastSevenDays: [DayStats] {
        (0..<7).compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: offset - 6, to: Date()) else { return nil }
            return stats(for: date)
        }
    }

    var sevenDayTotal: Int { lastSevenDays.reduce(0) { $0 + $1.total } }

    func stats(for date: Date) -> DayStats {
        days[dateKey(for: date)] ?? DayStats(dateKey: dateKey(for: date))
    }

    func hourlyCount(_ hour: Int) -> Int {
        stats(for: Date()).hourlyCounts[String(format: "%02d", hour)] ?? 0
    }

    func categoryCounts(for day: DayStats) -> [(name: String, count: Int)] {
        var totals: [String: Int] = [:]
        for (codeString, count) in day.keyCodeCounts {
            guard let code = Int(codeString) else { continue }
            totals[KeyCategory.name(for: code), default: 0] += count
        }
        return KeyCategory.displayOrder.compactMap { name in
            guard let count = totals[name], count > 0 else { return nil }
            return (name, count)
        }
    }

    func requestPermissionAndStart() {
        userPausedMonitoring = false
        if !inputMonitoringPermissionIsGranted() {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        permissionGranted = inputMonitoringPermissionIsGranted()
        if permissionGranted {
            if !restartMonitoring() {
                statusMessage = "权限已检测到，但键盘监听没有启动。请确认启用的是 ~/Applications/KeyBloom.app；必要时关闭旧版 KeyBloom 授权后重新启用。"
            }
        } else {
            statusMessage = "请在“输入监控”中启用 ~/Applications/KeyBloom.app（不要选 Terminal），然后回到此面板点“刷新并开始”。"
        }
        openInputMonitoringSettings()
    }

    func activateOnLaunch() {
        permissionGranted = inputMonitoringPermissionIsGranted()
        if permissionGranted {
            startMonitoring()
        } else {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            permissionGranted = inputMonitoringPermissionIsGranted()
            if !permissionGranted {
                statusMessage = "首次运行需允许输入监控；请在系统设置中授权后回来点击“刷新并开始”。"
            } else if !attemptStartMonitoring() {
                statusMessage = "已检测到授权，但键盘监听没有启动。请完全退出 KeyBloom 后重新打开。"
            }
        }
        if !UserDefaults.standard.bool(forKey: loginItemOptOutKey) {
            registerLaunchAtLoginIfNeeded()
        }
    }

    func refreshPermission() {
        permissionGranted = inputMonitoringPermissionIsGranted()
        if permissionGranted && !userPausedMonitoring {
            restartMonitoring()
        } else if !permissionGranted && isMonitoring {
            monitor.stop()
            isMonitoring = false
        }
    }

    func checkPermissionAndStart() {
        userPausedMonitoring = false
        permissionGranted = inputMonitoringPermissionIsGranted()
        if !permissionGranted {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            permissionGranted = inputMonitoringPermissionIsGranted()
        }
        if permissionGranted {
            if !restartMonitoring() {
                statusMessage = "权限已检测到，但键盘监听没有启动。请确认启用的是 ~/Applications/KeyBloom.app；必要时关闭旧版 KeyBloom 授权后重新启用。"
                openInputMonitoringSettings()
            }
        } else {
            statusMessage = "系统尚未确认 KeyBloom 的输入监控权限。请启用 ~/Applications/KeyBloom.app；不要授权 Terminal。"
            openInputMonitoringSettings()
        }
    }

    func openInputMonitoringSettings() {
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
        ]
        for string in settingsURLs {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
        statusMessage = "无法自动打开设置。请手动进入“系统设置 > 隐私与安全性 > 输入监控”。"
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        UserDefaults.standard.set(!enabled, forKey: loginItemOptOutKey)
        do {
            if enabled {
                switch SMAppService.mainApp.status {
                case .enabled, .requiresApproval:
                    break
                case .notRegistered:
                    try SMAppService.mainApp.register()
                case .notFound:
                    launchAtLoginMessage = "请先从“运行KeyBloom.command”安装应用，再启用开机启动。"
                    return
                @unknown default:
                    try SMAppService.mainApp.register()
                }
            } else {
                switch SMAppService.mainApp.status {
                case .notRegistered, .notFound:
                    break
                case .enabled, .requiresApproval:
                    try SMAppService.mainApp.unregister()
                @unknown default:
                    try SMAppService.mainApp.unregister()
                }
            }
            updateLaunchAtLoginState()
        } catch {
            updateLaunchAtLoginState()
            launchAtLoginMessage = "开机启动设置未完成：\(error.localizedDescription)"
        }
    }

    func toggleMonitoring() {
        if isMonitoring {
            monitor.stop()
            isMonitoring = false
            userPausedMonitoring = true
            statusMessage = "统计已暂停"
            save()
        } else {
            userPausedMonitoring = false
            if inputMonitoringPermissionIsGranted() {
                permissionGranted = true
                startMonitoring()
            } else {
                requestPermissionAndStart()
            }
        }
    }

    func stopAndSave() {
        monitor.stop()
        isMonitoring = false
        save()
    }

    func refreshLaunchAtLoginStatus() {
        updateLaunchAtLoginState()
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(StoredStats(days: days))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            statusMessage = "保存统计数据失败：\(error.localizedDescription)"
        }
    }

    private func startMonitoring() {
        guard permissionGranted else { return }
        if attemptStartMonitoring() {
            return
        } else {
            statusMessage = "权限已检测到，但 macOS 拒绝创建键盘监听。请确认启用的是 ~/Applications/KeyBloom.app；授权后完全退出并重新打开它。"
        }
    }

    @discardableResult
    private func restartMonitoring() -> Bool {
        monitor.stop()
        isMonitoring = false
        return attemptStartMonitoring()
    }

    @discardableResult
    private func attemptStartMonitoring() -> Bool {
        if monitor.start() {
            isMonitoring = true
            permissionGranted = true
            statusMessage = nil
            return true
        } else {
            isMonitoring = false
            return false
        }
    }

    private func registerLaunchAtLoginIfNeeded() {
        switch SMAppService.mainApp.status {
        case .enabled:
            updateLaunchAtLoginState()
        case .notRegistered:
            do {
                try SMAppService.mainApp.register()
                updateLaunchAtLoginState()
            } catch {
                updateLaunchAtLoginState()
                launchAtLoginMessage = "开机启动未能启用：\(error.localizedDescription)"
            }
        case .requiresApproval:
            updateLaunchAtLoginState()
        case .notFound:
            updateLaunchAtLoginState()
            launchAtLoginMessage = "请从“运行KeyBloom.command”安装到当前用户的 ~/Applications 后再启用开机启动。"
        @unknown default:
            updateLaunchAtLoginState()
        }
    }

    private func updateLaunchAtLoginState() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginEnabled = true
            launchAtLoginMessage = nil
        case .notRegistered:
            launchAtLoginEnabled = false
            launchAtLoginMessage = nil
        case .requiresApproval:
            launchAtLoginEnabled = false
            launchAtLoginMessage = "已登记开机启动；请到“系统设置 > 通用 > 登录项”允许 KeyBloom 在后台运行。"
        case .notFound:
            launchAtLoginEnabled = false
            launchAtLoginMessage = "请从“运行KeyBloom.command”安装到当前用户的 ~/Applications 后再启用开机启动。"
        @unknown default:
            launchAtLoginEnabled = false
        }
    }

    private func record(keyCode: Int, at date: Date) {
        lastKeyEventAt = date
        let key = dateKey(for: date)
        var day = days[key] ?? DayStats(dateKey: key)
        let hour = String(format: "%02d", Calendar.current.component(.hour, from: date))
        day.total += 1
        day.hourlyCounts[hour, default: 0] += 1
        day.keyCodeCounts[String(keyCode), default: 0] += 1
        days[key] = day
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(StoredStats.self, from: data) else { return }
        days = stored.days
    }

    private func dateKey(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func inputMonitoringPermissionIsGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }
}

private enum KeyCategory {
    static let displayOrder = ["字母", "数字", "标点与控制", "修饰键", "导航键", "其他"]

    static func name(for code: Int) -> String {
        if letters.contains(code) { return "字母" }
        if numbers.contains(code) { return "数字" }
        if punctuationAndControl.contains(code) { return "标点与控制" }
        if modifiers.contains(code) { return "修饰键" }
        if navigation.contains(code) { return "导航键" }
        return "其他"
    }

    private static let letters: Set<Int> = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 31, 32, 34, 35, 37, 38, 40, 45, 46]
    private static let numbers: Set<Int> = [18, 19, 20, 21, 22, 23, 25, 26, 28, 29, 65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]
    private static let punctuationAndControl: Set<Int> = [24, 27, 30, 33, 36, 39, 41, 42, 43, 44, 47, 48, 49, 50, 51, 53]
    private static let modifiers: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
    private static let navigation: Set<Int> = [114, 115, 116, 117, 119, 121, 123, 124, 125, 126]
}
