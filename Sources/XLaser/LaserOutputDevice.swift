public struct LaserPoint: Equatable, Sendable {
    public let xy: SIMD2<Float>
    public let rgb: SIMD3<Float>
    public let mode: LaserPointMode
    public var isBlanked: Bool { mode == .blank }

    public init(xy: SIMD2<Float>, rgb: SIMD3<Float>, mode: LaserPointMode = .normal) throws {
        guard xy.x.isFinite, xy.y.isFinite,
              (-1...1).contains(xy.x), (-1...1).contains(xy.y),
              rgb.x.isFinite, rgb.y.isFinite, rgb.z.isFinite,
              (0...1).contains(rgb.x), (0...1).contains(rgb.y), (0...1).contains(rgb.z)
        else { throw LaserOutputError.invalidPoint }
        self.xy = xy; self.rgb = rgb; self.mode = mode
    }

    public init(xy: SIMD2<Float>, rgb: SIMD3<Float>, isBlanked: Bool) throws {
        try self.init(xy: xy, rgb: rgb, mode: isBlanked ? .blank : .normal)
    }

    public func dwelling() -> LaserPoint { try! LaserPoint(xy: xy, rgb: rgb, mode: .dwell) }
    public func blanked() -> LaserPoint { try! LaserPoint(xy: xy, rgb: .zero, mode: .blank) }
}

public enum LaserOutputError: Error, Equatable, Sendable {
    case invalidPoint
    case unsupportedPointRate
    case notRunning
    case alreadyRunning
    case disconnected
}

public struct LaserOutputCapabilities: Equatable, Sendable {
    public let maximumPointRate: UInt32

    public init(maximumPointRate: UInt32) {
        precondition(maximumPointRate > 0)
        self.maximumPointRate = maximumPointRate
    }
}

public enum LaserOutputState: Equatable, Sendable {
    case ready
    case running(pointRate: UInt32)
    case failed(String)
    case disconnected
}

public protocol LaserOutputDevice: Sendable {
    var id: String { get }
    var name: String { get }
    func connect() async throws -> any LaserOutputSession
}

public protocol LaserOutputSession: AnyObject, Sendable {
    var capabilities: LaserOutputCapabilities { get }
    var states: AsyncStream<LaserOutputState> { get }
    func start(pointRate: UInt32) async throws
    func write(_ points: [LaserPoint]) async throws
    func stop() async throws
    func disconnect() async throws
}
