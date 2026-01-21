//
//  EnergyStateMachine.swift
//  EnergyShape
//
//  Created by Sun on 2026/1/21.
//  动画状态机 - 管理动画生命周期与参数插值
//

import Foundation
import QuartzCore

// MARK: - 动画参数

/// 动画参数（传递给 Shader）
public struct AnimationParams {
    /// 整体强度 [0 ~ 1]
    public var intensity: Float = 0
    /// 当前速度
    public var speed: Float = 1
    /// 当前噪声强度
    public var noiseStrength: Float = 0.3
    
    public init(intensity: Float = 0, speed: Float = 1, noiseStrength: Float = 0.3) {
        self.intensity = intensity
        self.speed = speed
        self.noiseStrength = noiseStrength
    }
}

// MARK: - DisplayLink Proxy（防止循环引用）

/// DisplayLink 代理对象
/// 使用 weak 引用打破 CADisplayLink → target 的强引用循环
private final class DisplayLinkProxy {
    weak var target: EnergyStateMachine?
    
    init(target: EnergyStateMachine) {
        self.target = target
    }
    
    @objc func handleDisplayLink(_ displayLink: CADisplayLink) {
        target?.handleDisplayLinkTick(displayLink)
    }
}

// MARK: - 状态机代理

/// 状态机代理协议
protocol EnergyStateMachineDelegate: AnyObject {
    /// 状态发生转换
    func stateMachine(_ stateMachine: EnergyStateMachine, didTransitionTo state: EnergyAnimationState)
    /// 参数更新（每帧调用）
    func stateMachine(_ stateMachine: EnergyStateMachine, didUpdateParams params: AnimationParams)
}

// MARK: - EnergyStateMachine

/// 能量动画状态机
/// 管理 idle → startup → loop ⇄ settle 的状态转换
final class EnergyStateMachine {
    
    // MARK: - 属性
    
    weak var delegate: EnergyStateMachineDelegate?
    
    /// 当前状态
    private(set) var currentState: EnergyAnimationState = .idle
    
    /// 配置
    private var config: EnergyConfig
    
    /// 暂停前的状态
    private var stateBeforePause: EnergyAnimationState = .idle
    
    /// 总时间（用于 shader）
    private var totalTime: TimeInterval = 0
    
    /// 当前状态开始时间
    private var stateStartTime: TimeInterval = 0
    
    /// 当前状态持续时间
    private var stateTime: TimeInterval {
        return totalTime - stateStartTime
    }
    
    /// 循环开始时间（用于 autoSettle）
    private var loopStartTime: TimeInterval = 0
    
    /// DisplayLink
    private var displayLink: CADisplayLink?
    
    /// 上一帧时间戳
    private var lastTimestamp: CFTimeInterval = 0
    
    /// 当前动画参数
    private(set) var currentParams = AnimationParams()
    
    // MARK: - 初始化
    
    init(config: EnergyConfig) {
        self.config = config
    }
    
    deinit {
        stopDisplayLink()
    }
    
    // MARK: - 公开方法
    
    /// 更新配置
    func updateConfig(_ config: EnergyConfig) {
        self.config = config
    }
    
    /// 开始动画
    func start() {
        guard currentState == .idle || currentState == .paused else { return }
        
        if currentState == .paused {
            resume()
            return
        }
        
        totalTime = 0
        stateStartTime = 0
        transitionTo(.startup)
        startDisplayLink()
    }
    
    /// 停止动画
    func stop() {
        stopDisplayLink()
        totalTime = 0
        stateStartTime = 0
        transitionTo(.idle)
    }
    
    /// 暂停动画
    func pause() {
        guard currentState != .idle && currentState != .paused else { return }
        
        stateBeforePause = currentState
        stopDisplayLink()
        transitionTo(.paused)
    }
    
    /// 恢复动画
    func resume() {
        guard currentState == .paused else { return }
        
        transitionTo(stateBeforePause)
        startDisplayLink()
    }
    
    /// 进入稳定状态
    func settle() {
        guard currentState == .loop else { return }
        
        stateStartTime = totalTime
        transitionTo(.settle)
    }
    
    /// 获取当前时间（用于 Shader）
    var time: Float {
        return Float(totalTime)
    }
    
    // MARK: - DisplayLink
    
    /// DisplayLink 代理（防止循环引用）
    private var displayLinkProxy: DisplayLinkProxy?
    
