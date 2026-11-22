//
//  AppDelegate.swift
//  ThinkpadAssistant
//
//  Dikelola oleh Syuhadak27. https://github.com/Syuhadak27/ThinkpadAssistent
//

import Cocoa
import ServiceManagement
import IOKit
import IOKit.ps
import Darwin
import Sparkle

private extension Notification.Name {
    static let powerSourceDidChange = Notification.Name("BatterySync.PowerSourceDidChange")
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    let statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    
    let helperBundleName = "de.mszturc.AutoLaunchHelper"

    // Battery threshold (YogaSMC ThinkVPC) — lihat SUMMARY.md bagian 4 dan 9.
    private weak var thresholdBatteryItem: NSMenuItem?
    private weak var thresholdEC0Item: NSMenuItem?
    private weak var thresholdEC1Item: NSMenuItem?
    private weak var thresholdSummaryItem: NSMenuItem?
    private weak var thresholdStartItem: NSMenuItem?
    private weak var thresholdStopItem: NSMenuItem?
    private weak var thresholdEnableItem: NSMenuItem?

    // Sparkle 2 — singleton, dibuat di main actor saat menu disiapkan.
    @MainActor private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    // Battery sync monitoring (IOPowerSources = sumber angka ikon macOS).
    private var batteryRefreshTimer: Timer?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var batteryMismatchSince: Date?
    private var lastDisplayedPercent: Int?
    private var pendingForceApply: DispatchWorkItem?

    @IBOutlet weak var statusBarMenu: NSMenu!
    
    @IBOutlet weak var monitorCapslocksMenuItem: NSMenuItem!
    @IBOutlet weak var launchAtLoginMenuItem: NSMenuItem!
    
    @MainActor
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupMenuBar()
        ShortcutManager.register()
        CapslockMonitor.register()
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

    @MainActor
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
        startBatteryMonitoring()
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

    /// Sumber kebenaran: IOPowerSources — persis yang dipakai macOS untuk ikon baterai.
    /// Di X260 ini menggabungkan BAT0 + BAT1 menjadi satu "InternalBattery".
    private struct MacOSBatteryStatus {
        let percent: Int
        let stateText: String
        let current: Int
        let max: Int
        let timeRemainingMinutes: Int?
    }

    private enum MacOSBatteryReader {
        static func read() -> MacOSBatteryStatus? {
            let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
            guard let array = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
                return nil
            }

            for source in array {
                guard let description = IOPSGetPowerSourceDescription(blob, source)?
                        .takeUnretainedValue() as? [String: Any],
                      let type = description[kIOPSTypeKey as String] as? String,
                      type == kIOPSInternalBatteryType else { continue }

                let current = int(description[kIOPSCurrentCapacityKey as String])
                let maxCapacity = int(description[kIOPSMaxCapacityKey as String])
                let percent = maxCapacity > 0
                    ? min(100, max(0, Int(round(Double(current) / Double(maxCapacity) * 100))))
                    : 0

                let charging = description[kIOPSIsChargingKey as String] as? Bool ?? false
                let state = description[kIOPSPowerSourceStateKey as String] as? String ?? ""
                let stateText: String
                if charging {
                    stateText = NSLocalizedString("Charging", comment: "")
                } else if state == kIOPSACPowerValue {
                    stateText = NSLocalizedString("Not Charging", comment: "")
                } else {
                    stateText = NSLocalizedString("Discharging", comment: "")
                }

                let remaining = charging
                    ? int(description[kIOPSTimeToFullChargeKey as String],
                          fallback: -1)
                    : int(description[kIOPSTimeToEmptyKey as String],
                          fallback: -1)

                return MacOSBatteryStatus(
                    percent: percent,
                    stateText: stateText,
                    current: current,
                    max: maxCapacity,
                    timeRemainingMinutes: remaining >= 0 ? remaining : nil
                )
            }
            return nil
        }

        private static func int(_ value: Any?, fallback: Int = 0) -> Int {
            (value as? NSNumber)?.intValue ?? fallback
        }
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

