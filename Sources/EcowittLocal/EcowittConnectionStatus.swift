//
//  EcowittConnectionStatus.swift
//  EcowittLocal
//

import Foundation

/// Connection state for the Ecowitt gateway client
public enum EcowittConnectionStatus: String, Sendable {
    case connected
    case connecting
    case disconnected
}
