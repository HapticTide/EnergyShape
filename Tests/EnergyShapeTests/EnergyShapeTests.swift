//
//  EnergyShapeTests.swift
//  EnergyShape
//
//  Created by Sun on 2026/1/21.
//

import XCTest
@testable import EnergyShape

final class EnergyShapeTests: XCTestCase {
    func testConfigValidation() throws {
        var config = EnergyConfig()
        config.speed = -1.0
        config.noiseStrength = 5.0
        config.validate()

        XCTAssertEqual(config.speed, 0.1)
        XCTAssertEqual(config.noiseStrength, 1.0)
    }

    func testDefaultConfig() throws {
        let config = EnergyConfig.default
        XCTAssertEqual(config.speed, 1.0)
        XCTAssertEqual(config.bloomEnabled, true)
    }

    func testColorStop() throws {
        let stop = ColorStop(position: 0.5, color: .red)
        let rgba = stop.rgba
        XCTAssertEqual(rgba.r, 1.0, accuracy: 0.01)
        XCTAssertEqual(rgba.g, 0.0, accuracy: 0.01)
        XCTAssertEqual(rgba.b, 0.0, accuracy: 0.01)
    }
}