        /// Detail EC per baterai (BAT0, BAT1). Hanya dipakai untuk baris detail kecil —
        /// BUKAN untuk persen utama. Control threshold tetap memakai jalur EC/SMC ini.
        func ecBatteryDetails() -> [BatteryStatus] {
            let matching = IOServiceMatching("AppleSmartBattery")
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iterator) == kIOReturnSuccess else {
                return []
            }
            defer { IOObjectRelease(iterator) }

            var result: [BatteryStatus] = []
            var service = IOIteratorNext(iterator)
            while service != 0 {
                if let status = readBattery(service) { result.append(status) }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            return result.sorted { $0.name < $1.name }
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
        let ec0Line = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let ec1Line = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let summaryLine = NSMenuItem(title: "…", action: nil, keyEquivalent: "")
        batteryLine.isEnabled = false
        ec0Line.isEnabled = false
        ec1Line.isEnabled = false
        summaryLine.isEnabled = false
        thresholdBatteryItem = batteryLine
        thresholdEC0Item = ec0Line
        thresholdEC1Item = ec1Line
        thresholdSummaryItem = summaryLine
        menu.addItem(batteryLine)
        menu.addItem(ec0Line)
        menu.addItem(ec1Line)
        menu.addItem(summaryLine)
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
        let power = MacOSBatteryReader.read()

        // Persen utama = IOPowerSources, sumber yang sama dengan ikon baterai macOS.
        if let power = power {
            thresholdBatteryItem?.title = String(
                format: NSLocalizedString("Battery - %d%% - %@", comment: ""),
                power.percent, power.stateText
            )
            let remaining = power.timeRemainingMinutes.map { " / \($0) min" } ?? ""
            NSLog("[BatterySync] source IOPowerSources: %d/%d = %d%%%@ | %@",
                  power.current, power.max, power.percent, remaining, power.stateText)
        } else {
            thresholdBatteryItem?.title = NSLocalizedString("Battery - Unknown", comment: "")
        }

        // Detail EC kecil di bawahnya — tidak pernah dipakai sebagai persen utama.
        let details = manager.ecBatteryDetails()
        applyECDetail(thresholdEC0Item, detail: details.indices.contains(0) ? details[0] : nil)
        applyECDetail(thresholdEC1Item, detail: details.indices.contains(1) ? details[1] : nil)

        thresholdSummaryItem?.title = String(
            format: NSLocalizedString("Threshold: Start %d%% → Stop %d%%", comment: ""),
            manager.start, manager.stop
        )
        thresholdEnableItem?.state = manager.isEnabled ? .on : .off
        setCheckmarks(in: thresholdStartItem?.submenu, base: 1000, current: manager.start)
        setCheckmarks(in: thresholdStopItem?.submenu, base: 2000, current: manager.stop)

        // Debug saja — tidak pernah tampil di UI.
        manager.logRawThresholds()
        verifyDisplaySync(macOSPercent: power?.percent)
    }

    private func applyECDetail(_ item: NSMenuItem?, detail: BatteryStatus?) {
        guard let item = item else { return }
        let text: String
        if let detail = detail {
            text = String(
                format: NSLocalizedString("%@ - %d%% - Detail EC", comment: ""),
                detail.name, detail.percent
            )
        } else {
            text = ""
        }
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        item.isHidden = (detail == nil)
    }

    // MARK: - Battery sync monitoring (IOPowerSources)

