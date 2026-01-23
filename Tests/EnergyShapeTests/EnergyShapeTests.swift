//
//  EnergyShapeTests.swift
//  EnergyShape
//
//  Created by Sun on 2026/1/21.
//

import XCTest
import Metal
@testable import EnergyShape

final class EnergyShapeTests: XCTestCase {
    
    // MARK: - ShaderSource 测试
    
    func testShaderSourceNotEmpty() throws {
        // 验证 shader 源码字符串不为空
        XCTAssertFalse(ShaderSource.source.isEmpty, "Shader 源码字符串不应为空")
        XCTAssertGreaterThan(ShaderSource.source.count, 10000, "Shader 源码应该包含大量代码")
    }
    
    func testShaderSourceContainsRequiredFunctions() throws {
        // 验证 shader 源码包含所有必需的着色器函数
        let source = ShaderSource.source
        
        // 顶点着色器
        XCTAssertTrue(source.contains("vertex VertexOut vertexFullscreen"), "应包含全屏顶点着色器")
        
        // 片段着色器
        XCTAssertTrue(source.contains("fragment float4 fragmentEnergy"), "应包含能量场片段着色器")
        XCTAssertTrue(source.contains("fragment float4 fragmentEnergyAnalytic"), "应包含解析 SDF 片段着色器")
        XCTAssertTrue(source.contains("fragment float4 fragmentEnergyNoSDF"), "应包含无 SDF 片段着色器")
        
        // Bloom 着色器
        XCTAssertTrue(source.contains("fragment float4 fragmentBloomThreshold"), "应包含 Bloom 阈值着色器")
        XCTAssertTrue(source.contains("fragment float4 fragmentBloomBlur"), "应包含 Bloom 模糊着色器")
        XCTAssertTrue(source.contains("fragment float4 fragmentBloomComposite"), "应包含 Bloom 合成着色器")
        
        // JFA 计算着色器
        XCTAssertTrue(source.contains("kernel void jfaSeedInit"), "应包含 JFA 种子初始化内核")
        XCTAssertTrue(source.contains("kernel void jfaFlood"), "应包含 JFA 洪泛内核")
        XCTAssertTrue(source.contains("kernel void jfaToSDF"), "应包含 JFA 转 SDF 内核")
    }
    
    func testShaderSourceContainsRequiredStructs() throws {
        // 验证 shader 源码包含所有必需的数据结构
        let source = ShaderSource.source
        
        XCTAssertTrue(source.contains("struct VertexOut"), "应包含 VertexOut 结构")
        XCTAssertTrue(source.contains("struct EnergyUniforms"), "应包含 EnergyUniforms 结构")
        XCTAssertTrue(source.contains("struct AnalyticShapeParams"), "应包含 AnalyticShapeParams 结构")
        XCTAssertTrue(source.contains("struct BloomUniforms"), "应包含 BloomUniforms 结构")
    }
    
    func testShaderSourceUsesGlowFalloff() throws {
        // 验证 shader 已使用新的命名
        let source = ShaderSource.source
        
        // 验证新命名在 EnergyUniforms 中存在
        XCTAssertTrue(source.contains("float glowFalloff;"), "EnergyUniforms 应包含 glowFalloff 成员")
        XCTAssertTrue(source.contains("float noiseScale;"), "EnergyUniforms 应包含 noiseScale 成员")
        XCTAssertTrue(source.contains("float borderBandWidth;"), "EnergyUniforms 应包含 borderBandWidth 成员")
        XCTAssertTrue(source.contains("float innerGlowRadius;"), "EnergyUniforms 应包含 innerGlowRadius 成员")
        XCTAssertTrue(source.contains("float outerGlowRadius;"), "EnergyUniforms 应包含 outerGlowRadius 成员")
        
        // 验证旧命名已从 EnergyUniforms 移除（通过检查不存在这些成员声明）
        XCTAssertFalse(source.contains("float borderWidth;"), "EnergyUniforms 不应包含 borderWidth（已重命名为 glowFalloff）")
        XCTAssertFalse(source.contains("float borderThickness;"), "EnergyUniforms 不应包含 borderThickness（已重命名为 borderBandWidth）")
        XCTAssertFalse(source.contains("float innerGlowRange;"), "EnergyUniforms 不应包含 innerGlowRange（已重命名为 innerGlowRadius）")
        XCTAssertFalse(source.contains("float outerGlowRange;"), "EnergyUniforms 不应包含 outerGlowRange（已重命名为 outerGlowRadius）")
    }
    
