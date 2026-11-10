import XCTest
import XLaser

final class LaserDescriptorTests: XCTestCase {
    func testAlternateTypeNamesUseTheSameCanonicalType() {
        XCTAssertEqual(LaserDescriptor.Input(name: "a", type: "long").canonicalType, "int")
        XCTAssertEqual(LaserDescriptor.Input(name: "b", type: "point2D").canonicalType, "vec2")
        XCTAssertEqual(LaserDescriptor.Input(name: "c", type: "color").canonicalType, "color")
    }

    func testHeaderRetainsInputDefaults() throws {
        let source = #"""
        /*{"NAME":"Example","INPUTS":[
          {"NAME":"enabled","TYPE":"bool","DEFAULT":true},
          {"NAME":"color","TYPE":"color","DEFAULT":[1,0,0,1]},
          {"NAME":"speed","TYPE":"float","DEFAULT":1,"MIN":0,"MAX":10}
        ]}*/
        """#
        let descriptor = try LaserJavaScriptDescriptor.parse(source)
        XCTAssertEqual(descriptor.name, "Example")
        XCTAssertEqual(descriptor.inputs[0].defaultValue, .bool(true))
        XCTAssertEqual(descriptor.inputs[1].defaultValue, .array([.number(1), .number(0), .number(0), .number(1)]))
        XCTAssertEqual(descriptor.inputs[2], .init(name: "speed", type: "float", defaultValue: .number(1), minimum: 0, maximum: 10))
    }

    func testInvalidHeaderIsReported() {
        XCTAssertThrowsError(try LaserJavaScriptDescriptor.parse("/*{\"INPUTS\":[{}]}*/"))
    }
}