    private func startBatteryMonitoring() {
        refreshThresholdMenu()

        batteryRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshThresholdMenu()
        }
        if let timer = batteryRefreshTimer {
            RunLoop.main.add(timer, forMode: .common)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePowerSourceChange),
            name: .powerSourceDidChange,
            object: nil
        )

        // Observer bawaan IOKit: langsung dibangkitkan saat charger dicabut/dicolok.
        let source = IOPSNotificationCreateRunLoopSource({ _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .powerSourceDidChange, object: nil)
            }
        }, nil)?.takeRetainedValue()
        powerSourceRunLoopSource = source
        if let source = source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    @objc private func handlePowerSourceChange() {
        refreshThresholdMenu()
        // Bug cabut-colok bablas: tulis ulang threshold EC setelah EC sempat settle.
        pendingForceApply?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.forceApplyThreshold()
        }
        pendingForceApply = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func forceApplyThreshold() {
        do {
            try BatteryThresholdManager.shared.apply()
            NSLog("[BatterySync] Power source changed: threshold re-applied to EC")
        } catch {
            NSLog("[BatterySync] WARNING: forceApplyThreshold failed: %@", error.localizedDescription)
        }
        refreshThresholdMenu()
    }

    private func displayedPercentFromTitle(_ title: String?) -> Int? {
        guard let title = title else { return nil }
        let parts = title.components(separatedBy: " - ")
        guard parts.count >= 2 else { return nil }
        return Int(parts[1].replacingOccurrences(of: "%", with: ""))
    }

    /// Console debug: bandingkan angka sumber macOS dengan angka yang benar-benar tampil.
    private func verifyDisplaySync(macOSPercent: Int?) {
        guard let macOSPercent = macOSPercent else { return }
        let displayPercent = displayedPercentFromTitle(thresholdBatteryItem?.title)
        lastDisplayedPercent = displayPercent
        let match = displayPercent == macOSPercent
        let line = String(
            format: "macOS Percent: %d%% | App Display: %@%% | Match: %@",
            macOSPercent,
            displayPercent.map(String.init) ?? "?",
            match ? "YES" : "NO"
        )
        print("[BatterySync] " + line)
        NSLog("[BatterySync] %@", line)

        if match {
            batteryMismatchSince = nil
            return
        }
        let now = Date()
        if batteryMismatchSince == nil {
            batteryMismatchSince = now
        } else if now.timeIntervalSince(batteryMismatchSince!) >= 10 {
            NSLog("[BatterySync] WARNING: app display tidak sinkron dengan ikon macOS selama >10 detik (%@)", line)
            batteryMismatchSince = now
        }
    }

    deinit {
        batteryRefreshTimer?.invalidate()
        pendingForceApply?.cancel()
        NotificationCenter.default.removeObserver(self)
        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
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

    // MARK: - Sparkle auto-update
    //
    // Kode lama yang menanyakan api.github.com dan membuka browser sudah dihapus total.
    // Sparkle membaca SUFeedURL / SUPublicEDKey dari Info.plist dan menangani
    // jaringan yang mati tanpa crash (alert error standar Sparkle).
    @MainActor
    private func setupUpdateMenu() {
        let checkItem = NSMenuItem(
            title: NSLocalizedString("Check for Updates...", comment: ""),
            action: #selector(checkForUpdatesPressed(_:)),
            keyEquivalent: ""
        )
        checkItem.target = self
        statusBarMenu.insertItem(checkItem, at: max(0, statusBarMenu.items.count - 1))

        let automaticItem = NSMenuItem(
            title: NSLocalizedString("Automatically Check for Updates", comment: ""),
            action: #selector(toggleAutomaticChecks(_:)),
            keyEquivalent: ""
        )
        automaticItem.target = self
        automaticItem.state = updaterController.updater.automaticallyChecksForUpdates ? .on : .off
        statusBarMenu.insertItem(automaticItem, at: max(0, statusBarMenu.items.count - 1))
    }

    @objc @MainActor
    private func checkForUpdatesPressed(_ sender: Any?) {
        updaterController.checkForUpdates(nil)
    }

    @objc @MainActor
    private func toggleAutomaticChecks(_ sender: NSMenuItem) {
        let enabled = !updaterController.updater.automaticallyChecksForUpdates
        updaterController.updater.automaticallyChecksForUpdates = enabled
        sender.state = enabled ? .on : .off
    }

    @IBAction func quitPressed(_ sender: Any) {
        NSApp.terminate(self)
    }
    
}

