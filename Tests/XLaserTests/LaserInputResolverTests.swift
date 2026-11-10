import XCTest
import XLaser

final class LaserInputResolverTests: XCTestCase {
    func testDefaultsAliasesAndOverrides() throws {
        let descriptor = LaserDescriptor(inputs: [
            .init(name: "count", type: "long", defaultValue: .number(3)),
            .init(name: "center", type: "point2D", defaultValue: .array([.number(1), .number(2)])),
            .init(name: "color", type: "color", defaultValue: .array([.number(1), .number(0), .number(0.5), .number(1)])),
            .init(name: "missing", type: "float"),
        ])
        let resolver = try LaserInputResolver(descriptor: descriptor)
        let inputs = try resolver.resolve(["count": .int(5), "extra": .bool(true)])
        XCTAssertEqual(inputs["count"], .integer(5))
        XCTAssertEqual(inputs["center"], .vec2(SIMD2(1, 2)))
        XCTAssertEqual(inputs["color"], .color(SIMD4(1, 0, 0.5, 1)))
        XCTAssertEqual(inputs["extra"], .bool(true))
        XCTAssertNil(inputs["missing"])
    }

    func testOtherDefaults() throws {
        let descriptor = LaserDescriptor(inputs: [
            .init(name: "float", type: "float", defaultValue: .number(0.5)),
            .init(name: "bool", type: "bool", defaultValue: .bool(true)),
            .init(name: "text", type: "string", defaultValue: .string("laser")),
            .init(name: "choice", type: "enum", defaultValue: .number(2)),
            .init(name: "event", type: "event", defaultValue: .bool(false)),
            .init(name: "values", type: "array", defaultValue: .array([.number(1), .bool(true)])),
            .init(name: "matrix", type: "matrix", defaultValue: .object([
                "rows": .number(1), "columns": .number(2), "values": .array([.number(3), .number(4)])
            ])),
        ])
        let inputs = try LaserInputResolver(descriptor: descriptor).resolve([:])
        XCTAssertEqual(inputs["float"], .float(0.5))
        XCTAssertEqual(inputs["bool"], .bool(true))
        XCTAssertEqual(inputs["text"], .string("laser"))
        XCTAssertEqual(inputs["choice"], .enumeration(2))
        XCTAssertEqual(inputs["event"], .event(false))
        XCTAssertEqual(inputs["values"], .array([.number(1), .bool(true)]))
        XCTAssertEqual(inputs["matrix"], .matrix(try LaserInputMatrix(rows: 1, columns: 2, values: [3, 4])))
    }

    func testRejectsDuplicateDeclarationsAndInvalidDefaults() {
        let duplicate = LaserDescriptor(inputs: [.init(name: "a", type: "int"), .init(name: "a", type: "float")])
        XCTAssertThrowsError(try LaserInputResolver(descriptor: duplicate)) { error in
            XCTAssertEqual(error as? LaserInputResolutionError, .duplicateName("a"))
        }
        let invalid = LaserDescriptor(inputs: [.init(name: "a", type: "vec3", defaultValue: .array([.number(1)]))])
        XCTAssertThrowsError(try LaserInputResolver(descriptor: invalid)) { error in
            XCTAssertEqual(error as? LaserInputResolutionError, .invalidDefault(name: "a", type: "vec3"))
        }
    }

    func testRejectsMismatchedDeclaredInput() throws {
        let resolver = try LaserInputResolver(descriptor: .init(inputs: [.init(name: "x", type: "point2D")]))
        XCTAssertThrowsError(try resolver.resolve(["x": .float(1)])) { error in
            XCTAssertEqual(error as? LaserInputResolutionError, .typeMismatch(name: "x", expected: "vec2"))
        }
    }
}
