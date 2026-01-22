//
//  EnergyMetalRenderer.swift
//  EnergyShape
//
//  Created by Sun on 2026/1/21.
//  Metal 渲染核心 - 整合所有渲染 Pass
//

import Metal
import MetalKit
import simd

// MARK: - Renderer Delegate

/// 渲染器代理协议
protocol EnergyMetalRendererDelegate: AnyObject {
    /// 完成一帧渲染
    func rendererDidFinishFrame(_ renderer: EnergyMetalRenderer, cpuTime: Double, gpuTime: Double)
    /// 渲染错误
    func renderer(_ renderer: EnergyMetalRenderer, didFailWithError error: Error)
}

// MARK: - 常量定义

private let maxColorPoints = 8

// MARK: - Uniform 结构（与 Shader 对应）

/// 能量场 Uniform（需要与 Shader 中定义保持一致）
/// 支持 IDW 颜色弥散 + 边框发光参数
struct EnergyUniforms {
    var time: Float
    var speed: Float
    var noiseStrength: Float
    var phaseScale: Float
    var glowIntensity: Float
    var edgeBoost: Float
    var intensity: Float
    var ditherEnabled: Float
    var resolution: SIMD2<Float>
    var texelSize: SIMD2<Float>
    var noiseOctaves: Int32
    var padding: Int32 = 0 // 保持 16 字节对齐

    // 6 个颜色停靠点（RGBA + position）- 用于 LUT 生成
    var color0: SIMD4<Float> = .zero
    var color0Pos: Float = 0
    var color1: SIMD4<Float> = .zero
    var color1Pos: Float = 0
    var color2: SIMD4<Float> = .zero
    var color2Pos: Float = 0
    var color3: SIMD4<Float> = .zero
    var color3Pos: Float = 0
    var color4: SIMD4<Float> = .zero
    var color4Pos: Float = 0
    var color5: SIMD4<Float> = .zero
    var color5Pos: Float = 0

    // 边框发光参数（像素单位）
    var borderWidth: Float = 2.0
    var borderThickness: Float = 0.0
    var borderSoftness: Float = 0.5
    var innerGlowIntensity: Float = 0.3
    var innerGlowRange: Float = 15.0
    var outerGlowIntensity: Float = 0.2
    var outerGlowRange: Float = 8.0
    var colorFlowSpeed: Float = 0.2
    
    // SDF 距离参数
    var sdfMaxDist: Float = 64.0
    var colorOffset: Float = 0.0
    
    // IDW 弥散参数
    var diffusionBias: Float = 0.01
    var diffusionPower: Float = 2.0
    var colorPointCount: Int32 = 0
    var padding2: Int32 = 0
    
    // 颜色点数组（最多 8 个）
    var colorPointPositions: (
        SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>,
        SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>
    ) = (.zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero)
    
    var colorPointColors: (
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
        SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>
    ) = (.zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero)
}

/// 解析形状参数（与 Shader 中的 AnalyticShapeParams 对应）
struct ShaderAnalyticShapeParams {
    var shapeType: Int32 = 0       // 0=圆角矩形, 1=圆形, 2=椭圆, 3=胶囊
    var padding1: Int32 = 0
    var viewSize: SIMD2<Float> = .zero
    var center: SIMD2<Float> = SIMD2<Float>(0.5, 0.5)
    var halfSize: SIMD2<Float> = SIMD2<Float>(0.5, 0.5)
    var cornerRadius: Float = 0.0
    var padding2: Float = 0
    var radius: SIMD2<Float> = SIMD2<Float>(0.5, 0.5)
    var isVertical: Int32 = 0
    var padding3: Int32 = 0
}

/// Bloom Uniform
struct BloomUniforms {
    var threshold: Float
    var intensity: Float
    var texelSize: SIMD2<Float>
    var blurRadius: Int32
    var isHorizontal: Int32
}

// MARK: - EnergyMetalRenderer

/// Metal 渲染器
final class EnergyMetalRenderer: NSObject {
    // MARK: - 属性

    weak var delegate: EnergyMetalRendererDelegate?

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private weak var view: MTKView?

    // Pipeline States
    private var energyPipelineState: MTLRenderPipelineState?
    private var energyNoSDFPipelineState: MTLRenderPipelineState?
    private var energyHDRPipelineState: MTLRenderPipelineState? // HDR 版本（rgba16Float）
    private var energyNoSDFHDRPipelineState: MTLRenderPipelineState? // HDR 版本（无 SDF）
    private var energyAnalyticPipelineState: MTLRenderPipelineState? // 解析 SDF 版本
    private var energyAnalyticHDRPipelineState: MTLRenderPipelineState? // 解析 SDF HDR 版本
    private var bloomThresholdPipelineState: MTLRenderPipelineState?
    private var bloomBlurPipelineState: MTLRenderPipelineState?
    private var bloomCompositePipelineState: MTLRenderPipelineState?

