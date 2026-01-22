//
//  EnergyConfig.swift
//  EnergyShape
//
//  Created by Sun on 2026/1/21.
//  能量动画配置参数
//

import UIKit

// MARK: - 主配置结构

/// 能量动画效果的完整配置
public struct EnergyConfig {
    // MARK: - 动画参数

    /// 流动速度 [0.1 ~ 3.0]，默认 1.0
    public var speed: Float = 1.0

    /// 噪声强度 [0 ~ 1.0]，默认 0.3
    /// 控制能量流动的随机扰动程度
    public var noiseStrength: Float = 0.3

    /// 相位缩放 [0.5 ~ 5.0]，默认 2.0
    /// 影响流动条纹的密度
    public var phaseScale: Float = 2.0

    /// 噪声 octaves 数量 [2 ~ 4]，默认 3
    /// 更多层次 = 更丰富细节，但性能开销更大
    public var noiseOctaves: Int = 3

    // MARK: - 视觉效果

    /// 发光强度 [0 ~ 2.0]，默认 0.5
    public var glowIntensity: Float = 0.5

    /// 边缘增强系数 [0 ~ 3.0]，默认 1.2
    public var edgeBoost: Float = 1.2

    // MARK: - 边框发光参数

    /// 边框宽度 [0.005 ~ 0.1]，默认 0.008（相对于视图尺寸的比例）
    /// 值越大边框越粗，全屏场景建议使用较小值以保持贴边感
    public var borderWidth: Float = 0.008

    /// 内发光强度 [0 ~ 1.0]，默认 0.35
    /// 控制边框向形状内部的发光扩散强度
    public var innerGlowIntensity: Float = 0.35

    /// 内发光范围 [0.01 ~ 0.5]，默认 0.04（相对于视图尺寸的比例）
    /// 值越大内发光扩散越远，全屏场景建议使用较小值（10~20px 范围）
    public var innerGlowRange: Float = 0.04

    /// 外发光强度 [0 ~ 1.0]，默认 0.0
    /// 控制边框向形状外部的发光扩散强度（全屏贴边效果建议关闭）
    public var outerGlowIntensity: Float = 0.0

    /// 外发光范围 [0.01 ~ 0.3]，默认 0.0（相对于视图尺寸的比例）
    public var outerGlowRange: Float = 0.0

    /// 颜色流动速度 [0.05 ~ 1.0]，默认 0.2
    /// 颜色沿边框流动的速度
    public var colorFlowSpeed: Float = 0.2

    // MARK: - IDW 弥散参数（DiffusionKit 风格）
    
    /// IDW 偏置值 [0.001 ~ 0.5]，默认 0.01
    /// 控制颜色扩散的模糊程度，越小边界越锐利，越大越模糊
    public var diffusionBias: Float = 0.01
    
    /// IDW 距离衰减指数 [1.0 ~ 4.0]，默认 2.0
    /// 控制颜色边界的锐利度，越大边界越明显
    public var diffusionPower: Float = 2.0
    
    /// 颜色点数量 [4 ~ 8]，默认 6
    /// 沿边缘分布的颜色点数量，更多点产生更丰富的混合效果
    public var colorPointCount: Int = 6
    
    /// 颜色点移动速度 [0.5 ~ 5.0]，默认 2.0
    /// 颜色点沿边缘移动的速度，影响弥散流动感
    public var colorPointSpeed: Float = 2.0

    /// 是否启用 Bloom 效果
    public var bloomEnabled: Bool = true

    /// Bloom 强度 [0 ~ 1.0]，默认 0.4（减小以避免糊边）
    public var bloomIntensity: Float = 0.4

    /// Bloom 阈值 [0 ~ 1.0]，默认 0.5（提高以减少雾化）
    /// 亮度超过此值的像素才会产生 Bloom
    public var bloomThreshold: Float = 0.5

    /// Bloom 模糊半径 [3, 5, 7, 9]，默认 7（适中模糊）
    public var bloomBlurRadius: Int = 7

    // MARK: - 颜色配置

    /// 颜色渐变停靠点（外部可配置）
    /// 默认为空数组，使用者需要自行设置颜色
    public var colorStops: [ColorStop] = []

    /// 是否使用 LUT 纹理映射颜色（强烈推荐开启）
    public var useLUTTexture: Bool = true

    /// 是否启用抖动抗色带
    public var ditherEnabled: Bool = true

    // MARK: - 动画状态机

    /// 启动阶段持续时间（秒）
    public var startupDuration: TimeInterval = 1.2

    /// 稳定阶段持续时间（秒）
    public var settleDuration: TimeInterval = 0.8

    /// 是否在循环一段时间后自动进入稳定状态
    public var autoSettle: Bool = false

    /// 自动稳定前的循环时间（秒）
    public var autoSettleDelay: TimeInterval = 10.0

