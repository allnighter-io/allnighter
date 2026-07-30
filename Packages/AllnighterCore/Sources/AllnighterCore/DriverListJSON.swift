import Foundation

/// `alln drivers` / `alln drivers park|unpark` machine contract.
/// Parked CLIs are listed **last** so capacity/status strips can reuse this order.
public struct DriverListJSON: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var contractVersion: String
    public var drivers: [Entry]

    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public var id: String { driverId }
        public var driverId: String
        public var displayName: String
        /// `parked` | `ready` | `notReady` | `notChecked`
        public var status: String
        public var parked: Bool
        public var version: String?
        public var modelsOn: Int
        public var probeDetail: String?
    }

    public init(
        schemaVersion: Int = 1,
        contractVersion: String,
        drivers: [Entry]
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.drivers = drivers
    }
}
