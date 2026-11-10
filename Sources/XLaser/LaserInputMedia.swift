public enum LaserInputMediaError: Error, Equatable, Sendable {
    case invalidImage
    case invalidAudio
    case invalidSpectrum
}

public struct LaserInputImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) throws {
        guard width > 0, height > 0, UInt32(exactly: width) != nil, UInt32(exactly: height) != nil, width <= Int.max / height,
              width * height <= Int.max / 4, rgba.count == width * height * 4 else {
            throw LaserInputMediaError.invalidImage
        }
        self.width = width; self.height = height; self.rgba = rgba
    }
}

public struct LaserInputAudio: Sendable, Equatable {
    public let sampleRate: Double
    public let channels: Int
    public let samples: [Float]

    public init(sampleRate: Double, channels: Int, samples: [Float]) throws {
        guard sampleRate.isFinite, sampleRate > 0, channels > 0, UInt32(exactly: channels) != nil,
              samples.count % channels == 0, samples.allSatisfy(\.isFinite) else {
            throw LaserInputMediaError.invalidAudio
        }
        self.sampleRate = sampleRate; self.channels = channels; self.samples = samples
    }
}

public struct LaserInputSpectrum: Sendable, Equatable {
    public let sampleRate: Double
    public let fftSize: Int
    public let bins: [Float]

    public init(sampleRate: Double, fftSize: Int, bins: [Float]) throws {
        guard sampleRate.isFinite, sampleRate > 0, fftSize > 0, UInt32(exactly: fftSize) != nil, bins.allSatisfy(\.isFinite) else {
            throw LaserInputMediaError.invalidSpectrum
        }
        self.sampleRate = sampleRate; self.fftSize = fftSize; self.bins = bins
    }
}
