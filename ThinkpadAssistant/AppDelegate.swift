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
    private weak var thresholdStatusItem: NSMenuItem?
    private weak var thresholdStartItem: NSMenuItem?
    private weak var thresholdStopItem: NSMenuItem?

    @IBOutlet weak var statusBarMenu: NSMenu!
    
    @IBOutlet weak var monitorCapslocksMenuItem: NSMenuItem!
    @IBOutlet weak var launchAtLoginMenuItem: NSMenuItem!
    
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
    private enum BatteryThresholdError: LocalizedError {
        case serviceNotFound
        case setFailed(IOReturn)
        case readFailed
        case noBatteryData

        var errorDescription: String? {
            switch self {
            case .serviceNotFound:
                return NSLocalizedString("ThinkVPC (YogaSMC) service not found. Make sure YogaSMC 1.5.3 is loaded.", comment: "")
            case .setFailed(let kr):
                return String(format: NSLocalizedString("Could not write threshold (0x%08X). Administrator rights may be required.", comment: ""), kr)
            case .readFailed:
                return NSLocalizedString("Could not read BAT_PRIMARY from ThinkVPC.", comment: "")
            case .noBatteryData:
                return NSLocalizedString("BAT_PRIMARY is not available yet (YogaSMC has not published battery data).", comment: "")
            }
        }
    }

    private struct BatteryThresholdState {
        let start: Int?   // BCTG (perkiraan — lihat catatan di SUMMARY.md)
        let stop: Int?    // BCSG (perkiraan — lihat catatan di SUMMARY.md)
    }

    private final class BatteryThresholdManager {
        static let shared = BatteryThresholdManager()
        private init() {}

        private let serviceName = "ThinkVPC"
        private let batteryProperty = "Battery"
        private let batteryIndex = 1   // BAT_PRIMARY

        private func copyService() throws -> io_registry_entry_t {
            let matching = IOServiceMatching(serviceName)
            let service = IOServiceGetMatchingService(kIOMasterPortDefault, matching)
            guard service != 0 else { throw BatteryThresholdError.serviceNotFound }
            return service
        }

        func set(start: Int?, stop: Int?) throws {
            var props: [String: Any] = [batteryProperty: batteryIndex]
            if let start = start { props["setCMstart"] = min(100, max(0, start)) }
            if let stop = stop { props["setCMstop"] = min(100, max(0, stop)) }
            guard props.count > 1 else { return }

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

        func read() throws -> BatteryThresholdState {
            let service = try copyService()
            defer { IOObjectRelease(service) }

            let raw = IORegistryEntryCreateCFProperty(service, "BAT_PRIMARY" as CFString, kCFAllocatorDefault, 0)
            guard let dict = raw?.takeRetainedValue() as? NSDictionary, dict.count > 0 else {
                throw BatteryThresholdError.noBatteryData
            }

            var numbers: [String: Int] = [:]
            for (key, value) in dict {
                if let k = key as? String, let n = value as? NSNumber {
                    numbers[k] = n.intValue
                }
            }
            guard !numbers.isEmpty else { throw BatteryThresholdError.readFailed }
            return BatteryThresholdState(start: numbers["BCTG"], stop: numbers["BCSG"])
        }
    }

    private func setupBatteryThresholdMenu() {
        let item = NSMenuItem(title: NSLocalizedString("Battery Threshold", comment: ""), action: nil, keyEquivalent: "")
        let menu = NSMenu()

        let status = NSMenuItem(title: "…", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        thresholdStatusItem = status
        menu.addItem(NSMenuItem.separator())

        let startItem = NSMenuItem(title: NSLocalizedString("Charge start (%)", comment: ""), action: nil, keyEquivalent: "")
        let startMenu = NSMenu()
        for value in stride(from: 0, through: 100, by: 5) {
            let choice = NSMenuItem(title: "\(value)%", action: #selector(setStart(_:)), keyEquivalent: "")
            choice.target = self
            choice.tag = 1000 + value
            startMenu.addItem(choice)
        }
        startItem.submenu = startMenu
        menu.addItem(startItem)
        thresholdStartItem = startItem

        let stopItem = NSMenuItem(title: NSLocalizedString("Charge stop (%)", comment: ""), action: nil, keyEquivalent: "")
        let stopMenu = NSMenu()
        for value in stride(from: 0, through: 100, by: 5) {
            let choice = NSMenuItem(title: "\(value)%", action: #selector(setStop(_:)), keyEquivalent: "")
            choice.target = self
            choice.tag = 2000 + value
            stopMenu.addItem(choice)
        }
        stopItem.submenu = stopMenu
        menu.addItem(stopItem)
        thresholdStopItem = stopItem

        menu.addItem(NSMenuItem.separator())
        let refresh = NSMenuItem(title: NSLocalizedString("Refresh Threshold", comment: ""), action: #selector(refreshThresholdMenu), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        item.submenu = menu
        // Sisipkan sebelum separator + Quit (dua item terakhir di storyboard).
        statusBarMenu.insertItem(item, at: max(0, statusBarMenu.items.count - 2))
        refreshThresholdMenu()
    }

    private func setCheckmarks(in menu: NSMenu?, base: Int, current: Int?) {
        guard let menu = menu else { return }
        for choice in menu.items {
            choice.state = (current != nil && choice.tag - base == current!) ? .on : .off
        }
    }

    @objc private func refreshThresholdMenu() {
        let state: BatteryThresholdState
        do {
            state = try BatteryThresholdManager.shared.read()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            thresholdStatusItem?.title = message
            thresholdStartItem?.title = NSLocalizedString("Charge start (%)", comment: "")
            thresholdStopItem?.title = NSLocalizedString("Charge stop (%)", comment: "")
            return
        }

        let startText = state.start.map { "\($0)%" } ?? "?"
        let stopText = state.stop.map { "\($0)%" } ?? "?"
        // Tampilkan nama key mentah: pemetaan BCTG/BCSG ke start/stop adalah
        // inferensi (lihat SUMMARY.md 9.4), jadi jangan disembunyikan.
        thresholdStatusItem?.title = String(format: NSLocalizedString("BCTG %@ · BCSG %@", comment: ""), startText, stopText)
        thresholdStartItem?.title = String(format: NSLocalizedString("Charge start (%) — BCTG %@", comment: ""), startText)
        thresholdStopItem?.title = String(format: NSLocalizedString("Charge stop (%) — BCSG %@", comment: ""), stopText)
        setCheckmarks(in: thresholdStartItem?.submenu, base: 1000, current: state.start)
        setCheckmarks(in: thresholdStopItem?.submenu, base: 2000, current: state.stop)
    }

    @objc private func setStart(_ sender: NSMenuItem) {
        applyThreshold(start: sender.tag - 1000, stop: nil)
    }

    @objc private func setStop(_ sender: NSMenuItem) {
        applyThreshold(start: nil, stop: sender.tag - 2000)
    }

    private func applyThreshold(start: Int?, stop: Int?) {
        do {
            try BatteryThresholdManager.shared.set(start: start, stop: stop)
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

    @IBAction func quitPressed(_ sender: Any) {
        NSApp.terminate(self)
    }
    
}

