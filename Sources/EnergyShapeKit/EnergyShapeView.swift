//
//  EnergyShapeView.swift
//  EnergyShapeKit
//
//  Created by Sun on 2026/1/21.
//  能量动画视图 - 对外 API 封装
//

import UIKit
import MetalKit
import ObjectiveC

// MARK: - EnergyShapeView

/// 通用 Shape 能量动画视图
/// 在任意 CGPath 形状内部播放高质感的能量流动动画
public class EnergyShapeView: UIView {
    
    // MARK: - 公开属性
    
    /// 能量动画的形状路径
    public var shapePath: CGPath? {
        didSet {
            // 使用 boundingBox 比较而非引用比较，避免 copy() 后的不必要重建
            let newBounds = shapePath?.boundingBox ?? .zero
            guard newBounds != lastPathBounds else { return }
            lastPathBounds = newBounds
            handleShapePathChanged()
        }
    }
    
    /// 形状适配模式
    public var shapeContentMode: ShapeContentMode = .aspectFit {
        didSet {
            setNeedsLayout()
        }
    }
    
    /// 能量效果配置
    public var config: EnergyConfig = .default {
        didSet {
            var validatedConfig = config
            validatedConfig.validate()
            if config.colorStops != oldValue.colorStops {
                renderer?.updateColorLUT(config.colorStops)
            }
            renderer?.updateConfig(validatedConfig)
        }
    }
    
    /// 性能统计和错误回调代理
    public weak var delegate: EnergyShapeViewDelegate?
    
    /// 降级模式
    public var fallbackMode: FallbackMode = .coreAnimation
    
