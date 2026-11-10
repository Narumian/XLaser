public struct LaserShapeID: Hashable, Sendable, ExpressibleByIntegerLiteral {
    public var rawValue: UInt32
    public init(_ rawValue: UInt32) { self.rawValue = rawValue }
    public init(integerLiteral value: UInt32) { rawValue = value }
}