    // 纹理
    private var maskTexture: MTLTexture?
    private var sdfTexture: MTLTexture?
    private var lutTexture: MTLTexture?
    
    // SDF 模式和解析形状参数
    private var sdfMode: SDFMode = .texture
    private var analyticShapeParams: AnalyticShapeParams?

    // Bloom 中间纹理
    private var bloomThresholdTexture: MTLTexture?
    private var bloomBlurHTexture: MTLTexture?
    private var bloomBlurVTexture: MTLTexture?
    private var energyOutputTexture: MTLTexture?

    // 纹理池
    private let texturePool: TexturePool
    
    // MSAA 采样数
    private let sampleCount: Int

    // 配置
    private var config: EnergyConfig = .default
    private var animationParams = AnimationParams()
    private var totalTime: Float = 0
    
    // IDW 颜色点动画状态
    private var colorPoints: [ColorPointState] = []
    private var colorPointsInitialized = false
    /// 上次颜色停靠点的哈希值（用于检测颜色变化）
    private var lastColorStopsHash: Int = 0

    // 性能统计
    private var cpuStartTime: CFTimeInterval = 0
    private var lastGPUTime: Double = 0
    
    /// 上一帧时间（用于计算真实 deltaTime）
    private var lastFrameTime: CFTimeInterval = 0

    // 当前视图尺寸
    private var viewportSize: CGSize = .zero

    // MARK: - 初始化

    init(device: MTLDevice, view: MTKView) throws {
        self.device = device
        self.view = view
        self.sampleCount = view.sampleCount  // 保存 MSAA 采样数
        texturePool = TexturePool(device: device)

        guard let queue = device.makeCommandQueue() else {
            throw EnergyShapeError.deviceCreationFailed
        }
        commandQueue = queue

        super.init()

        try setupPipelines()
        setupDefaultLUT()
    }

    // MARK: - Pipeline 设置

    private func setupPipelines() throws {
        // 1. 尝试从默认库加载（App 直接包含源码时）
        if let library = device.makeDefaultLibrary() {
            try setupPipelinesWithLibrary(library)
            return
        }

        // 2. 尝试从 SwiftPM Bundle.module 加载编译后的 metallib
        #if SWIFT_PACKAGE
            if
                let libraryURL = Bundle.module.url(forResource: "default", withExtension: "metallib"),
                let library = try? device.makeLibrary(URL: libraryURL) {
                try setupPipelinesWithLibrary(library)
                return
            }

            // 3. 从 Bundle.module 加载 .metal 源码并在运行时编译
            if
                let shaderURL = Bundle.module.url(forResource: "Shaders", withExtension: "metal"),
                let shaderSource = try? String(contentsOf: shaderURL, encoding: .utf8) {
                let library = try device.makeLibrary(source: shaderSource, options: nil)
                try setupPipelinesWithLibrary(library)
                return
            }
        #endif

        // 4. 尝试从当前类所在的 Bundle 加载
        let classBundle = Bundle(for: EnergyMetalRenderer.self)
        if
            let libraryURL = classBundle.url(forResource: "default", withExtension: "metallib"),
            let library = try? device.makeLibrary(URL: libraryURL) {
            try setupPipelinesWithLibrary(library)
            return
        }

        throw EnergyShapeError.shaderCompilationFailed("无法加载 Metal Library，请确保 Shaders.metal 文件在正确位置")
    }

    private func setupPipelinesWithLibrary(_ library: MTLLibrary) throws {
        // 获取 shader 函数
        guard let vertexFunction = library.makeFunction(name: "vertexFullscreen") else {
            throw EnergyShapeError.shaderCompilationFailed("找不到 vertexFullscreen")
        }

        // 能量场 Pipeline（有 SDF）- 直接渲染到屏幕，需要 MSAA
        if let fragmentFunction = library.makeFunction(name: "fragmentEnergy") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            descriptor.rasterSampleCount = sampleCount  // MSAA 采样数

            energyPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        }

        // 能量场 Pipeline（无 SDF）- 直接渲染到屏幕，需要 MSAA
        if let fragmentFunction = library.makeFunction(name: "fragmentEnergyNoSDF") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            descriptor.rasterSampleCount = sampleCount  // MSAA 采样数

            energyNoSDFPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        }
        
        // 能量场 Pipeline（解析 SDF）- 直接渲染到屏幕，需要 MSAA
        if let fragmentFunction = library.makeFunction(name: "fragmentEnergyAnalytic") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            descriptor.rasterSampleCount = sampleCount  // MSAA 采样数

            energyAnalyticPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        }
        
        // 能量场 Pipeline HDR 版本（有 SDF，输出到 rgba16Float）
        // Bloom 中间纹理，不需要 MSAA
        if let fragmentFunction = library.makeFunction(name: "fragmentEnergy") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .rgba16Float
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            energyHDRPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        }
        
        // 能量场 Pipeline HDR 版本（无 SDF，输出到 rgba16Float）
        // Bloom 中间纹理，不需要 MSAA
        if let fragmentFunction = library.makeFunction(name: "fragmentEnergyNoSDF") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .rgba16Float
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            energyNoSDFHDRPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        }
        
        // 能量场 Pipeline HDR 版本（解析 SDF）
        // Bloom 中间纹理，不需要 MSAA
        if let fragmentFunction = library.makeFunction(name: "fragmentEnergyAnalytic") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .rgba16Float
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            energyAnalyticHDRPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        }

        // Bloom Threshold Pipeline - 中间纹理，不需要 MSAA
        if let fragmentFunction = library.makeFunction(name: "fragmentBloomThreshold") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .rgba16Float

            bloomThresholdPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        }

        // Bloom Blur Pipeline - 中间纹理，不需要 MSAA
        if let fragmentFunction = library.makeFunction(name: "fragmentBloomBlur") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .rgba16Float

            bloomBlurPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        }

        // Bloom Composite Pipeline - 渲染到屏幕，需要 MSAA
        if let fragmentFunction = library.makeFunction(name: "fragmentBloomComposite") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            descriptor.rasterSampleCount = sampleCount  // MSAA 采样数

            bloomCompositePipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        }
    }

    private func setupDefaultLUT() {
        // 创建默认 LUT（灰度渐变，如果外部未设置颜色）
        let defaultColors: [ColorStop] = [
            ColorStop(position: 0.0, color: UIColor(white: 0.3, alpha: 1.0)),
            ColorStop(position: 0.5, color: UIColor(white: 0.6, alpha: 1.0)),
            ColorStop(position: 1.0, color: UIColor(white: 1.0, alpha: 1.0)),
        ]
        updateColorLUT(defaultColors)
    }

    deinit {
        // 释放所有 Bloom 纹理回池
        releaseBloomTextures()
    }

    // MARK: - 公开方法

    /// 更新配置
    func updateConfig(_ config: EnergyConfig) {
        let oldBloomEnabled = self.config.bloomEnabled
        self.config = config

        // 如果 Bloom 被禁用，释放相关纹理
        if oldBloomEnabled, !config.bloomEnabled {
            releaseBloomTextures()
        }
    }

    /// 释放 Bloom 相关纹理
    private func releaseBloomTextures() {
        if let tex = bloomThresholdTexture {
            texturePool.release(tex)
            bloomThresholdTexture = nil
        }
        if let tex = bloomBlurHTexture {
            texturePool.release(tex)
            bloomBlurHTexture = nil
        }
        if let tex = bloomBlurVTexture {
            texturePool.release(tex)
            bloomBlurVTexture = nil
        }
        if let tex = energyOutputTexture {
            texturePool.release(tex)
            energyOutputTexture = nil
        }
        lastBloomSize = (0, 0)
        lastEnergySize = (0, 0)
    }

    /// 更新动画参数
    func updateAnimationParams(_ params: AnimationParams) {
        animationParams = params
    }

    /// 更新 Mask 纹理（纹理 SDF 模式）
    func updateMaskTextures(mask: MTLTexture?, sdf: MTLTexture?) {
        maskTexture = mask
        sdfTexture = sdf
        sdfMode = .texture
        analyticShapeParams = nil
    }
    
    /// 更新解析形状参数（解析 SDF 模式）
    func updateAnalyticShape(_ params: AnalyticShapeParams) {
        analyticShapeParams = params
        sdfMode = .analytic
        // 解析模式不需要纹理
        sdfTexture = nil
    }
    
    /// 获取当前 SDF 模式
    var currentSDFMode: SDFMode {
        sdfMode
    }

    /// 更新颜色 LUT
    func updateColorLUT(_ colorStops: [ColorStop]) {
        lutTexture = generateLUTTexture(from: colorStops)
    }

    // MARK: - LUT 生成

    /// 生成 LUT 纹理
    /// 注意：使用 2D 纹理（高度为1）而非 1D 纹理，以确保更好的设备兼容性
    private func generateLUTTexture(from colorStops: [ColorStop]) -> MTLTexture? {
        let width = 256
        var pixels = [UInt8](repeating: 0, count: width * 4)

        let sortedStops = colorStops.sorted { $0.position < $1.position }
        guard sortedStops.count >= 2 else { return nil }

        for i in 0..<width {
            let t = Float(i) / Float(width - 1)
            let color = interpolateColor(at: t, stops: sortedStops)

            pixels[i * 4 + 0] = UInt8(max(0, min(255, color.r * 255)))
            pixels[i * 4 + 1] = UInt8(max(0, min(255, color.g * 255)))
            pixels[i * 4 + 2] = UInt8(max(0, min(255, color.b * 255)))
            pixels[i * 4 + 3] = 255
        }

        // 使用 2D 纹理（高度=1）替代 1D 纹理，兼容性更好
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, 1),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width * 4
        )

        return texture
    }

    private func interpolateColor(at t: Float, stops: [ColorStop]) -> (r: Float, g: Float, b: Float) {
        var lowerIndex = 0
        var upperIndex = stops.count - 1

        for i in 0..<(stops.count - 1) {
            if t >= stops[i].position, t <= stops[i + 1].position {
                lowerIndex = i
                upperIndex = i + 1
                break
            }
        }

        let lower = stops[lowerIndex]
        let upper = stops[upperIndex]

        let range = upper.position - lower.position
        let localT = range > 0 ? (t - lower.position) / range : 0
        let smoothT = localT * localT * (3 - 2 * localT)

        let lowerRGBA = lower.rgba
        let upperRGBA = upper.rgba

        return (
            r: lowerRGBA.r + (upperRGBA.r - lowerRGBA.r) * smoothT,
            g: lowerRGBA.g + (upperRGBA.g - lowerRGBA.g) * smoothT,
            b: lowerRGBA.b + (upperRGBA.b - lowerRGBA.b) * smoothT
        )
    }

    // MARK: - 纹理管理

    /// 上一次的 Bloom 纹理尺寸
    private var lastBloomSize: (width: Int, height: Int) = (0, 0)
    private var lastEnergySize: (width: Int, height: Int) = (0, 0)

    private func ensureBloomTextures(width: Int, height: Int) {
        let bloomWidth = max(1, Int(Float(width) * config.bloomResolutionScale))
        let bloomHeight = max(1, Int(Float(height) * config.bloomResolutionScale))

        // 检查是否需要重建 Bloom 纹理
        if lastBloomSize.width != bloomWidth || lastBloomSize.height != bloomHeight {
            // 归还旧纹理到池
            if let old = bloomThresholdTexture { texturePool.release(old) }
            if let old = bloomBlurHTexture { texturePool.release(old) }
            if let old = bloomBlurVTexture { texturePool.release(old) }

            // 从池获取新纹理
            bloomThresholdTexture = texturePool.acquire(
                width: bloomWidth,
                height: bloomHeight,
                pixelFormat: .rgba16Float,
                usage: [.shaderRead, .renderTarget]
            )
            bloomBlurHTexture = texturePool.acquire(
                width: bloomWidth,
                height: bloomHeight,
                pixelFormat: .rgba16Float,
                usage: [.shaderRead, .renderTarget]
            )
            bloomBlurVTexture = texturePool.acquire(
                width: bloomWidth,
                height: bloomHeight,
                pixelFormat: .rgba16Float,
                usage: [.shaderRead, .renderTarget]
            )

            lastBloomSize = (bloomWidth, bloomHeight)
        }

        // 检查是否需要重建能量输出纹理（使用 HDR 格式）
        if lastEnergySize.width != width || lastEnergySize.height != height {
            // 归还旧纹理
            if let old = energyOutputTexture { texturePool.release(old) }

            // 从池获取新纹理（使用 rgba16Float 以支持 HDR）
            energyOutputTexture = texturePool.acquire(
                width: width,
                height: height,
                pixelFormat: .rgba16Float,
                usage: [.shaderRead, .renderTarget]
            )

            lastEnergySize = (width, height)
        }
    }

    // MARK: - 颜色停靠点动画

    /// 设置动态颜色停靠点
    /// 使用整体偏移替代排序，避免颜色跳变
    private func setupColorStops(_ uniforms: inout EnergyUniforms, time: Float) {
        let colorStops = config.colorStops

        // 确保至少有 6 个颜色停靠点
        let stops: [ColorStop]
        if colorStops.count >= 6 {
            stops = Array(colorStops.prefix(6))
        } else {
            // 扩展到 6 个
            var expanded = colorStops
            while expanded.count < 6 {
                expanded.append(colorStops.last ?? ColorStop(position: 1.0, color: .white))
            }
            stops = expanded
        }

        // 获取 RGBA 值
        func rgba(_ color: UIColor) -> SIMD4<Float> {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
        }

        // 设置固定的颜色和位置（用于 LUT 生成）
        uniforms.color0 = rgba(stops[0].color)
        uniforms.color0Pos = stops[0].position

        uniforms.color1 = rgba(stops[1].color)
        uniforms.color1Pos = stops[1].position

        uniforms.color2 = rgba(stops[2].color)
        uniforms.color2Pos = stops[2].position

        uniforms.color3 = rgba(stops[3].color)
        uniforms.color3Pos = stops[3].position

        uniforms.color4 = rgba(stops[4].color)
        uniforms.color4Pos = stops[4].position

        uniforms.color5 = rgba(stops[5].color)
        uniforms.color5Pos = stops[5].position
        
        // 使用整体偏移替代位置波动，避免排序导致的颜色跳变
        let animSpeed: Float = 0.1
        uniforms.colorOffset = time * animSpeed
        
        // 设置 IDW 弥散参数
        uniforms.diffusionBias = config.diffusionBias
        uniforms.diffusionPower = config.diffusionPower
        
        // 更新颜色点动画状态
        updateColorPoints(deltaTime: 1.0 / 60.0, stops: stops)
        
        // 将颜色点数据传递给 Shader
        uniforms.colorPointCount = Int32(min(colorPoints.count, maxColorPoints))
        
        // 复制颜色点位置
        var positions = uniforms.colorPointPositions
        var colors = uniforms.colorPointColors
        
        for i in 0 ..< min(colorPoints.count, maxColorPoints) {
            let point = colorPoints[i]
            switch i {
            case 0: positions.0 = SIMD2<Float>(point.currentPosition.x, point.currentPosition.y)
                    colors.0 = point.color
            case 1: positions.1 = SIMD2<Float>(point.currentPosition.x, point.currentPosition.y)
                    colors.1 = point.color
            case 2: positions.2 = SIMD2<Float>(point.currentPosition.x, point.currentPosition.y)
                    colors.2 = point.color
            case 3: positions.3 = SIMD2<Float>(point.currentPosition.x, point.currentPosition.y)
                    colors.3 = point.color
            case 4: positions.4 = SIMD2<Float>(point.currentPosition.x, point.currentPosition.y)
                    colors.4 = point.color
            case 5: positions.5 = SIMD2<Float>(point.currentPosition.x, point.currentPosition.y)
                    colors.5 = point.color
            case 6: positions.6 = SIMD2<Float>(point.currentPosition.x, point.currentPosition.y)
                    colors.6 = point.color
            case 7: positions.7 = SIMD2<Float>(point.currentPosition.x, point.currentPosition.y)
                    colors.7 = point.color
            default: break
            }
        }
        
        uniforms.colorPointPositions = positions
        uniforms.colorPointColors = colors
    }
    
    // MARK: - IDW 颜色点动画系统
    
    /// 颜色点状态
    private struct ColorPointState {
        var currentPosition: SIMD2<Float>  // 当前位置 [0, 1]
        var targetPosition: SIMD2<Float>   // 目标位置 [0, 1]
        var velocity: SIMD2<Float>         // 当前速度
        var color: SIMD4<Float>            // RGBA 颜色
        
        init(position: SIMD2<Float>, color: SIMD4<Float>) {
            currentPosition = position
            targetPosition = position
            velocity = .zero
            self.color = color
        }
    }
    
    /// 初始化颜色点
    private func initializeColorPoints(count: Int, colors: [ColorStop]) {
        colorPoints = []
        
        // 沿边缘均匀分布颜色点
        for i in 0 ..< count {
            let angle = Float(i) / Float(count) * 2 * .pi
            
            // 在边缘附近生成初始位置（考虑圆角矩形边缘）
            let edgePosition = edgePositionForAngle(angle)
            
            // 获取对应颜色
            let colorIndex = i % colors.count
            let color = colors[colorIndex]
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.color.getRed(&r, green: &g, blue: &b, alpha: &a)
            let rgba = SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
            
            var point = ColorPointState(position: edgePosition, color: rgba)
            point.targetPosition = randomEdgePosition()
            
            colorPoints.append(point)
        }
        
        colorPointsInitialized = true
    }
    
    /// 计算颜色停靠点的哈希值
    private func computeColorStopsHash(_ stops: [ColorStop]) -> Int {
        var hasher = Hasher()
        for stop in stops {
            hasher.combine(stop.position)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            stop.color.getRed(&r, green: &g, blue: &b, alpha: &a)
            hasher.combine(Float(r))
            hasher.combine(Float(g))
            hasher.combine(Float(b))
            hasher.combine(Float(a))
        }
        return hasher.finalize()
    }
    
    /// 更新颜色点位置（弹簧动画）
    private func updateColorPoints(deltaTime: Float, stops: [ColorStop]) {
        let targetCount = config.colorPointCount
        
        // 计算当前颜色的哈希值
        let currentHash = computeColorStopsHash(stops)
        let colorChanged = currentHash != lastColorStopsHash
        
        // 如果颜色点数量变化或颜色变化，重新初始化
        if colorPoints.count != targetCount || !colorPointsInitialized || colorChanged {
            initializeColorPoints(count: targetCount, colors: stops)
            lastColorStopsHash = currentHash
        }
        
        // 动画参数
        let moveSpeed = config.colorPointSpeed  // [0.5 ~ 5.0]
        let springStiffness: Float = 3.0 * moveSpeed  // 弹簧刚度随速度增加
        let springDamping: Float = 0.6                // 阻尼（稍微降低以增加弹性）
        
        for i in 0 ..< colorPoints.count {
            var point = colorPoints[i]
            
            // 检查是否接近目标位置
            let distance = simd_distance(point.currentPosition, point.targetPosition)
            if distance < 0.08 {
                // 生成新的随机目标位置
                point.targetPosition = randomEdgePosition()
            }
            
            // 弹簧力 = -k * (current - target) - b * velocity
            let displacement = point.currentPosition - point.targetPosition
            let springForce = -springStiffness * displacement
            let dampingForce = -springDamping * point.velocity
            let acceleration = springForce + dampingForce
            
            // 更新速度和位置
            point.velocity += acceleration * deltaTime
            point.currentPosition += point.velocity * deltaTime
            
            // 限制在 [0, 1] 范围内
            point.currentPosition = simd_clamp(point.currentPosition, SIMD2<Float>(0, 0), SIMD2<Float>(1, 1))
            
            colorPoints[i] = point
        }
    }
    
    /// 生成随机边缘位置
    private func randomEdgePosition() -> SIMD2<Float> {
        let angle = Float.random(in: 0 ... 2 * .pi)
        return edgePositionForAngle(angle)
    }
    
    /// 根据角度计算边缘位置
    /// 对于圆角矩形，颜色点沿着实际边缘移动
    private func edgePositionForAngle(_ angle: Float) -> SIMD2<Float> {
        // 简化版：在 [0.1, 0.9] 范围内生成位置
        // 这样颜色点会分布在视图内部，接近边缘
        let margin: Float = 0.1
        let range: Float = 1.0 - 2 * margin
        
        // 使用角度生成边缘位置
        let normalizedAngle = angle / (2 * .pi)
        
        // 沿矩形边缘分布（简化为正方形）
        let perimeter: Float = 4.0
        let edgePos = normalizedAngle * perimeter
        
        var x: Float
        var y: Float
        
        if edgePos < 1.0 {
            // 底边
            x = edgePos
            y = 0.0
        } else if edgePos < 2.0 {
            // 右边
            x = 1.0
            y = edgePos - 1.0
        } else if edgePos < 3.0 {
            // 顶边
            x = 1.0 - (edgePos - 2.0)
            y = 1.0
        } else {
            // 左边
            x = 0.0
            y = 1.0 - (edgePos - 3.0)
        }
        
        // 映射到有效范围
        x = margin + x * range
        y = margin + y * range
        
        return SIMD2<Float>(x, y)
    }
}