    private func startDisplayLink() {
        stopDisplayLink()
        
        let proxy = DisplayLinkProxy(target: self)
        displayLinkProxy = proxy
        displayLink = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.handleDisplayLink(_:)))
        displayLink?.preferredFramesPerSecond = 60
        displayLink?.add(to: .main, forMode: .common)
        lastTimestamp = CACurrentMediaTime()
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil
    }
    
    /// DisplayLink 回调（由 proxy 调用）
    fileprivate func handleDisplayLinkTick(_ displayLink: CADisplayLink) {
        let currentTimestamp = displayLink.timestamp
        let deltaTime = lastTimestamp > 0 ? currentTimestamp - lastTimestamp : 1.0 / 60.0
        lastTimestamp = currentTimestamp
        
        update(deltaTime: deltaTime)
    }
    
    // MARK: - 更新逻辑
    
    private func update(deltaTime: TimeInterval) {
        totalTime += deltaTime
        
        // 根据当前状态更新
        switch currentState {
        case .idle:
            break
            
        case .startup:
            updateStartup()
            
        case .loop:
            updateLoop()
            
        case .settle:
            updateSettle()
            
        case .paused:
            break
        }
        
        // 通知代理
        delegate?.stateMachine(self, didUpdateParams: currentParams)
    }
    
    private func updateStartup() {
        let duration = config.startupDuration
        let t = min(stateTime / duration, 1.0)
        
        // easeOutExpo: 1 - 2^(-10t)
        let eased = 1.0 - pow(2.0, -10.0 * t)
        
        currentParams = AnimationParams(
            intensity: Float(eased),
            speed: config.speed,
            noiseStrength: config.noiseStrength
        )
        
        // 检查是否完成
        if t >= 1.0 {
            stateStartTime = totalTime
            loopStartTime = totalTime
            transitionTo(.loop)
        }
    }
    
    private func updateLoop() {
        currentParams = AnimationParams(
            intensity: 1.0,
            speed: config.speed,
            noiseStrength: config.noiseStrength
        )
        
        // 检查自动稳定
        if config.autoSettle {
            let loopTime = totalTime - loopStartTime
            if loopTime >= config.autoSettleDelay {
                stateStartTime = totalTime
                transitionTo(.settle)
            }
        }
    }
    
    private func updateSettle() {
        let duration = config.settleDuration
        let t = min(stateTime / duration, 1.0)
        
        // 线性衰减
        let intensityDecay = config.settleToIdle ? Float(1.0 - t) : 1.0
        currentParams = AnimationParams(
            intensity: intensityDecay,
            speed: config.speed * Float(1.0 - t * 0.7),
            noiseStrength: config.noiseStrength * Float(1.0 - t * 0.8)
        )
        
        // settle 完成后的行为
        if t >= 1.0 {
            if config.settleToIdle {
                // 进入 idle 状态，完全停止动画
                stopDisplayLink()
                transitionTo(.idle)
            } else {
                // 回到 loop 继续循环
                stateStartTime = totalTime
                loopStartTime = totalTime
                transitionTo(.loop)
            }
        }
    }
    
    // MARK: - 状态转换
    
    private func transitionTo(_ newState: EnergyAnimationState) {
        guard newState != currentState else { return }
        
        let oldState = currentState
        currentState = newState
        
        // 重置状态时间
        if newState != .paused {
            // stateStartTime 已在调用处设置
        }
        
        // 特殊处理
        switch newState {
        case .idle:
            currentParams = AnimationParams(intensity: 0, speed: 0, noiseStrength: 0)
            
        case .paused:
            // 保持当前参数不变
            break
            
        default:
            break
        }
        
        delegate?.stateMachine(self, didTransitionTo: newState)
    }
}

// MARK: - 缓动函数

extension EnergyStateMachine {
    
    /// easeOutExpo
    static func easeOutExpo(_ t: Double) -> Double {
        return t == 1.0 ? 1.0 : 1.0 - pow(2.0, -10.0 * t)
    }
    
    /// easeInOutQuad
    static func easeInOutQuad(_ t: Double) -> Double {
        return t < 0.5 ? 2.0 * t * t : 1.0 - pow(-2.0 * t + 2.0, 2) / 2.0
    }
    
    /// easeOutQuad
    static func easeOutQuad(_ t: Double) -> Double {
        return 1.0 - (1.0 - t) * (1.0 - t)
    }
    
    /// easeInQuad
    static func easeInQuad(_ t: Double) -> Double {
        return t * t
    }
}