    /// settle 完成后是否进入 idle 状态（而非回到 loop）
    /// 设为 true 时，调用 settle() 后动画会完全停止
    public var settleToIdle: Bool = false

    // MARK: - 性能配置

    /// 最大纹理尺寸（像素）
    public var maxTextureSize: Int = 2048

    /// 是否启用 SDF（边缘效果更好）
    public var sdfEnabled: Bool = true

    /// SDF 质量等级
    public var sdfQuality: SDFQuality = .medium

    /// Bloom 纹理分辨率比例 [0.25, 0.5]，默认 0.25
    public var bloomResolutionScale: Float = 0.25

    // MARK: - 背景模式

    /// 背景适配模式
    public var backgroundMode: BackgroundMode = .transparent

    // MARK: - 默认配置

    /// 默认配置
    public static let `default` = EnergyConfig()

    // MARK: - 初始化

    public init() {}

    // MARK: - 参数验证

    /// 验证并修正参数到有效范围
    public mutating func validate() {
        speed = max(0.1, min(3.0, speed))
        noiseStrength = max(0.0, min(1.0, noiseStrength))
        phaseScale = max(0.5, min(5.0, phaseScale))
        noiseOctaves = max(2, min(4, noiseOctaves))
        glowIntensity = max(0.0, min(2.0, glowIntensity))
        edgeBoost = max(0.0, min(3.0, edgeBoost))

        // 边框发光参数验证
        borderWidth = max(0.005, min(0.1, borderWidth))
        innerGlowIntensity = max(0.0, min(1.0, innerGlowIntensity))
        innerGlowRange = max(0.01, min(0.5, innerGlowRange))
        outerGlowIntensity = max(0.0, min(1.0, outerGlowIntensity))
        outerGlowRange = max(0.01, min(0.1, outerGlowRange))  // 缩小范围上限
        colorFlowSpeed = max(0.05, min(1.0, colorFlowSpeed))
        
        // IDW 弥散参数验证
        diffusionBias = max(0.001, min(0.5, diffusionBias))
        diffusionPower = max(1.0, min(4.0, diffusionPower))
        colorPointCount = max(4, min(8, colorPointCount))
        colorPointSpeed = max(0.5, min(5.0, colorPointSpeed))

        bloomIntensity = max(0.0, min(1.0, bloomIntensity))
        bloomThreshold = max(0.0, min(1.0, bloomThreshold))
        bloomBlurRadius = [3, 5, 7, 9].min(by: { abs($0 - bloomBlurRadius) < abs($1 - bloomBlurRadius) }) ?? 5
        maxTextureSize = max(256, min(4096, maxTextureSize))
        bloomResolutionScale = max(0.25, min(0.5, bloomResolutionScale))
    }
}

// MARK: - 辅助类型

/// 颜色渐变停靠点
public struct ColorStop: Equatable {
    /// 位置 [0 ~ 1]
    public var position: Float
    /// 颜色
    public var color: UIColor

    public init(position: Float, color: UIColor) {
        self.position = max(0, min(1, position))
        self.color = color
    }

    /// 获取 RGBA 分量
    public var rgba: (r: Float, g: Float, b: Float, a: Float) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Float(r), Float(g), Float(b), Float(a))
    }
}

/// SDF 质量等级
public enum SDFQuality: Int, CaseIterable {
    case low = 0 // 1/4 分辨率，CPU 简版
    case medium = 1 // 1/2 分辨率，CPU EDT
    case high = 2 // 全分辨率，GPU JFA（如支持）

    /// 分辨率缩放因子
    public var resolutionScale: Float {
        switch self {
        case .low: 0.25
        case .medium: 0.5
        case .high: 1.0
        }
    }
}

/// 背景适配模式
public enum BackgroundMode: Equatable {
    case transparent // 透明背景
    case dark // 深色背景（默认效果最佳）
    case light // 浅色背景（自动调整 glow）
    case custom(UIColor) // 自定义背景色

    /// 获取背景颜色
    public var color: UIColor? {
        switch self {
        case .transparent: nil
        case .dark: .black
        case .light: .white
        case let .custom(color): color
        }
    }
}

/// 形状适配模式
public enum ShapeContentMode: Equatable {
    case aspectFit // 完整显示，保持比例，可能有留白
    case aspectFill // 填满视图，保持比例，可能裁切
    case center // 原始大小居中显示
    case scaleToFill // 拉伸填满（允许变形）
    case custom(CGAffineTransform) // 自定义变换矩阵
}

/// 动画状态
public enum EnergyAnimationState: Equatable {
    case idle // 空闲，无渲染
    case startup // 启动中，intensity 0→1
    case loop // 循环流动
    case settle // 稳定中，降低 speed/noise
    case paused // 暂停，保持当前帧
}

