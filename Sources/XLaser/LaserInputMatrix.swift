public struct LaserInputMatrix: Sendable, Equatable, Encodable {
    public let rows: Int
    public let columns: Int
    public let values: [Double]

    public init(rows: Int, columns: Int, values: [Double]) throws {
        guard rows > 0, columns > 0, rows <= Int.max / columns,
              values.count == rows * columns, values.allSatisfy(\.isFinite) else {
            throw LaserInputMatrixError.invalidDimensions
        }
        self.rows = rows
        self.columns = columns
        self.values = values
    }
}

public enum LaserInputMatrixError: Error, Equatable, Sendable {
    case invalidDimensions
}
