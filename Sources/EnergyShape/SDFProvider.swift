//
//  SDFProvider.swift
//  EnergyShape
//
//  Created by Sun on 2026/1/21.
//  SDF 提供者协议 - 统一解析 SDF 和纹理 SDF 的接口
//

import CoreGraphics
import Metal

// MARK: - SDF 模式

/// SDF 计算模式
public enum SDFMode {
    /// 解析模式：使用数学公式在 Shader 中实时计算
    /// 适用于圆角矩形、圆形等简单形状
    case analytic
    
    /// 纹理模式：使用预计算的 SDF 纹理
    /// 适用于任意复杂路径
    case texture
}

// MARK: - SDF 结果

/// SDF 计算结果
enum SDFResult {
    /// 解析 SDF 结果（包含形状参数）
    case analytic(AnalyticShapeParams)
    
    /// 纹理 SDF 结果（包含 SDF 纹理）
    case texture(MTLTexture)
    
    /// SDF 模式
    var mode: SDFMode {
        switch self {
        case .analytic: return .analytic
        case .texture: return .texture
        }
    }
    
    /// 解析形状参数（仅解析模式有效）
    var analyticParams: AnalyticShapeParams? {
        if case .analytic(let params) = self {
            return params
        }
        return nil
    }
    
    /// SDF 纹理（仅纹理模式有效）
    var sdfTexture: MTLTexture? {
        if case .texture(let texture) = self {
            return texture
        }
        return nil
    }
}

// MARK: - SDFProvider 协议

/// SDF 提供者协议
/// 负责计算或生成 SDF（有符号距离场）
protocol SDFProvider {
    /// SDF 计算模式
    var mode: SDFMode { get }
    
    /// 准备 SDF（可能是异步的）
    /// - Parameters:
    ///   - shapeType: 内部形状类型
    ///   - viewSize: 视图尺寸
    ///   - scale: 屏幕缩放因子
    ///   - completion: 完成回调
    func prepareSDF(
        for shapeType: InternalShapeType,
        viewSize: CGSize,
        scale: CGFloat,
        completion: @escaping (Result<SDFResult, Error>) -> Void
    )
    
    /// 取消当前计算
    func cancel()
}

// MARK: - 错误类型

/// SDF 计算错误
enum SDFError: Error, LocalizedError {
    case invalidShape
    case computeFailed(String)
    case textureCreationFailed
    case deviceNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .invalidShape:
            return "无效的形状参数"
        case .computeFailed(let reason):
            return "SDF 计算失败: \(reason)"
        case .textureCreationFailed:
            return "无法创建 SDF 纹理"
        case .deviceNotAvailable:
            return "Metal 设备不可用"
        }
    }
}