// MARK: - MTKViewDelegate

extension EnergyMetalRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
    }

    func draw(in view: MTKView) {
        cpuStartTime = CACurrentMediaTime()

        // 解析模式不需要 maskTexture，纹理模式需要
        let needsMask = sdfMode == .texture
        guard (!needsMask || maskTexture != nil),
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        let width = Int(viewportSize.width)
        let height = Int(viewportSize.height)

        guard width > 0, height > 0 else { return }

        // 使用真实帧间隔更新时间（支持 120Hz 和掉帧场景）
        let currentFrameTime = CACurrentMediaTime()
        let deltaTime = lastFrameTime > 0 ? Float(currentFrameTime - lastFrameTime) : Float(1.0 / 60.0)
        lastFrameTime = currentFrameTime
        totalTime += deltaTime * animationParams.speed

        // 确保 Bloom 纹理存在
        if config.bloomEnabled {
            ensureBloomTextures(width: width, height: height)
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // 准备 Uniform 数据
        let minDimension = Float(min(width, height))
        
        var energyUniforms = EnergyUniforms(
            time: totalTime,
            speed: animationParams.speed,
            noiseStrength: animationParams.noiseStrength,
            phaseScale: config.phaseScale,
            glowIntensity: config.glowIntensity,
            edgeBoost: config.edgeBoost,
            intensity: animationParams.intensity,
            ditherEnabled: config.ditherEnabled ? 1.0 : 0.0,
            resolution: SIMD2<Float>(Float(width), Float(height)),
            texelSize: SIMD2<Float>(1.0 / Float(width), 1.0 / Float(height)),
            noiseOctaves: Int32(config.noiseOctaves)
        )

        // 设置边框发光参数（转换为像素单位）
        energyUniforms.borderWidth = config.borderWidth * minDimension
        energyUniforms.borderThickness = config.borderThickness * minDimension
        energyUniforms.borderSoftness = config.borderSoftness
        energyUniforms.innerGlowIntensity = config.innerGlowIntensity
        energyUniforms.innerGlowRange = config.innerGlowRange * minDimension
        energyUniforms.outerGlowIntensity = config.outerGlowIntensity
        energyUniforms.outerGlowRange = config.outerGlowRange * minDimension
        energyUniforms.colorFlowSpeed = config.colorFlowSpeed
        
        // SDF 最大距离（与 EnergyMaskCache 中的计算保持一致）
        // 取较小边的 1/4，最小 32，最大 128
        let sdfMaxDist = Float(max(32, min(128, min(width, height) / 4)))
        energyUniforms.sdfMaxDist = sdfMaxDist

        // 设置动态颜色停靠点
        setupColorStops(&energyUniforms, time: totalTime)

        if config.bloomEnabled, let energyOutputTexture {
            // Pass 1: 渲染能量场到中间纹理
            renderEnergyPass(
                commandBuffer: commandBuffer,
                targetTexture: energyOutputTexture,
                uniforms: &energyUniforms
            )

            // Pass 2-4: Bloom
            renderBloomPasses(commandBuffer: commandBuffer, sourceTexture: energyOutputTexture)

            // Pass 5: 最终合成
            renderCompositePass(
                commandBuffer: commandBuffer,
                renderPassDescriptor: renderPassDescriptor,
                mainTexture: energyOutputTexture
            )
        } else {
            // 直接渲染到屏幕（无 Bloom）
            renderEnergyPassDirect(
                commandBuffer: commandBuffer,
                renderPassDescriptor: renderPassDescriptor,
                uniforms: &energyUniforms
            )
        }

        // GPU 时间统计：使用 scheduled 和 completed 时间差
        let gpuStartTime = CACurrentMediaTime()
        var scheduledTime: CFTimeInterval = 0

        commandBuffer.addScheduledHandler { _ in
            scheduledTime = CACurrentMediaTime()
        }

        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            let completedTime = CACurrentMediaTime()
            let cpuTime = scheduledTime - gpuStartTime // CPU 准备时间
            let gpuTime = completedTime - scheduledTime // GPU 执行时间

            DispatchQueue.main.async {
                self.delegate?.rendererDidFinishFrame(self, cpuTime: cpuTime, gpuTime: gpuTime)
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - 渲染 Pass

    private func renderEnergyPass(
        commandBuffer: MTLCommandBuffer,
        targetTexture: MTLTexture,
        uniforms: inout EnergyUniforms
    ) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = targetTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        // 根据 SDF 模式选择 Pipeline
        let pipelineState: MTLRenderPipelineState?
        
        switch sdfMode {
        case .analytic:
            // 解析 SDF 模式
            pipelineState = energyAnalyticHDRPipelineState
        case .texture:
            // 纹理 SDF 模式
            let hasSDF = sdfTexture != nil && config.sdfEnabled
            pipelineState = hasSDF ? energyHDRPipelineState : energyNoSDFHDRPipelineState
        }

        guard let pipeline = pipelineState else {
            encoder.endEncoding()
            return
        }

        encoder.setRenderPipelineState(pipeline)
        
        switch sdfMode {
        case .analytic:
            // 解析模式：只需要 LUT 纹理
            encoder.setFragmentTexture(lutTexture, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EnergyUniforms>.stride, index: 0)
            
            // 设置解析形状参数
            var shapeParams = ShaderAnalyticShapeParams()
            if let params = analyticShapeParams {
                shapeParams.shapeType = params.shapeType
                shapeParams.viewSize = params.viewSize
                shapeParams.center = params.center
                shapeParams.halfSize = params.halfSize
                shapeParams.cornerRadius = params.cornerRadius
                shapeParams.radius = params.radius
                shapeParams.isVertical = params.isVertical
            }
            encoder.setFragmentBytes(&shapeParams, length: MemoryLayout<ShaderAnalyticShapeParams>.stride, index: 1)
            
        case .texture:
            // 纹理模式
            encoder.setFragmentTexture(maskTexture, index: 0)
            let hasSDF = sdfTexture != nil && config.sdfEnabled
            if hasSDF {
                encoder.setFragmentTexture(sdfTexture, index: 1)
                encoder.setFragmentTexture(lutTexture, index: 2)
            } else {
                encoder.setFragmentTexture(lutTexture, index: 1)
            }
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EnergyUniforms>.stride, index: 0)
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }

    private func renderEnergyPassDirect(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        uniforms: inout EnergyUniforms
    ) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        // 根据 SDF 模式选择 Pipeline
        let pipelineState: MTLRenderPipelineState?
        
        switch sdfMode {
        case .analytic:
            pipelineState = energyAnalyticPipelineState
        case .texture:
            let hasSDF = sdfTexture != nil && config.sdfEnabled
            pipelineState = hasSDF ? energyPipelineState : energyNoSDFPipelineState
        }

        guard let pipeline = pipelineState else {
            encoder.endEncoding()
            return
        }

        encoder.setRenderPipelineState(pipeline)
        
        switch sdfMode {
        case .analytic:
            // 解析模式
            encoder.setFragmentTexture(lutTexture, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EnergyUniforms>.stride, index: 0)
            
            var shapeParams = ShaderAnalyticShapeParams()
            if let params = analyticShapeParams {
                shapeParams.shapeType = params.shapeType
                shapeParams.viewSize = params.viewSize
                shapeParams.center = params.center
                shapeParams.halfSize = params.halfSize
                shapeParams.cornerRadius = params.cornerRadius
                shapeParams.radius = params.radius
                shapeParams.isVertical = params.isVertical
            }
            encoder.setFragmentBytes(&shapeParams, length: MemoryLayout<ShaderAnalyticShapeParams>.stride, index: 1)
            
        case .texture:
            encoder.setFragmentTexture(maskTexture, index: 0)
            let hasSDF = sdfTexture != nil && config.sdfEnabled
            if hasSDF {
                encoder.setFragmentTexture(sdfTexture, index: 1)
                encoder.setFragmentTexture(lutTexture, index: 2)
            } else {
                encoder.setFragmentTexture(lutTexture, index: 1)
            }
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EnergyUniforms>.stride, index: 0)
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }

    private func renderBloomPasses(commandBuffer: MTLCommandBuffer, sourceTexture: MTLTexture) {
        guard
            let thresholdTexture = bloomThresholdTexture,
            let blurHTexture = bloomBlurHTexture,
            let blurVTexture = bloomBlurVTexture,
            let thresholdPipeline = bloomThresholdPipelineState,
            let blurPipeline = bloomBlurPipelineState else {
            return
        }

        let bloomWidth = thresholdTexture.width
        let bloomHeight = thresholdTexture.height

        // Pass 2: Threshold
        var thresholdUniforms = BloomUniforms(
            threshold: config.bloomThreshold,
            intensity: config.bloomIntensity,
            texelSize: SIMD2<Float>(1.0 / Float(sourceTexture.width), 1.0 / Float(sourceTexture.height)),
            blurRadius: Int32(config.bloomBlurRadius),
            isHorizontal: 0
        )

        let thresholdPass = MTLRenderPassDescriptor()
        thresholdPass.colorAttachments[0].texture = thresholdTexture
        thresholdPass.colorAttachments[0].loadAction = .clear
        thresholdPass.colorAttachments[0].storeAction = .store

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: thresholdPass) {
            encoder.setRenderPipelineState(thresholdPipeline)
            encoder.setFragmentTexture(sourceTexture, index: 0)
            encoder.setFragmentBytes(&thresholdUniforms, length: MemoryLayout<BloomUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            encoder.endEncoding()
        }

        // Pass 3: Horizontal Blur
        var blurHUniforms = BloomUniforms(
            threshold: config.bloomThreshold,
            intensity: config.bloomIntensity,
            texelSize: SIMD2<Float>(1.0 / Float(bloomWidth), 1.0 / Float(bloomHeight)),
            blurRadius: Int32(config.bloomBlurRadius),
            isHorizontal: 1
        )

        let blurHPass = MTLRenderPassDescriptor()
        blurHPass.colorAttachments[0].texture = blurHTexture
        blurHPass.colorAttachments[0].loadAction = .clear
        blurHPass.colorAttachments[0].storeAction = .store

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: blurHPass) {
            encoder.setRenderPipelineState(blurPipeline)
            encoder.setFragmentTexture(thresholdTexture, index: 0)
            encoder.setFragmentBytes(&blurHUniforms, length: MemoryLayout<BloomUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            encoder.endEncoding()
        }

        // Pass 4: Vertical Blur
        var blurVUniforms = blurHUniforms
        blurVUniforms.isHorizontal = 0

        let blurVPass = MTLRenderPassDescriptor()
        blurVPass.colorAttachments[0].texture = blurVTexture
        blurVPass.colorAttachments[0].loadAction = .clear
        blurVPass.colorAttachments[0].storeAction = .store

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: blurVPass) {
            encoder.setRenderPipelineState(blurPipeline)
            encoder.setFragmentTexture(blurHTexture, index: 0)
            encoder.setFragmentBytes(&blurVUniforms, length: MemoryLayout<BloomUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            encoder.endEncoding()
        }
    }

    private func renderCompositePass(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        mainTexture: MTLTexture
    ) {
        guard
            let compositePipeline = bloomCompositePipelineState,
            let bloomTexture = bloomBlurVTexture else {
            return
        }

        var compositeUniforms = BloomUniforms(
            threshold: config.bloomThreshold,
            intensity: config.bloomIntensity,
            texelSize: SIMD2<Float>(0, 0),
            blurRadius: 0,
            isHorizontal: 0
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        encoder.setRenderPipelineState(compositePipeline)
        encoder.setFragmentTexture(mainTexture, index: 0)
        encoder.setFragmentTexture(bloomTexture, index: 1)
        encoder.setFragmentBytes(&compositeUniforms, length: MemoryLayout<BloomUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }
}
