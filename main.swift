// StayAwake — macOS 菜单栏"锁屏不休眠"开关
//
// 用途：手动锁屏（屏幕变黑）不想让别人看到屏幕内容，但又希望后台 agent 继续干活。
// 点一下菜单栏图标 → app 持有 PreventUserIdleSystemSleep 电源断言：屏幕仍按系统
// 设置变黑/锁屏，但系统不会空闲睡眠，Wi-Fi 不断、后台任务继续跑。
// 再点一下 → 释放断言，一切恢复系统默认（空闲到时间就正常睡眠）。
//
// 技术选型：IOPMAssertion（用户态电源断言），不改 pmset 全局设置、无需 sudo、
// 完全可逆；系统设置里的"显示器关闭后睡眠"等保持原样。
//
// 参考：与 ~/gitlab-pipeline-monitor 同一套构建/签名/菜单栏写法。

import AppKit
import IOKit.pwr_mgt

// MARK: - 电源断言管理

final class PowerAssertion {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    /// 持有"阻止空闲系统睡眠"断言。屏幕变黑/锁屏不受影响，只拦"系统睡眠"。
    func enable() {
        guard !isActive else { return }
        // PreventUserIdleSystemSleep：只阻止"空闲"睡眠；合盖（lid close）仍会睡，
        // 这正是想要的——手动合盖该睡还是睡。
        let ret = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "StayAwake: 锁屏后后台继续工作" as CFString,
            &assertionID)
        if ret == kIOReturnSuccess {
            isActive = true
        } else {
            NSLog("StayAwake: 创建电源断言失败 ret=\(ret)")
        }
    }

    /// 释放断言，恢复系统默认空闲睡眠行为。
    func disable() {
        guard isActive else { return }
        let ret = IOPMAssertionRelease(assertionID)
        if ret == kIOReturnSuccess {
            isActive = false
        } else {
            NSLog("StayAwake: 释放电源断言失败 ret=\(ret)")
        }
    }
}

// MARK: - 相对时间文本

private func relativeText(_ date: Date) -> String {
    let f = DateComponentsFormatter()
    f.allowedUnits = [.hour, .minute]
    f.unitsStyle = .abbreviated
    f.collapsesLargestUnit = false
    let s = f.string(from: date, to: Date()) ?? ""
    return s.isEmpty ? "刚刚" : "\(s)前"
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let power = PowerAssertion()
    private var awakeSince: Date?   // 开启时刻，用于菜单展示"已持续"
    private var timer: Timer?       // 开启状态下定时刷新菜单/图标（显示持续时长）

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.icon(active: false)
            button.toolTip = "StayAwake · 锁屏不休眠开关"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // App 本身别被 App Nap 挂起（断言持有期间尤其重要）
        ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "StayAwake 常驻")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 退出时释放断言，不留悬挂断言
        power.disable()
    }

    // MARK: 图标

    private static func icon(active: Bool) -> NSImage? {
        // 开启：实心月亮+绿点太难辨认，直接用 SF Symbols：
        // 关闭 = moon.fill 灰色（系统默认会睡）；开启 = moon.fill 绿色 + zzz 被划掉的感觉不好做，
        // 用 "cup.and.saucer.fill"? 太生活化。最直观：电风扇/电源。最终选：
        // 关闭 = power 圆圈灰；开启 = power 圆圈绿色。
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let name = active ? "moon.circle.fill" : "moon.circle"
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            // SF Symbol 不可用时退化为纯色圆点
            let side: CGFloat = 18
            let img = NSImage(size: NSSize(width: side, height: side))
            img.lockFocus()
            (active ? NSColor.systemGreen : NSColor.systemGray).set()
            NSBezierPath(ovalIn: NSRect(x: side / 2 - 5.5, y: side / 2 - 5.5, width: 11, height: 11)).fill()
            img.unlockFocus()
            img.isTemplate = false
            return img
        }
        let size = base.size
        let img = NSImage(size: size)
        img.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size))
        (active ? NSColor.systemGreen : NSColor.systemGray).set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.image = Self.icon(active: power.isActive)
        button.toolTip = power.isActive
            ? "StayAwake：开启中（\(relativeText(awakeSince ?? Date()))起），锁屏后系统不休眠"
            : "StayAwake：未开启（系统按默认设置空闲睡眠）"
    }

    // MARK: 菜单

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu: menu)
    }

    private func rebuild(menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        let title = power.isActive
            ? "🌙 锁屏不休眠：已开启（\(relativeText(awakeSince ?? Date()))起）"
            : "🌙 锁屏不休眠：未开启"
        let toggle = NSMenuItem(title: title, action: #selector(toggleAwake), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        let explain = NSMenuItem(title: power.isActive
            ? "屏幕照常变黑锁屏，系统不睡，后台继续跑"
            : "点上面开关后：锁屏不睡，再点恢复默认", action: nil, keyEquivalent: "")
        explain.isEnabled = false
        menu.addItem(explain)

        if power.isActive {
            let now = NSMenuItem(title: "现在锁屏（立即变黑）", action: #selector(lockScreenNow), keyEquivalent: "")
            now.target = self
            menu.addItem(now)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 StayAwake", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: 动作

    @objc private func toggleAwake() {
        if power.isActive {
            power.disable()
            awakeSince = nil
            timer?.invalidate()
            timer = nil
        } else {
            power.enable()
            awakeSince = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.updateIcon()
            }
        }
        updateIcon()
    }

    /// 立即锁屏：触发系统锁屏（屏幕按设置变黑），等同 Ctrl+Cmd+Q
    @objc private func lockScreenNow() {
        // 以 root 权限要求系统立即锁屏；这是 Apple 官方支持的自动锁屏入口
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // 菜单栏常驻，不占 Dock
app.run()