    func testShaderLibraryCompilation() throws {
        // 测试 shader 能否成功编译（需要 Metal 设备）
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("无法获取 Metal 设备，跳过编译测试")
        }
        
        // 尝试从源码编译 Metal Library
        XCTAssertNoThrow(try ShaderSource.makeLibrary(device: device), "Shader 源码应能成功编译")
    }
    
    func testShaderLibraryContainsFunctions() throws {
        // 测试编译后的 library 包含所需函数
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("无法获取 Metal 设备，跳过函数测试")
        }
        
        let library = try ShaderSource.makeLibrary(device: device)
        
        // 验证关键函数存在
        XCTAssertNotNil(library.makeFunction(name: "vertexFullscreen"), "应能获取 vertexFullscreen 函数")
        XCTAssertNotNil(library.makeFunction(name: "fragmentEnergy"), "应能获取 fragmentEnergy 函数")
        XCTAssertNotNil(library.makeFunction(name: "fragmentEnergyAnalytic"), "应能获取 fragmentEnergyAnalytic 函数")
        XCTAssertNotNil(library.makeFunction(name: "fragmentEnergyNoSDF"), "应能获取 fragmentEnergyNoSDF 函数")
        XCTAssertNotNil(library.makeFunction(name: "fragmentBloomThreshold"), "应能获取 fragmentBloomThreshold 函数")
        XCTAssertNotNil(library.makeFunction(name: "fragmentBloomBlur"), "应能获取 fragmentBloomBlur 函数")
        XCTAssertNotNil(library.makeFunction(name: "fragmentBloomComposite"), "应能获取 fragmentBloomComposite 函数")
        XCTAssertNotNil(library.makeFunction(name: "jfaSeedInit"), "应能获取 jfaSeedInit 函数")
        XCTAssertNotNil(library.makeFunction(name: "jfaFlood"), "应能获取 jfaFlood 函数")
        XCTAssertNotNil(library.makeFunction(name: "jfaToSDF"), "应能获取 jfaToSDF 函数")
    }
    
    // MARK: - Config 测试
    
    func testConfigValidation() throws {
        var config = EnergyConfig()
        config.speed = -1.0
        config.noiseStrength = 5.0
        config.glowFalloff = 0.0  // 使用新命名
        config.validate()

        XCTAssertEqual(config.speed, 0.1)
        XCTAssertEqual(config.noiseStrength, 1.0)
        XCTAssertEqual(config.glowFalloff, 0.005)  // 验证最小值限制
    }
    
    func testConfigValidationMaxValues() throws {
        var config = EnergyConfig()
        config.speed = 100.0
        config.glowFalloff = 1.0  // 超过最大值
        config.innerGlowIntensity = 2.0
        config.validate()
        
        XCTAssertEqual(config.speed, 3.0, "speed 应被限制到最大值 3.0")
        XCTAssertEqual(config.glowFalloff, 0.1, "glowFalloff 应被限制到最大值 0.1")
        XCTAssertEqual(config.innerGlowIntensity, 1.0, "innerGlowIntensity 应被限制到最大值 1.0")
    }

    func testDefaultConfig() throws {
        let config = EnergyConfig.default
        XCTAssertEqual(config.speed, 1.0)
        XCTAssertEqual(config.bloomEnabled, true)
        XCTAssertEqual(config.glowFalloff, 0.008, "默认 glowFalloff 应为 0.008")
    }
    
    func testConfigGlowFalloffRename() throws {
        // 验证 glowFalloff 属性存在且可访问
        var config = EnergyConfig()
        config.glowFalloff = 0.05
        XCTAssertEqual(config.glowFalloff, 0.05)
    }

    func testColorStop() throws {
        let stop = ColorStop(position: 0.5, color: .red)
        let rgba = stop.rgba
        XCTAssertEqual(rgba.r, 1.0, accuracy: 0.01)
        XCTAssertEqual(rgba.g, 0.0, accuracy: 0.01)
        XCTAssertEqual(rgba.b, 0.0, accuracy: 0.01)
    }
    
    func testColorStopWithCustomColor() throws {
        let customColor = UIColor(red: 0.5, green: 0.25, blue: 0.75, alpha: 0.8)
        let stop = ColorStop(position: 0.3, color: customColor)
        
        XCTAssertEqual(stop.position, 0.3, accuracy: 0.001)
        XCTAssertEqual(stop.rgba.r, 0.5, accuracy: 0.01)
        XCTAssertEqual(stop.rgba.g, 0.25, accuracy: 0.01)
        XCTAssertEqual(stop.rgba.b, 0.75, accuracy: 0.01)
        XCTAssertEqual(stop.rgba.a, 0.8, accuracy: 0.01)
    }
    
    // MARK: - IDW 参数测试
    
    func testIDWParametersValidation() throws {
        var config = EnergyConfig()
        config.diffusionBias = 0.0  // 低于最小值
        config.diffusionPower = 10.0  // 高于最大值
        config.colorPointCount = 20  // 高于最大值
        config.validate()
        
        XCTAssertEqual(config.diffusionBias, 0.001, "diffusionBias 应被限制到最小值 0.001")
        XCTAssertEqual(config.diffusionPower, 4.0, "diffusionPower 应被限制到最大值 4.0")
        XCTAssertEqual(config.colorPointCount, 8, "colorPointCount 应被限制到最大值 8")
    }
    
    // MARK: - 边框参数测试
    
    func testBorderParametersValidation() throws {
        var config = EnergyConfig()
        config.borderBandWidth = -0.1
        config.borderSoftness = 2.0
        config.validate()
        
        XCTAssertEqual(config.borderBandWidth, 0.0, "borderBandWidth 应被限制到最小值 0.0")
        XCTAssertEqual(config.borderSoftness, 1.0, "borderSoftness 应被限制到最大值 1.0")
    }
    
    // MARK: - Bloom 参数测试
    
    func testBloomParametersValidation() throws {
        var config = EnergyConfig()
        config.bloomIntensity = -0.5
        config.bloomThreshold = 1.5
        config.bloomBlurRadius = 6  // 不在允许列表中
        config.validate()
        
        XCTAssertEqual(config.bloomIntensity, 0.0, "bloomIntensity 应被限制到最小值 0.0")
        XCTAssertEqual(config.bloomThreshold, 1.0, "bloomThreshold 应被限制到最大值 1.0")
        XCTAssertTrue([3, 5, 7, 9].contains(config.bloomBlurRadius), "bloomBlurRadius 应被调整到最近的允许值")
    }
    
    // MARK: - 内外发光半径测试
    
    func testGlowRadiusParametersValidation() throws {
        var config = EnergyConfig()
        config.innerGlowRadius = -0.1  // 低于最小值
        config.outerGlowRadius = 1.0   // 高于最大值
        config.validate()
        
        XCTAssertEqual(config.innerGlowRadius, 0.01, "innerGlowRadius 应被限制到最小值 0.01")
        XCTAssertEqual(config.outerGlowRadius, 0.1, "outerGlowRadius 应被限制到最大值 0.1")
    }
    
    func testGlowIntensityParametersValidation() throws {
        var config = EnergyConfig()
        config.innerGlowIntensity = -0.5
        config.outerGlowIntensity = 2.0
        config.validate()
        
        XCTAssertEqual(config.innerGlowIntensity, 0.0, "innerGlowIntensity 应被限制到最小值 0.0")
        XCTAssertEqual(config.outerGlowIntensity, 1.0, "outerGlowIntensity 应被限制到最大值 1.0")
    }
    
    // MARK: - noiseScale 参数测试
    
    func testNoiseScaleValidation() throws {
        var config = EnergyConfig()
        config.noiseScale = 0.1  // 低于最小值 0.5
        config.validate()
        
        XCTAssertEqual(config.noiseScale, 0.5, "noiseScale 应被限制到最小值 0.5")
        
        config.noiseScale = 10.0  // 高于最大值 5.0
        config.validate()
        
        XCTAssertEqual(config.noiseScale, 5.0, "noiseScale 应被限制到最大值 5.0")
    }
    
    func testNoiseOctavesValidation() throws {
        var config = EnergyConfig()
        config.noiseOctaves = 1  // 低于最小值 2
        config.validate()
        
        XCTAssertEqual(config.noiseOctaves, 2, "noiseOctaves 应被限制到最小值 2")
        
        config.noiseOctaves = 8  // 高于最大值 4
        config.validate()
        
        XCTAssertEqual(config.noiseOctaves, 4, "noiseOctaves 应被限制到最大值 4")
    }
    
    // MARK: - bloomScale 参数测试
    
    func testBloomScaleValidation() throws {
        var config = EnergyConfig()
        config.bloomScale = 0.1  // 低于最小值 0.25
        config.validate()
        
        XCTAssertEqual(config.bloomScale, 0.25, "bloomScale 应被限制到最小值 0.25")
        
        config.bloomScale = 0.8  // 高于最大值 0.5
        config.validate()
        
        XCTAssertEqual(config.bloomScale, 0.5, "bloomScale 应被限制到最大值 0.5")
    }
    
    // MARK: - 完整配置测试
    
    func testAllRenamedParametersExist() throws {
        // 验证所有重命名后的参数都能正常访问和赋值
        var config = EnergyConfig()
        
        // 设置所有重命名后的参数
        config.glowFalloff = 0.02
        config.noiseScale = 2.5
        config.borderBandWidth = 0.03
        config.innerGlowRadius = 0.1
        config.outerGlowRadius = 0.15
        config.bloomScale = 0.35
        
        // 验证值正确存储
        XCTAssertEqual(config.glowFalloff, 0.02, accuracy: 0.001)
        XCTAssertEqual(config.noiseScale, 2.5, accuracy: 0.001)
        XCTAssertEqual(config.borderBandWidth, 0.03, accuracy: 0.001)
        XCTAssertEqual(config.innerGlowRadius, 0.1, accuracy: 0.001)
        XCTAssertEqual(config.outerGlowRadius, 0.15, accuracy: 0.001)
        XCTAssertEqual(config.bloomScale, 0.35, accuracy: 0.001)
    }
    
    // MARK: - SDFQuality 测试
    
    func testSDFQualityEnum() throws {
        let config = EnergyConfig()
        
        // 验证 SDFQuality 枚举值
        XCTAssertNotNil(SDFQuality.low)
        XCTAssertNotNil(SDFQuality.medium)
        XCTAssertNotNil(SDFQuality.high)
        
        // 验证分辨率缩放因子
        XCTAssertEqual(SDFQuality.low.resolutionScale, 0.25, accuracy: 0.001)
        XCTAssertEqual(SDFQuality.medium.resolutionScale, 0.5, accuracy: 0.001)
        XCTAssertEqual(SDFQuality.high.resolutionScale, 1.0, accuracy: 0.001)
        
        // 验证默认值
        XCTAssertEqual(config.sdfQuality, .medium)
    }
    
    // MARK: - 动画状态机参数测试
    
    func testAnimationStateParameters() throws {
        var config = EnergyConfig()
        
        // 设置动画参数
        config.startupDuration = 2.0
        config.settleDuration = 1.5
        config.autoSettle = true
        config.autoSettleDelay = 15.0
        config.settleToIdle = true
        
        // 验证值正确存储
        XCTAssertEqual(config.startupDuration, 2.0, accuracy: 0.001)
        XCTAssertEqual(config.settleDuration, 1.5, accuracy: 0.001)
        XCTAssertTrue(config.autoSettle)
        XCTAssertEqual(config.autoSettleDelay, 15.0, accuracy: 0.001)
        XCTAssertTrue(config.settleToIdle)
    }
    
    // MARK: - ColorStop 数组测试
    
    func testColorStopsArray() throws {
        var config = EnergyConfig()
        
        let stops: [ColorStop] = [
            ColorStop(position: 0.0, color: .red),
            ColorStop(position: 0.5, color: .green),
            ColorStop(position: 1.0, color: .blue),
        ]
        
        config.colorStops = stops
        
        XCTAssertEqual(config.colorStops.count, 3)
        XCTAssertEqual(config.colorStops[0].position, 0.0, accuracy: 0.001)
        XCTAssertEqual(config.colorStops[1].position, 0.5, accuracy: 0.001)
        XCTAssertEqual(config.colorStops[2].position, 1.0, accuracy: 0.001)
    }
    
    // MARK: - Shader 包含 IDW 函数测试
    
    func testShaderContainsIDWFunctions() throws {
        let source = ShaderSource.source
        
        // 验证 IDW 相关函数/代码存在
        XCTAssertTrue(source.contains("diffusionBias"), "应包含 diffusionBias 参数")
        XCTAssertTrue(source.contains("diffusionPower"), "应包含 diffusionPower 参数")
    }
    
    // MARK: - Shader 包含噪声函数测试
    
    func testShaderContainsNoiseFunctions() throws {
        let source = ShaderSource.source
        
        // 验证噪声函数存在
        XCTAssertTrue(source.contains("fbm"), "应包含 FBM (Fractional Brownian Motion) 函数")
        XCTAssertTrue(source.contains("noise"), "应包含噪声函数")
    }
}