    /// 当前动画状态
    public private(set) var animationState: EnergyAnimationState = .idle {
        didSet {
            if animationState != oldValue {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.energyShapeView(self, didChangeState: self.animationState)
                }
            }
        }
    }
    
    /// 性能统计
    public var performanceStats: EnergyPerformanceStats {
        return _performanceStats
    }
    
    /// 是否支持 Metal
    public static var isMetalSupported: Bool {
        return MTLCreateSystemDefaultDevice() != nil
    }
    
    // MARK: - 私有属性
    
    private var metalView: MTKView?
    private var renderer: EnergyMetalRenderer?
    private var stateMachine: EnergyStateMachine?
    private var maskCache: EnergyMaskCache?
    
    private var _performanceStats = EnergyPerformanceStats()
    private var lastFrameTime: CFTimeInterval = 0
    private var frameTimeAccumulator: [Double] = []
    private let maxFrameSamples = 60
    
    private var isMetalInitialized = false
    private var pendingStart = false
    
    /// 上一次的 shapePath boundingBox（用于避免不必要的 mask 重建）
    private var lastPathBounds: CGRect = .zero
    
    /// 上一次的视图尺寸（用于避免 layoutSubviews 中重复更新 mask）
    private var lastBoundsSize: CGSize = .zero
    
    // MARK: - 初始化
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        backgroundColor = .clear
        isOpaque = false
        
        // 尝试初始化 Metal
        initializeMetalIfNeeded()
    }
    
    deinit {
        stop()
        cleanupFallbackLayers()
        metalView?.removeFromSuperview()
        metalView = nil
        renderer = nil
        stateMachine = nil
        maskCache = nil
    }
    
    // MARK: - 布局
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        metalView?.frame = bounds
        
        // 仅当尺寸变化时才重新生成 mask
        if bounds.size != lastBoundsSize {
            lastBoundsSize = bounds.size
            if let _ = shapePath, bounds.size != .zero {
                updateMaskForCurrentBounds()
            }
        }
    }
    
    // MARK: - 公开方法
    
    /// 开始动画
    public func start() {
        guard animationState == .idle || animationState == .paused else { return }
        
        if !isMetalInitialized {
            pendingStart = true
            initializeMetalIfNeeded()
            return
        }
        
        stateMachine?.start()
        metalView?.isPaused = false
        animationState = .startup
    }
    
    /// 停止动画（重置到初始状态）
    public func stop() {
        stateMachine?.stop()
        metalView?.isPaused = true
        animationState = .idle
    }
    
    /// 暂停动画（保持当前状态）
    public func pause() {
        guard animationState != .idle && animationState != .paused else { return }
        
        stateMachine?.pause()
        metalView?.isPaused = true
        animationState = .paused
    }
    
    /// 恢复动画
    public func resume() {
        guard animationState == .paused else { return }
        
        stateMachine?.resume()
        metalView?.isPaused = false
        // 恢复到之前的状态（由状态机管理）
        if let state = stateMachine?.currentState {
            animationState = state
        }
    }
    
    /// 切换到稳定状态
    public func settle() {
        guard animationState == .loop else { return }
        
        stateMachine?.settle()
        animationState = .settle
    }
    
    // MARK: - Metal 初始化
    
    private func initializeMetalIfNeeded() {
        guard !isMetalInitialized else { return }
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            handleError(EnergyShapeError.metalNotSupported)
            return
        }
        
        do {
            // 创建 MTKView
            let mtkView = MTKView(frame: bounds, device: device)
            mtkView.colorPixelFormat = .bgra8Unorm
            mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            mtkView.isOpaque = false
            mtkView.backgroundColor = .clear
            mtkView.framebufferOnly = false
            mtkView.isPaused = true
            mtkView.enableSetNeedsDisplay = false
            mtkView.preferredFramesPerSecond = 60
            
            // 创建渲染器
            let renderer = try EnergyMetalRenderer(device: device, view: mtkView)
            renderer.delegate = self
            mtkView.delegate = renderer
            
            // 创建 Mask 缓存
            let maskCache = EnergyMaskCache(device: device)
            
            // 创建状态机
            let stateMachine = EnergyStateMachine(config: config)
            stateMachine.delegate = self
            
            // 保存引用
            self.metalView = mtkView
            self.renderer = renderer
            self.maskCache = maskCache
            self.stateMachine = stateMachine
            
            // 添加 Metal 视图
            addSubview(mtkView)
            mtkView.frame = bounds
            
            isMetalInitialized = true
            
            // 如果有待处理的 shapePath
            if let path = shapePath {
                handleShapePathChanged()
            }
            
            // 如果有待处理的 start
            if pendingStart {
                pendingStart = false
                start()
            }
            
        } catch {
            handleError(error)
        }
    }
    
    // MARK: - 私有方法
    
    private func handleShapePathChanged() {
        guard let path = shapePath, bounds.size != .zero else { return }
        
        updateMaskForCurrentBounds()
    }
    
    private func updateMaskForCurrentBounds() {
        guard let path = shapePath, let maskCache = maskCache else { return }
        
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let transformedPath = applyContentMode(to: path, in: bounds)
        
        maskCache.updatePath(
            transformedPath,
            size: bounds.size,
            scale: scale,
            sdfEnabled: config.sdfEnabled,
            sdfQuality: config.sdfQuality
        ) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let textures):
                self.renderer?.updateMaskTextures(mask: textures.mask, sdf: textures.sdf)
                self._performanceStats.maskRebuildCount += 1
                
            case .failure(let error):
                self.handleError(error)
            }
        }
    }
    
    private func applyContentMode(to path: CGPath, in bounds: CGRect) -> CGPath {
        let pathBounds = path.boundingBox
        guard !pathBounds.isEmpty && !bounds.isEmpty else { return path }
        
        var transform: CGAffineTransform
        
        switch shapeContentMode {
        case .aspectFit:
            transform = aspectFitTransform(from: pathBounds, to: bounds)
            
        case .aspectFill:
            transform = aspectFillTransform(from: pathBounds, to: bounds)
            
        case .center:
            let dx = bounds.midX - pathBounds.midX
            let dy = bounds.midY - pathBounds.midY
            transform = CGAffineTransform(translationX: dx, y: dy)
            
        case .scaleToFill:
            let scaleX = bounds.width / pathBounds.width
            let scaleY = bounds.height / pathBounds.height
            transform = CGAffineTransform(translationX: -pathBounds.minX, y: -pathBounds.minY)
                .scaledBy(x: scaleX, y: scaleY)
            
        case .custom(let customTransform):
            transform = customTransform
        }
        
        return path.copy(using: &transform) ?? path
    }
    
    private func aspectFitTransform(from source: CGRect, to destination: CGRect) -> CGAffineTransform {
        let scale = min(destination.width / source.width, destination.height / source.height)
        let scaledWidth = source.width * scale
        let scaledHeight = source.height * scale
        let dx = destination.minX + (destination.width - scaledWidth) / 2 - source.minX * scale
        let dy = destination.minY + (destination.height - scaledHeight) / 2 - source.minY * scale
        
        return CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: dx / scale, y: dy / scale)
    }
    
    private func aspectFillTransform(from source: CGRect, to destination: CGRect) -> CGAffineTransform {
        let scale = max(destination.width / source.width, destination.height / source.height)
        let scaledWidth = source.width * scale
        let scaledHeight = source.height * scale
        let dx = destination.minX + (destination.width - scaledWidth) / 2 - source.minX * scale
        let dy = destination.minY + (destination.height - scaledHeight) / 2 - source.minY * scale
        
        return CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: dx / scale, y: dy / scale)
    }
    
    private func handleError(_ error: Error) {
        let energyError: EnergyShapeError
        if let e = error as? EnergyShapeError {
            energyError = e
        } else {
            energyError = .renderingFailed(error.localizedDescription)
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.energyShapeView(self, didFailWithError: energyError)
            
            // 处理降级
            switch self.fallbackMode {
            case .none:
                break
            case .coreAnimation:
                self.setupCoreAnimationFallback()
            case .staticImage:
                self.setupStaticImageFallback()
            }
        }
    }
    
    private func setupCoreAnimationFallback() {
        // CoreAnimation 降级效果：使用渐变动画模拟能量流动
        guard let path = shapePath else { return }
        
        // 移除 Metal 视图
        metalView?.removeFromSuperview()
        metalView = nil
        
        // 创建形状图层
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = applyContentMode(to: path, in: bounds)
        shapeLayer.fillColor = nil
        shapeLayer.strokeColor = nil
        
        // 创建渐变图层
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = bounds
        gradientLayer.colors = config.colorStops.sorted { $0.position < $1.position }.map { $0.color.cgColor }
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.mask = shapeLayer
        
        // 添加到视图
        layer.addSublayer(gradientLayer)
        
        // 创建流动动画
        let animation = CABasicAnimation(keyPath: "colors")
        animation.fromValue = gradientLayer.colors
        // 循环移位颜色
        if let colors = gradientLayer.colors as? [CGColor], colors.count > 1 {
            var shifted = colors
            shifted.append(shifted.removeFirst())
            animation.toValue = shifted
        }
        animation.duration = 2.0 / Double(config.speed)
        animation.repeatCount = .infinity
        animation.autoreverses = false
        
        gradientLayer.add(animation, forKey: "colorFlow")
        
        // 保存引用以便清理
        objc_setAssociatedObject(self, &AssociatedKeys.fallbackLayer, gradientLayer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    private func setupStaticImageFallback() {
        // 静态图片降级：渲染静态渐变填充
        guard let path = shapePath else { return }
        
        // 移除 Metal 视图
        metalView?.removeFromSuperview()
        metalView = nil
        
        // 创建形状图层
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = applyContentMode(to: path, in: bounds)
        
        // 创建渐变图层
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = bounds
        gradientLayer.colors = config.colorStops.sorted { $0.position < $1.position }.map { $0.color.cgColor }
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.mask = shapeLayer
        
        layer.addSublayer(gradientLayer)
        
        // 保存引用
        objc_setAssociatedObject(self, &AssociatedKeys.fallbackLayer, gradientLayer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    /// 清理降级图层
    private func cleanupFallbackLayers() {
        if let layer = objc_getAssociatedObject(self, &AssociatedKeys.fallbackLayer) as? CALayer {
            layer.removeFromSuperlayer()
            objc_setAssociatedObject(self, &AssociatedKeys.fallbackLayer, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    /// 关联对象键
    private struct AssociatedKeys {
        static var fallbackLayer: UInt8 = 0
    }
    
    private func updatePerformanceStats(frameTime: Double) {
        frameTimeAccumulator.append(frameTime)
        if frameTimeAccumulator.count > maxFrameSamples {
            frameTimeAccumulator.removeFirst()
        }
        
        _performanceStats.currentFPS = frameTime > 0 ? 1.0 / frameTime : 0
        _performanceStats.averageFPS = frameTimeAccumulator.isEmpty ? 0 :
            1.0 / (frameTimeAccumulator.reduce(0, +) / Double(frameTimeAccumulator.count))
        
        if let maskCache = maskCache {
            _performanceStats.textureMemoryBytes = maskCache.totalMemoryBytes
        }
        
        delegate?.energyShapeView(self, didUpdateStats: _performanceStats)
    }
}

// MARK: - EnergyMetalRendererDelegate

extension EnergyShapeView: EnergyMetalRendererDelegate {
    func rendererDidFinishFrame(_ renderer: EnergyMetalRenderer, cpuTime: Double, gpuTime: Double) {
        let currentTime = CACurrentMediaTime()
        let frameTime = lastFrameTime > 0 ? currentTime - lastFrameTime : 1.0 / 60.0
        lastFrameTime = currentTime
        
        _performanceStats.cpuTime = cpuTime * 1000 // 转换为毫秒
        _performanceStats.gpuTime = gpuTime * 1000
        
        updatePerformanceStats(frameTime: frameTime)
    }
    
    func renderer(_ renderer: EnergyMetalRenderer, didFailWithError error: Error) {
        handleError(error)
    }
}

// MARK: - EnergyStateMachineDelegate

extension EnergyShapeView: EnergyStateMachineDelegate {
    func stateMachine(_ stateMachine: EnergyStateMachine, didTransitionTo state: EnergyAnimationState) {
        animationState = state
    }
    
    func stateMachine(_ stateMachine: EnergyStateMachine, didUpdateParams params: AnimationParams) {
        renderer?.updateAnimationParams(params)
    }
}
