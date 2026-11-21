//
//  BluetoothManager.swift
//  ThinkpadAssistant
//
//  Created by Matt on 24.05.20.
//  Dikelola oleh Syuhadak27. https://github.com/Syuhadak27/ThinkpadAssistent
//
import Foundation
import IOBluetooth

final class BluetoothManager {
    
    static func toggleBluetooth() {
        isEnabled() ? disableBluetooth() : enableBluetooth()
    }
    
    static func isEnabled() -> Bool {
        return IOBluetoothPreferenceGetControllerPowerState() == 1
    }
    
    static func disableBluetooth() {
        IOBluetoothPreferenceSetControllerPowerState(0)
    }
    
    static func enableBluetooth() {
        IOBluetoothPreferenceSetControllerPowerState(1)
    }
}
