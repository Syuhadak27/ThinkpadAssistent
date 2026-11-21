//
//  AboutViewController.swift
//  ThinkpadAssistant
//
//  Dikelola oleh Syuhadak27.
//  https://github.com/Syuhadak27/ThinkpadAssistent
//

import Foundation
import Cocoa

class AboutViewController: NSViewController {
    
    @IBOutlet weak var versionLabel: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
         if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            self.versionLabel.stringValue = NSLocalizedString("Version", comment: "") + " " + version
        }
        NSApp.activate(ignoringOtherApps: true)
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(appMovedToBackground), name: NSApplication.willResignActiveNotification, object: nil)
        
    }
    
    @objc func appMovedToBackground() {
        self.view.window!.close()
    }

    @IBAction func openGitHub(_ sender: Any) {
        guard let url = URL(string: "https://github.com/Syuhadak27/ThinkpadAssistent") else { return }
        NSWorkspace.shared.open(url)
    }
    
}
