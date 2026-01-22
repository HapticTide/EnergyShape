//
//  ShapeType.swift
//  EnergyShape
//
//  Created by Sun on 2026/1/21.
//  形状类型定义 - 用于选择 SDF 计算策略
//

import CoreGraphics

// MARK: - 解析形状类型

/// 可以使用数学公式计算 SDF 的形状
/// 这些形状在 GPU Shader 中直接计算，零延迟、完美平滑
public enum AnalyticShape: Equatable {
    /// 圆角矩形
    /// - Parameters:
    ///   - rect: 矩形边界（相对于渲染区域的归一化坐标）
    ///   - cornerRadius: 圆角半径（相对于较小边的比例，0-0.5）
    case roundedRect(rect: CGRect, cornerRadius: CGFloat)
    
    /// 圆形
    /// - Parameters:
    ///   - center: 圆心（归一化坐标 0-1）
    ///   - radius: 半径（相对于较小边的比例）
    case circle(center: CGPoint, radius: CGFloat)
    
    /// 椭圆
    /// - Parameters:
    ///   - rect: 椭圆边界矩形（归一化坐标）
    case ellipse(rect: CGRect)
    
    /// 胶囊形（两端圆角的矩形）
    /// - Parameters:
    ///   - rect: 边界矩形（归一化坐标）
    ///   - isVertical: 是否垂直方向（决定哪个方向是圆角端）
    case capsule(rect: CGRect, isVertical: Bool)
}

// MARK: - 内部形状类型

/// 内部使用的形状类型，决定 SDF 计算策略
enum InternalShapeType {
    /// 解析形状 - 使用数学公式在 Shader 中实时计算
    /// 优点：零延迟、完美平滑、无内存占用
    case analytic(AnalyticShape)
    
    /// 自定义路径 - 使用 GPU JFA 算法计算 SDF 纹理
    /// 优点：支持任意 CGPath
    case customPath(CGPath)
}

// MARK: - 形状参数（传递给 Shader）

/// 解析形状参数（与 Shader 中的 ShapeParams 对应）
/// 用于在 GPU 中实时计算 SDF
struct AnalyticShapeParams {
    /// 形状类型 (0=圆角矩形, 1=圆形, 2=椭圆, 3=胶囊)
    var shapeType: Int32 = 0
    
    /// 渲染区域尺寸（像素）
    var viewSize: SIMD2<Float> = .zero
    
    /// 形状中心（归一化坐标 0-1）
    var center: SIMD2<Float> = SIMD2<Float>(0.5, 0.5)
    
    /// 半尺寸（归一化坐标，用于矩形/椭圆）
    var halfSize: SIMD2<Float> = SIMD2<Float>(0.5, 0.5)
    
    /// 圆角半径（归一化坐标）
    var cornerRadius: Float = 0.0
    
    /// 圆形/椭圆半径（归一化坐标）
    var radius: SIMD2<Float> = SIMD2<Float>(0.5, 0.5)
    
    /// 是否垂直胶囊
    var isVertical: Int32 = 0
    
    /// 对齐填充
    var padding: Int32 = 0
    
    /// 从 AnalyticShape 创建参数
    static func from(_ shape: AnalyticShape, viewSize: CGSize) -> AnalyticShapeParams {
        var params = AnalyticShapeParams()
        params.viewSize = SIMD2<Float>(Float(viewSize.width), Float(viewSize.height))
        
        switch shape {
        case .roundedRect(let rect, let cornerRadius):
            params.shapeType = 0
            params.center = SIMD2<Float>(
                Float(rect.midX),
                Float(rect.midY)
            )
            params.halfSize = SIMD2<Float>(
                Float(rect.width / 2),
                Float(rect.height / 2)
            )
            // cornerRadius 是相对于较小边的比例
            let minDim = min(rect.width, rect.height)
            params.cornerRadius = Float(cornerRadius * minDim)
            
        case .circle(let center, let radius):
            params.shapeType = 1
            params.center = SIMD2<Float>(Float(center.x), Float(center.y))
            let minDim = min(viewSize.width, viewSize.height)
            let r = Float(radius * minDim / viewSize.width) // 归一化到视图宽度
            params.radius = SIMD2<Float>(r, Float(radius * minDim / viewSize.height))
            
        case .ellipse(let rect):
            params.shapeType = 2
            params.center = SIMD2<Float>(
                Float(rect.midX),
                Float(rect.midY)
            )
            params.radius = SIMD2<Float>(
                Float(rect.width / 2),
                Float(rect.height / 2)
            )
            
        case .capsule(let rect, let isVertical):
            params.shapeType = 3
            params.center = SIMD2<Float>(
                Float(rect.midX),
                Float(rect.midY)
            )
            params.halfSize = SIMD2<Float>(
                Float(rect.width / 2),
                Float(rect.height / 2)
            )
            params.isVertical = isVertical ? 1 : 0
        }
        
        return params
    }
}