// MARK: - 性能统计

/// 性能统计数据
public struct EnergyPerformanceStats {
    /// 当前帧率
    public var currentFPS: Double = 0
    /// 平均帧率
    public var averageFPS: Double = 0
    /// GPU 每帧耗时（ms）
    public var gpuTime: Double = 0
    /// CPU 每帧耗时（ms）
    public var cpuTime: Double = 0
    /// 纹理内存占用（bytes）
    public var textureMemoryBytes: Int = 0
    /// Mask 重建次数
    public var maskRebuildCount: Int = 0
    /// SDF 模式（analytic = 解析形状，texture = 纹理 SDF）
    public var sdfMode: String = "analytic"

    public init() {}

    // MARK: - 性能评估

    /// 60 FPS 的帧预算（16.67ms）
    public static let frameBudget60FPS: Double = 16.67
    /// 120 FPS 的帧预算（8.33ms）
    public static let frameBudget120FPS: Double = 8.33

    /// 总帧时间（GPU + CPU）
    public var totalFrameTime: Double {
        gpuTime + cpuTime
    }

    /// 帧预算使用百分比（基于 60 FPS）
    public var frameBudgetUsage: Double {
        (totalFrameTime / Self.frameBudget60FPS) * 100
    }

    /// 性能等级
    public enum PerformanceGrade: String {
        case excellent   // < 25% 帧预算
        case good        // 25-50% 帧预算
        case normal      // 50-75% 帧预算
        case warning     // 75-100% 帧预算
        case critical    // > 100% 帧预算
    }

    /// 当前性能等级
    public var performanceGrade: PerformanceGrade {
        let usage = frameBudgetUsage
        switch usage {
        case ..<25: return .excellent
        case 25 ..< 50: return .good
        case 50 ..< 75: return .normal
        case 75 ..< 100: return .warning
        default: return .critical
        }
    }

    /// 格式化内存大小
    public func formatMemory(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
        }
    }

    /// 纯文本格式化显示（不含 emoji，颜色在 View 层处理）
    public var description: String {
        let fpsText = String(format: "%.0f", currentFPS)
        let avgFpsText = String(format: "%.0f", averageFPS)
        let gpuText = String(format: "%.2f", gpuTime)
        let cpuText = String(format: "%.2f", cpuTime)
        let totalText = String(format: "%.2f", totalFrameTime)
        let budgetText = String(format: "%.0f%%", frameBudgetUsage)

        return """
        FPS: \(fpsText) (平均 \(avgFpsText))
        帧耗时: \(totalText)ms [\(budgetText)]
        GPU: \(gpuText)ms | CPU: \(cpuText)ms
        """
    }
}

// MARK: - 错误类型

/// 能量视图错误
public enum EnergyShapeError: Error, LocalizedError {
    case metalNotSupported // 设备不支持 Metal
    case deviceCreationFailed // MTLDevice 创建失败
    case shaderCompilationFailed(String) // Shader 编译失败
    case textureCreationFailed // 纹理创建失败
    case invalidPath // 无效的 CGPath
    case outOfMemory // 内存不足
    case renderingFailed(String) // 渲染失败

    public var errorDescription: String? {
        switch self {
        case .metalNotSupported:
            "此设备不支持 Metal"
        case .deviceCreationFailed:
            "无法创建 Metal 设备"
        case let .shaderCompilationFailed(message):
            "Shader 编译失败: \(message)"
        case .textureCreationFailed:
            "无法创建纹理"
        case .invalidPath:
            "无效的 CGPath"
        case .outOfMemory:
            "内存不足"
        case let .renderingFailed(message):
            "渲染失败: \(message)"
        }
    }
}

// MARK: - Fallback 模式

/// 降级模式
public enum FallbackMode {
    case none // 不降级，直接报错
    case coreAnimation // 降级到 CA 简化效果
    case staticImage // 降级到静态图片
}

// MARK: - Delegate 协议

/// 能量视图代理协议
public protocol EnergyShapeViewDelegate: AnyObject {
    /// 性能统计更新
    func energyShapeView(_ view: EnergyShapeView, didUpdateStats stats: EnergyPerformanceStats)
    /// 发生错误
    func energyShapeView(_ view: EnergyShapeView, didFailWithError error: Error)
    /// 动画状态变化
    func energyShapeView(_ view: EnergyShapeView, didChangeState state: EnergyAnimationState)
}

// MARK: - Delegate 默认实现

public extension EnergyShapeViewDelegate {
    func energyShapeView(_ view: EnergyShapeView, didUpdateStats stats: EnergyPerformanceStats) {}
    func energyShapeView(_ view: EnergyShapeView, didFailWithError error: Error) {}
    func energyShapeView(_ view: EnergyShapeView, didChangeState state: EnergyAnimationState) {}
}
