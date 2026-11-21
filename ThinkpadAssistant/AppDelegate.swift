//
//  AppDelegate.swift
//  ThinkpadAssistant
//
//  Copyright © 2020 Matthäus Szturc. All rights reserved.
//

import Cocoa
import ServiceManagement
import IOKit
import Darwin

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    let statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    
    let helperBundleName = "de.mszturc.AutoLaunchHelper"

    // Battery threshold (YogaSMC ThinkVPC) — lihat SUMMARY.md bagian 4 dan 9.
    private weak var thresholdBatteryItem: NSMenuItem?
    private weak var thresholdSummaryItem: NSMenuItem?
    private weak var thresholdStartItem: NSMenuItem?
    private weak var thresholdStopItem: NSMenuItem?
    private weak var thresholdEnableItem: NSMenuItem?
    private weak var updateMenuItem: NSMenuItem?

    @IBOutlet weak var statusBarMenu: NSMenu!
    
    @IBOutlet weak var monitorCapslocksMenuItem: NSMenuItem!
    @IBOutlet weak var launchAtLoginMenuItem: NSMenuItem!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupMenuBar()
        ShortcutManager.register()
        CapslockMonitor.register()
        checkForUpdates(silent: true)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        ShortcutManager.unregister()
    }
    
    @IBAction func launchAtLoginPressed(_ sender: NSMenuItem) {        
        if sender.state == .off {
            sender.state = .on
            SMLoginItemSetEnabled(helperBundleName as CFString, true)
        } else {
            sender.state = .off
            SMLoginItemSetEnabled(helperBundleName as CFString, false)
        }
    }
    
    @IBAction func monitorCapslockPressed(_ sender: NSMenuItem) {
        if(sender.state == .off) {
            sender.state = .on
            CapslockMonitor.start()
        } else {
            sender.state = .off
            CapslockMonitor.stop()
        }
    }

    func setupMenuBar() {
        statusItem.button?.image = NSImage(named: "menuIcon")
        statusItem.button?.alternateImage = NSImage(named: "menuIcon-light")
        
        statusItem.button?.image?.size = NSSize(width: 18, height: 18)
        statusItem.button?.alternateImage?.size = NSSize(width: 18, height: 18)
        
        statusItem.menu = statusBarMenu
        
        let foundHelper = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == helperBundleName
        }
        
        launchAtLoginMenuItem.state = foundHelper ? .on : .off

        monitorCapslocksMenuItem.state = CapslockMonitor.isActive ? .on : .off

        setupBatteryThresholdMenu()
        setupUpdateMenu()
    }

    // MARK: - Battery threshold (YogaSMC / ThinkVPC)
    //
    // Referensi lokal: YogaSMC 1.5.3. Threshold ditulis lewat properti IOUserClient,
    // BUKAN lewat SMC key B0St/B0Sp/B0En (key itu tidak ada / bukan threshold).
    //
    //   {"setCMstart": 80, "Battery": 1}  -> ThinkVPC::setPropertiesGated()
    //   {"setCMstop":  90, "Battery": 1}  -> ThinkVPC::setConservation()
    //                                     -> ACPI BCCS / BCSS -> EC
    //
    // "Battery": 0 = ANY, 1 = PRIMARY, 2 = SECONDARY (default YogaSMC = 1).
    // Nama key internal (BCTG/BCSG) sengaja TIDAK dipakai di UI — debug log saja.
    private enum BatteryThresholdError: LocalizedError {
        case serviceNotFound
        case setFailed(IOReturn)

        var errorDescription: String? {
            switch self {
            case .serviceNotFound:
                return NSLocalizedString("ThinkVPC (YogaSMC) service not found. Make sure YogaSMC 1.5.3 is loaded.", comment: "")
            case .setFailed(let kr):
                return String(format: NSLocalizedString("Could not write threshold (0x%08X). Administrator rights may be required.", comment: ""), kr)
            }
        }
    }

    private struct BatteryStatus {
        let name: String
        let percent: Int
        let stateText: String
    }

    private final class BatteryThresholdManager {
        static let shared = BatteryThresholdManager()
        private init() {}

        private let serviceName = "ThinkVPC"
        private let batteryProperty = "Battery"
        private let batteryIndex = 1   // BAT_PRIMARY

        private let defaults = UserDefaults.standard
        private let startKey = "BatteryThreshold.Start"
        private let stopKey = "BatteryThreshold.Stop"
        private let enabledKey = "BatteryThreshold.Enabled"

        private func stored(_ key: String, fallback: Int) -> Int {
            guard let value = defaults.object(forKey: key) as? Int else { return fallback }
            return min(100, max(0, value))
        }

        var start: Int { stored(startKey, fallback: 75) }
        var stop: Int { stored(stopKey, fallback: 85) }

        var isEnabled: Bool {
            get { defaults.object(forKey: enabledKey) as? Bool ?? true }
            set { defaults.set(newValue, forKey: enabledKey) }
        }

        private func copyService() throws -> io_registry_entry_t {
            let matching = IOServiceMatching(serviceName)
            let service = IOServiceGetMatchingService(kIOMasterPortDefault, matching)
            guard service != 0 else { throw BatteryThresholdError.serviceNotFound }
            return service
        }

        private func send(_ props: [String: Any]) throws {
            let service = try copyService()
            defer { IOObjectRelease(service) }
            let cfProps = props as NSDictionary as CFTypeRef

            // Jalur utama: IOKit registry setProperties -> YogaVPC::setProperties()
            var kr = IORegistryEntrySetCFProperties(service, cfProps)
            if kr == kIOReturnSuccess { return }

            // Fallback: user client resmi YogaSMC (IOConnectSetCFProperties).
            var connect: io_connect_t = 0
            let open = IOServiceOpen(service, mach_task_self_, 0, &connect)
            guard open == kIOReturnSuccess else { throw BatteryThresholdError.setFailed(kr) }
            defer { IOServiceClose(connect) }
            kr = IOConnectSetCFProperties(connect, cfProps)
            guard kr == kIOReturnSuccess else { throw BatteryThresholdError.setFailed(kr) }
        }

        /// Menulis threshold. Nilai disimpan agar menu tetap konsisten walaupun
        /// pembacaan ACPI belum ter-update. Jalur BCCS/BCSS tidak diubah.
        func apply(start: Int? = nil, stop: Int? = nil, enabled: Bool? = nil) throws {
            var s = start ?? self.start
            var t = stop ?? self.stop
            let e = enabled ?? self.isEnabled

            if start != nil { s = min(100, max(0, s)); defaults.set(s, forKey: startKey) }
            if stop != nil { t = min(100, max(0, t)); defaults.set(t, forKey: stopKey) }
            if enabled != nil { isEnabled = e }

            var props: [String: Any] = [batteryProperty: batteryIndex]
            if e {
                props["setCMstart"] = s
                props["setCMstop"] = t
            } else {
                props["setCMstart"] = 0
                props["setCMstop"] = 100
                props["setCMInhibitCharge"] = 0
            }
            try send(props)
        }

        /// Debug saja: nama key internal tetap ada di log, tidak di menu.
        func logRawThresholds() {
            guard let service = try? copyService() else { return }
            defer { IOObjectRelease(service) }
            let raw = IORegistryEntryCreateCFProperty(service, "BAT_PRIMARY" as CFString, kCFAllocatorDefault, 0)
            if let dict = raw?.takeRetainedValue() as? NSDictionary {
                NSLog("[BatteryThreshold] debug raw BAT_PRIMARY: %@", dict.description)
            }
        }

        // MARK: Baterai (IORegistry, bukan BCTG/BCSG)

        private func boolProperty(_ key: String, _ service: io_registry_entry_t) -> Bool? {
            let raw = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
            return raw?.takeRetainedValue() as? Bool
        }

        private func intProperty(_ key: String, _ service: io_registry_entry_t) -> Int? {
            let raw = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
            return (raw?.takeRetainedValue() as? NSNumber)?.intValue
        }

        private func batteryName(_ service: io_registry_entry_t) -> String {
            // Naik beberapa level sampai ketemu nama device ACPI (BAT0 / BAT1).
            var current = service
            var ownsCurrent = false
            for _ in 0..<5 {
                var buffer = [CChar](repeating: 0, count: 128)
                if IORegistryEntryGetName(current, &buffer) == kIOReturnSuccess {
                    let name = String(cString: buffer)
                    if name.hasPrefix("BAT") {
                        if ownsCurrent { IOObjectRelease(current) }
                        return name
                    }
                }
                var parent: io_registry_entry_t = 0
                guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == kIOReturnSuccess,
                      parent != 0 else { break }
                if ownsCurrent { IOObjectRelease(current) }
                current = parent
                ownsCurrent = true
            }
            if ownsCurrent { IOObjectRelease(current) }
            return "BAT0"
        }

        private func readBattery(_ service: io_registry_entry_t) -> BatteryStatus? {
            guard boolProperty("BatteryInstalled", service) ?? false else { return nil }
            let current = intProperty("CurrentCapacity", service) ?? 0
            let capacity = intProperty("MaxCapacity", service) ?? 0
            let percent = capacity > 0
                ? min(100, max(0, Int(round(Double(current) / Double(capacity) * 100))))
                : 0

            let charging = boolProperty("IsCharging", service) ?? false
            let connected = boolProperty("ExternalConnected", service) ?? false
            let stateText: String
            if charging {
                stateText = NSLocalizedString("Charging ⚡", comment: "")
            } else if connected {
                stateText = NSLocalizedString("Not Charging 🔌", comment: "")
            } else {
                stateText = NSLocalizedString("Discharging 🔋", comment: "")
            }
            return BatteryStatus(name: batteryName(service), percent: percent, stateText: stateText)
        }

        /// Cari satu-satunya baterai yang terpasang. Tidak pernah menampilkan BAT0+BAT1.
        func batteryStatus() -> BatteryStatus {
            let matching = IOServiceMatching("AppleSmartBattery")
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iterator) == kIOReturnSuccess else {
                return BatteryStatus(name: "BAT0", percent: 0, stateText: NSLocalizedString("Unknown", comment: ""))
            }
            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                let status = readBattery(service)
                IOObjectRelease(service)
                if let status = status { return status }
                service = IOIteratorNext(iterator)
            }
            return BatteryStatus(name: "BAT0", percent: 0, stateText: NSLocalizedString("Unknown", comment: ""))
        }
    }

    private func valueSubmenu(tagBase: Int, action: Selector) -> NSMenu {
        let menu = NSMenu()
        for value in stride(from: 0, through: 100, by: 5) {
            let choice = NSMenuItem(title: "\(value)%", action: action, keyEquivalent: "")
            choice.target = self
            choice.tag = tagBase + value
            menu.addItem(choice)
        }
        return menu
    }

    private func setupBatteryThresholdMenu() {
        // Menu utama bersih: About, Monitor Capslock, Launch on Login, Battery Threshold, Quit.
        for item in statusBarMenu.items where item.isSeparatorItem {
            statusBarMenu.removeItem(item)
        }

        let item = NSMenuItem(title: NSLocalizedString("Battery Threshold", comment: ""), action: nil, keyEquivalent: "")
        let menu = NSMenu()

        let batteryLine = NSMenuItem(title: "…", action: nil, keyEquivalent: "")
        let summaryLine = NSMenuItem(title: "…", action: nil, keyEquivalent: "")
        batteryLine.isEnabled = false
        summaryLine.isEnabled = false
        menu.addItem(batteryLine)
        menu.addItem(summaryLine)
        thresholdBatteryItem = batteryLine
        thresholdSummaryItem = summaryLine
        menu.addItem(NSMenuItem.separator())

        let startItem = NSMenuItem(title: NSLocalizedString("Set Start Charge At", comment: ""), action: nil, keyEquivalent: "")
        startItem.submenu = valueSubmenu(tagBase: 1000, action: #selector(setStart(_:)))
        menu.addItem(startItem)
        thresholdStartItem = startItem

        let stopItem = NSMenuItem(title: NSLocalizedString("Set Stop Charge At", comment: ""), action: nil, keyEquivalent: "")
        stopItem.submenu = valueSubmenu(tagBase: 2000, action: #selector(setStop(_:)))
        menu.addItem(stopItem)
        thresholdStopItem = stopItem

        menu.addItem(NSMenuItem.separator())
        let enable = NSMenuItem(title: NSLocalizedString("Enable Threshold", comment: ""), action: #selector(toggleThreshold(_:)), keyEquivalent: "")
        enable.target = self
        menu.addItem(enable)
        thresholdEnableItem = enable

        let refresh = NSMenuItem(title: NSLocalizedString("Refresh Threshold", comment: ""), action: #selector(refreshThresholdMenu), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        item.submenu = menu
        // Sebelum item terakhir (Quit).
        statusBarMenu.insertItem(item, at: max(0, statusBarMenu.items.count - 1))
        refreshThresholdMenu()
    }

    private func setCheckmarks(in menu: NSMenu?, base: Int, current: Int) {
        guard let menu = menu else { return }
        for choice in menu.items {
            choice.state = (choice.tag - base == current) ? .on : .off
        }
    }

    @objc private func refreshThresholdMenu() {
        let manager = BatteryThresholdManager.shared
        let battery = manager.batteryStatus()

        thresholdBatteryItem?.title = String(
            format: NSLocalizedString("%@ - %d%% - %@", comment: ""),
            battery.name, battery.percent, battery.stateText
        )
        thresholdSummaryItem?.title = String(
            format: NSLocalizedString("Threshold: Start %d%% → Stop %d%%", comment: ""),
            manager.start, manager.stop
        )
        thresholdEnableItem?.state = manager.isEnabled ? .on : .off
        setCheckmarks(in: thresholdStartItem?.submenu, base: 1000, current: manager.start)
        setCheckmarks(in: thresholdStopItem?.submenu, base: 2000, current: manager.stop)

        // Debug saja — tidak pernah tampil di UI.
        manager.logRawThresholds()
    }

    @objc private func setStart(_ sender: NSMenuItem) {
        applyThreshold(start: sender.tag - 1000)
    }

    @objc private func setStop(_ sender: NSMenuItem) {
        applyThreshold(stop: sender.tag - 2000)
    }

    @objc private func toggleThreshold(_ sender: NSMenuItem) {
        applyThreshold(enabled: !BatteryThresholdManager.shared.isEnabled)
    }

    private func applyThreshold(start: Int? = nil, stop: Int? = nil, enabled: Bool? = nil) {
        do {
            try BatteryThresholdManager.shared.apply(start: start, stop: stop, enabled: enabled)
            refreshThresholdMenu()
        } catch {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Battery Threshold", comment: "")
            alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            alert.runModal()
        }
    }

    // MARK: - Update check (GitHub Releases)
    //
    // Repository: Syuhadak27/ThinkpadAssistent
    // Release dibuat otomatis oleh GitHub Actions (.github/workflows/release.yml).
    private enum UpdateCheck {
        static let apiURL = "https://api.github.com/repos/Syuhadak27/ThinkpadAssistent/releases/latest"
        static let tagKey = "UpdateCheck.LastSeenTag"
    }

    private func setupUpdateMenu() {
        let item = NSMenuItem(
            title: NSLocalizedString("Check for Updates...", comment: ""),
            action: #selector(checkForUpdatesPressed(_:)),
            keyEquivalent: ""
        )
        item.target = self
        statusBarMenu.insertItem(item, at: max(0, statusBarMenu.items.count - 1))
        updateMenuItem = item
    }

    @objc private func checkForUpdatesPressed(_ sender: Any?) {
        checkForUpdates(silent: false)
    }

    private func checkForUpdates(silent: Bool) {
        guard let url = URL(string: UpdateCheck.apiURL) else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ThinkpadAssistant", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                self?.handleUpdateResponse(data: data, error: error, silent: silent)
            }
        }.resume()
    }

    private func handleUpdateResponse(data: Data?, error: Error?, silent: Bool) {
        if let error = error {
            if !silent {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Update Check Failed", comment: "")
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                alert.runModal()
            }
            return
        }

        guard let data = data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = json["tag_name"] as? String, !tag.isEmpty else {
            if !silent {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Update Check Failed", comment: "")
                alert.informativeText = NSLocalizedString("Could not read the latest release from GitHub.", comment: "")
                alert.alertStyle = .warning
                alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                alert.runModal()
            }
            return
        }

        let htmlURL = json["html_url"] as? String ?? "https://github.com/Syuhadak27/ThinkpadAssistent/releases"
        let defaults = UserDefaults.standard
        let lastTag = defaults.string(forKey: UpdateCheck.tagKey)

        if lastTag == tag {
            updateMenuItem?.title = NSLocalizedString("Check for Updates...", comment: "")
            if !silent {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("You're up to date", comment: "")
                alert.informativeText = String(format: NSLocalizedString("Latest release: %@", comment: ""), tag)
                alert.alertStyle = .informational
                alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                alert.runModal()
            }
            return
        }

        // Release berbeda / belum pernah dicek -> tawarkan update.
        updateMenuItem?.title = String(format: NSLocalizedString("Update Available (%@)", comment: ""), tag)
        guard !silent else { return }

        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Update %@ is available", comment: ""), tag)
        alert.informativeText = NSLocalizedString("A new build has been published on GitHub Releases.", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("Download", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Skip This Version", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Later", comment: ""))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: htmlURL) { NSWorkspace.shared.open(url) }
            defaults.set(tag, forKey: UpdateCheck.tagKey)
            updateMenuItem?.title = NSLocalizedString("Check for Updates...", comment: "")
        case .alertSecondButtonReturn:
            defaults.set(tag, forKey: UpdateCheck.tagKey)
            updateMenuItem?.title = NSLocalizedString("Check for Updates...", comment: "")
        default:
            break
        }
    }

    @IBAction func quitPressed(_ sender: Any) {
        NSApp.terminate(self)
    }
    
}

