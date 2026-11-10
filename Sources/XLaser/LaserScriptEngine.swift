public struct LaserScriptReadContext: Sendable, Equatable {
    public var time: Double
    public var sampleRate: Double
    public var frameLength: Int

    public init(time: Double, sampleRate: Double, frameLength: Int) {
        self.time = time
        self.sampleRate = sampleRate
        self.frameLength = frameLength
    }
}

public protocol LaserScriptEngine: AnyObject {
    func read(context: LaserScriptReadContext, inputs: [Laser3DBuffer], output: inout Laser3DBuffer) throws
}
