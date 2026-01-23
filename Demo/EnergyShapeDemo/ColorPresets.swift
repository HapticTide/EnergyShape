//
//  ColorPresets.swift
//  EnergyShapeDemo
//
//  Created by Sun on 2026/1/21.
//  颜色预设定义
//

import EnergyShape
import UIKit

// MARK: - 颜色预设枚举

/// 预设颜色方案
enum ColorPreset: String, CaseIterable {
    case appleIntelligence = "Apple 智能"
    case oceanBlue = "蓝色"
    case fireRed = "红色"

    /// 获取颜色停靠点数组
    var colorStops: [ColorStop] {
        switch self {
        case .appleIntelligence:
            ColorPresets.appleIntelligenceColors
        case .oceanBlue:
            ColorPresets.oceanBlueColors
        case .fireRed:
            ColorPresets.fireRedColors
        }
    }

    /// 获取对应的完整配置
    var config: EnergyConfig {
        switch self {
        case .appleIntelligence:
            ColorPresets.appleIntelligenceConfig
        case .oceanBlue:
            ColorPresets.oceanBlueConfig
        case .fireRed:
            ColorPresets.fireRedConfig
        }
    }
}

// MARK: - 颜色预设集合

enum ColorPresets {
    // MARK: - Apple Intelligence 风格

    /// Apple Intelligence 官方配色
    /// 颜色值参考 Apple Intelligence 官方效果：
    /// BC82F3 (紫), F5B9EA (粉), 8D9FFF (蓝紫), FF6778 (红), FFBA71 (橙), C686FF (浅紫)
    static let appleIntelligenceColors: [ColorStop] = [
        ColorStop(position: 0.0, color: UIColor(hex: 0xbc82f3)), // 紫
        ColorStop(position: 0.17, color: UIColor(hex: 0xf5b9ea)), // 粉
        ColorStop(position: 0.33, color: UIColor(hex: 0x8d9fff)), // 蓝紫
        ColorStop(position: 0.50, color: UIColor(hex: 0xff6778)), // 红
        ColorStop(position: 0.67, color: UIColor(hex: 0xffba71)), // 橙
        ColorStop(position: 0.83, color: UIColor(hex: 0xc686ff)), // 浅紫
    ]

    /// Apple Intelligence 完整配置
    static var appleIntelligenceConfig: EnergyConfig = {
        var config = EnergyConfig()
        config.speed = 0.45 // 慢速流动
        config.noiseStrength = 0.05 // 减少噪声干扰
        config.noiseScale = 1.4 // 平滑条纹
        config.noiseOctaves = 2 // 减少噪声层数
        config.glowIntensity = 1.0 // 边框发光强度
        config.edgeBoost = 1.1 // 边缘增强

        // 边框发光参数（贴边效果）
        config.glowFalloff = 0.006 // 更细边框
        config.innerGlowIntensity = 0.35 // 内发光强度
        config.innerGlowRadius = 0.03 // 缩小内发光范围，保持贴边
        config.outerGlowIntensity = 0.0 // 关闭外发光
        config.outerGlowRadius = 0.0 // 无外发光
        config.colorFlowSpeed = 0.1 // 颜色流动速度

        // Bloom 效果（避免糊边）
        config.bloomEnabled = true
        config.bloomIntensity = 0.4 // 降低强度
        config.bloomThreshold = 0.5 // 提高阈值
        config.bloomBlurRadius = 7 // 适中模糊
        config.bloomScale = 0.5 // 提高分辨率
        config.colorStops = appleIntelligenceColors

        config.sdfQuality = .high

        config.startupDuration = 1.5
        config.settleDuration = 1.0
        return config
    }()

    // MARK: - 蓝色系（Ocean Blue）

    /// 蓝色系配色 - 纯蓝色调渐变
    /// 基于 #2F00FF 和 #2759FF 生成的相近蓝色
    static let oceanBlueColors: [ColorStop] = [
        ColorStop(position: 0.0, color: UIColor(hex: 0x2F00FF)), // 主蓝 1
        ColorStop(position: 0.2, color: UIColor(hex: 0x3020FF)), // 过渡蓝
        ColorStop(position: 0.4, color: UIColor(hex: 0x2840FF)), // 中间蓝
        ColorStop(position: 0.6, color: UIColor(hex: 0x2759FF)), // 主蓝 2
        ColorStop(position: 0.8, color: UIColor(hex: 0x2045FF)), // 深明亮蓝
        ColorStop(position: 1.0, color: UIColor(hex: 0x2F00FF)), // 主蓝 1（循环）
    ]

    /// 蓝色系完整配置
    static var oceanBlueConfig: EnergyConfig = {
        var config = EnergyConfig()
        config.speed = 0.6
        config.noiseStrength = 0.12
        config.noiseScale = 1.8
        config.noiseOctaves = 2
        config.glowIntensity = 1.0
        config.edgeBoost = 1.3

        config.glowFalloff = 0.02
        config.innerGlowIntensity = 0.5
        config.innerGlowRadius = 0.18
        config.outerGlowIntensity = 0.0
        config.outerGlowRadius = 0.0
        config.colorFlowSpeed = 0.18

        config.bloomEnabled = true
        config.bloomIntensity = 0.5
        config.bloomThreshold = 0.4
        config.bloomBlurRadius = 7
        config.colorStops = oceanBlueColors

        config.sdfQuality = .high

        config.startupDuration = 1.2
        config.settleDuration = 0.8
        return config
    }()

    // MARK: - 红色系（Fire Red）

    /// 红色系配色 - 纯红色调渐变
    /// 设计灵感：火焰、热情能量
    static let fireRedColors: [ColorStop] = [
        ColorStop(position: 0.0, color: UIColor(hex: 0x7f0000)), // 深红
        ColorStop(position: 0.25, color: UIColor(hex: 0xb71c1c)), // 暗红
        ColorStop(position: 0.5, color: UIColor(hex: 0xd32f2f)), // 红
        ColorStop(position: 0.75, color: UIColor(hex: 0xef5350)), // 亮红
        ColorStop(position: 1.0, color: UIColor(hex: 0x7f0000)), // 深红（循环）
    ]

    /// 红色系完整配置
    static var fireRedConfig: EnergyConfig = {
        var config = EnergyConfig()
        config.speed = 0.7
        config.noiseStrength = 0.15
        config.noiseScale = 2.0
        config.noiseOctaves = 3
        config.glowIntensity = 1.1
        config.edgeBoost = 1.4

        config.glowFalloff = 0.022
        config.innerGlowIntensity = 0.55
        config.innerGlowRadius = 0.22
        config.outerGlowIntensity = 0.0
        config.outerGlowRadius = 0.0
        config.colorFlowSpeed = 0.2

        config.bloomEnabled = true
        config.bloomIntensity = 0.55
        config.bloomThreshold = 0.38
        config.bloomBlurRadius = 7
        config.colorStops = fireRedColors

        config.sdfQuality = .high

        config.startupDuration = 1.0
        config.settleDuration = 0.8
        return config
    }()
}

// MARK: - UIColor 扩展

extension UIColor {
    /// 从 Hex 值创建颜色
    /// - Parameter hex: 十六进制颜色值，如 0xBC82F3
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xff) / 255.0
        let g = CGFloat((hex >> 8) & 0xff) / 255.0
        let b = CGFloat(hex & 0xff) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
