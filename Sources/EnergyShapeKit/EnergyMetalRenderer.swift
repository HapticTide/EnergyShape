//
//  EnergyMetalRenderer.swift
//  EnergyShapeKit
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

// MARK: - Uniform 结构（与 Shader 对应）

/// 能量场 Uniform（需要与 Shader 中定义保持一致）
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
    var padding: Int32 = 0  // 保持 16 字节对齐
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
    private var bloomThresholdPipelineState: MTLRenderPipelineState?
    private var bloomBlurPipelineState: MTLRenderPipelineState?
    private var bloomCompositePipelineState: MTLRenderPipelineState?
    
    // 纹理
    private var maskTexture: MTLTexture?
    private var sdfTexture: MTLTexture?
    private var lutTexture: MTLTexture?
    
    // Bloom 中间纹理
    private var bloomThresholdTexture: MTLTexture?
    private var bloomBlurHTexture: MTLTexture?
    private var bloomBlurVTexture: MTLTexture?
    private var energyOutputTexture: MTLTexture?
    
    // 纹理池
    private let texturePool: TexturePool
    
    // 配置
    private var config: EnergyConfig = .default
    private var animationParams = AnimationParams()
    private var totalTime: Float = 0
    
    // 性能统计
    private var cpuStartTime: CFTimeInterval = 0
    private var lastGPUTime: Double = 0
    
    // 当前视图尺寸
    private var viewportSize: CGSize = .zero
    
    // MARK: - 初始化
    
    init(device: MTLDevice, view: MTKView) throws {
        self.device = device
        self.view = view
        self.texturePool = TexturePool(device: device)
        
        guard let queue = device.makeCommandQueue() else {
            throw EnergyShapeError.deviceCreationFailed
        }
        self.commandQueue = queue
        
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
        if let libraryURL = Bundle.module.url(forResource: "default", withExtension: "metallib"),
           let library = try? device.makeLibrary(URL: libraryURL) {
            try setupPipelinesWithLibrary(library)
            return
        }
        
        // 3. 从 Bundle.module 加载 .metal 源码并在运行时编译
        if let shaderURL = Bundle.module.url(forResource: "Shaders", withExtension: "metal"),
           let shaderSource = try? String(contentsOf: shaderURL, encoding: .utf8) {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            try setupPipelinesWithLibrary(library)
            return
        }
        #endif
        
        // 4. 尝试从当前类所在的 Bundle 加载
        let classBundle = Bundle(for: EnergyMetalRenderer.self)
        if let libraryURL = classBundle.url(forResource: "default", withExtension: "metallib"),
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
        
        // 能量场 Pipeline（有 SDF）
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
            
            energyPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        }
        
        // 能量场 Pipeline（无 SDF）
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
            
            energyNoSDFPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        }
        
        // Bloom Threshold Pipeline
        if let fragmentFunction = library.makeFunction(name: "fragmentBloomThreshold") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .rgba16Float
            
            bloomThresholdPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        }
        
        // Bloom Blur Pipeline
        if let fragmentFunction = library.makeFunction(name: "fragmentBloomBlur") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .rgba16Float
            
            bloomBlurPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        }
        
        // Bloom Composite Pipeline
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
            
            bloomCompositePipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        }
    }
    
    private func setupDefaultLUT() {
        // 创建默认 LUT
        updateColorLUT(EnergyConfig.defaultColors)
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
        if oldBloomEnabled && !config.bloomEnabled {
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
        self.animationParams = params
    }
    
    /// 更新 Mask 纹理
    func updateMaskTextures(mask: MTLTexture?, sdf: MTLTexture?) {
        self.maskTexture = mask
        self.sdfTexture = sdf
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
            if t >= stops[i].position && t <= stops[i + 1].position {
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
        
        // 检查是否需要重建能量输出纹理
        if lastEnergySize.width != width || lastEnergySize.height != height {
            // 归还旧纹理
            if let old = energyOutputTexture { texturePool.release(old) }
            
            // 从池获取新纹理
            energyOutputTexture = texturePool.acquire(
                width: width,
                height: height,
                pixelFormat: .bgra8Unorm,
                usage: [.shaderRead, .renderTarget]
            )
            
            lastEnergySize = (width, height)
        }
    }
}

// MARK: - MTKViewDelegate

extension EnergyMetalRenderer: MTKViewDelegate {
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
    }
    
    func draw(in view: MTKView) {
        cpuStartTime = CACurrentMediaTime()
        
        guard let maskTexture = maskTexture,
              let lutTexture = lutTexture,
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }
        
        let width = Int(viewportSize.width)
        let height = Int(viewportSize.height)
        
        guard width > 0 && height > 0 else { return }
        
        // 更新时间
        totalTime += Float(1.0 / 60.0) * animationParams.speed
        
        // 确保 Bloom 纹理存在
        if config.bloomEnabled {
            ensureBloomTextures(width: width, height: height)
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        // 准备 Uniform 数据
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
        
        if config.bloomEnabled, let energyOutputTexture = energyOutputTexture {
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
            guard let self = self else { return }
            let completedTime = CACurrentMediaTime()
            let cpuTime = scheduledTime - gpuStartTime  // CPU 准备时间
            let gpuTime = completedTime - scheduledTime  // GPU 执行时间
            
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
        
        let hasSDF = sdfTexture != nil && config.sdfEnabled
        let pipelineState = hasSDF ? energyPipelineState : energyNoSDFPipelineState
        
        guard let pipeline = pipelineState else {
            encoder.endEncoding()
            return
        }
        
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(maskTexture, index: 0)
        
        if hasSDF {
            encoder.setFragmentTexture(sdfTexture, index: 1)
            encoder.setFragmentTexture(lutTexture, index: 2)
        } else {
            encoder.setFragmentTexture(lutTexture, index: 1)
        }
        
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EnergyUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }
    
    private func renderEnergyPassDirect(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        uniforms: inout EnergyUniforms
    ) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        let hasSDF = sdfTexture != nil && config.sdfEnabled
        let pipelineState = hasSDF ? energyPipelineState : energyNoSDFPipelineState
        
        guard let pipeline = pipelineState else {
            encoder.endEncoding()
            return
        }
        
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(maskTexture, index: 0)
        
        if hasSDF {
            encoder.setFragmentTexture(sdfTexture, index: 1)
            encoder.setFragmentTexture(lutTexture, index: 2)
        } else {
            encoder.setFragmentTexture(lutTexture, index: 1)
        }
        
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EnergyUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }
    
    private func renderBloomPasses(commandBuffer: MTLCommandBuffer, sourceTexture: MTLTexture) {
        guard let thresholdTexture = bloomThresholdTexture,
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
        guard let compositePipeline = bloomCompositePipelineState,
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
