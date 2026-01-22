//
//  PathAnalyzer.swift
//  EnergyShape
//
//  Created by Sun on 2026/1/21.
//  路径智能分析器 - 判断 CGPath 是否为可解析形状
//

import CoreGraphics
import UIKit

// MARK: - PathAnalyzer

/// CGPath 分析器
/// 尝试将任意 CGPath 识别为可解析的简单形状
/// 如果识别成功，可以使用数学 SDF 公式避免纹理计算
enum PathAnalyzer {
    // MARK: - 公开方法
    
    /// 分析 CGPath，判断是否为可解析形状
    /// - Parameters:
    ///   - path: 待分析的路径
    ///   - viewSize: 视图尺寸（用于归一化坐标）
    /// - Returns: 内部形状类型
    static func analyze(_ path: CGPath, viewSize: CGSize) -> InternalShapeType {
        let bounds = path.boundingBox
        
        // 防止无效边界
        guard bounds.width > 0, bounds.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            return .customPath(path)
        }
        
        // 尝试检测各种形状
        
        // 1. 检测圆形
        if let circle = detectCircle(path, bounds: bounds, viewSize: viewSize) {
            return .analytic(circle)
        }
        
        // 2. 检测椭圆
        if let ellipse = detectEllipse(path, bounds: bounds, viewSize: viewSize) {
            return .analytic(ellipse)
        }
        
        // 3. 检测圆角矩形
        if let roundedRect = detectRoundedRect(path, bounds: bounds, viewSize: viewSize) {
            return .analytic(roundedRect)
        }
        
        // 4. 检测胶囊
        if let capsule = detectCapsule(path, bounds: bounds, viewSize: viewSize) {
            return .analytic(capsule)
        }
        
        // 无法识别，使用自定义路径
        return .customPath(path)
    }
    
    /// 强制指定使用解析形状（跳过检测）
    /// - Parameters:
    ///   - shape: 解析形状类型
    /// - Returns: 内部形状类型
    static func forceAnalytic(_ shape: AnalyticShape) -> InternalShapeType {
        .analytic(shape)
    }
    
    // MARK: - 形状检测
    
    /// 检测圆形
    /// 条件：边界是正方形，路径面积接近 π*r²
    private static func detectCircle(
        _ path: CGPath,
        bounds: CGRect,
        viewSize: CGSize
    ) -> AnalyticShape? {
        // 检查是否接近正方形
        let aspectRatio = bounds.width / bounds.height
        guard abs(aspectRatio - 1.0) < 0.05 else { return nil }
        
        // 计算路径面积（近似）
        let pathArea = approximateArea(of: path)
        let expectedCircleArea = .pi * pow(bounds.width / 2, 2)
        
        // 允许 5% 的误差
        let areaRatio = pathArea / expectedCircleArea
        guard abs(areaRatio - 1.0) < 0.05 else { return nil }
        
        // 归一化坐标
        let center = CGPoint(
            x: bounds.midX / viewSize.width,
            y: bounds.midY / viewSize.height
        )
        let radius = bounds.width / 2 / min(viewSize.width, viewSize.height)
        
        return .circle(center: center, radius: radius)
    }
    
    /// 检测椭圆
    /// 条件：路径面积接近 π*a*b
    private static func detectEllipse(
        _ path: CGPath,
        bounds: CGRect,
        viewSize: CGSize
    ) -> AnalyticShape? {
        let a = bounds.width / 2
        let b = bounds.height / 2
        
        let pathArea = approximateArea(of: path)
        let expectedEllipseArea = .pi * a * b
        
        // 允许 5% 的误差
        let areaRatio = pathArea / expectedEllipseArea
        guard abs(areaRatio - 1.0) < 0.05 else { return nil }
        
        // 进一步验证：椭圆上的点应满足方程
        // 但这个检测可能误判矩形为椭圆，所以优先级低于圆形
        
        // 如果宽高比接近 1，应该已经被圆形检测捕获
        let aspectRatio = bounds.width / bounds.height
        guard abs(aspectRatio - 1.0) >= 0.05 else { return nil }
        
        // 归一化坐标
        let rect = CGRect(
            x: bounds.minX / viewSize.width,
            y: bounds.minY / viewSize.height,
            width: bounds.width / viewSize.width,
            height: bounds.height / viewSize.height
        )
        
        return .ellipse(rect: rect)
    }
    
    /// 检测圆角矩形
    /// 这是最常见的情况，使用元素分析来检测
    private static func detectRoundedRect(
        _ path: CGPath,
        bounds: CGRect,
        viewSize: CGSize
    ) -> AnalyticShape? {
        // 解析路径元素
        var elements: [PathElement] = []
        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                elements.append(.move(element.points[0]))
            case .addLineToPoint:
                elements.append(.line(element.points[0]))
            case .addQuadCurveToPoint:
                elements.append(.quadCurve(element.points[0], element.points[1]))
            case .addCurveToPoint:
                elements.append(.cubicCurve(element.points[0], element.points[1], element.points[2]))
            case .closeSubpath:
                elements.append(.close)
            @unknown default:
                break
            }
        }
        
        // 圆角矩形通常由 4 条直线 + 4 条曲线（或更多弧线段）组成
        // UIBezierPath(roundedRect:) 使用曲线绘制圆角
        
        let lineCount = elements.filter { $0.isLine }.count
        let curveCount = elements.filter { $0.isCurve }.count
        
        // 典型的圆角矩形：4 条边 + 4 个圆角
        // 每个圆角可能是 1 个三次曲线或多个二次曲线
        guard lineCount >= 4 || (lineCount == 0 && curveCount >= 8) else { return nil }
        
        // 计算面积比（圆角矩形的面积比纯矩形小）
        let pathArea = approximateArea(of: path)
        let rectArea = bounds.width * bounds.height
        let areaRatio = pathArea / rectArea
        
        // 圆角矩形的面积应在 0.7-1.0 之间（取决于圆角大小）
        guard areaRatio > 0.7 && areaRatio <= 1.001 else { return nil }
        
        // 估算圆角半径
        // 面积损失 ≈ (4 - π) * r²，其中 r 是圆角半径
        let areaLoss = rectArea - pathArea
        let estimatedRadius = sqrt(areaLoss / (4 - .pi))
        
        // 归一化
        let minDim = min(bounds.width, bounds.height)
        let normalizedRadius = min(estimatedRadius / minDim, 0.5)
        
        let rect = CGRect(
            x: bounds.minX / viewSize.width,
            y: bounds.minY / viewSize.height,
            width: bounds.width / viewSize.width,
            height: bounds.height / viewSize.height
        )
        
        return .roundedRect(rect: rect, cornerRadius: normalizedRadius)
    }
    
    /// 检测胶囊形
    /// 条件：两端完全圆角的矩形
    private static func detectCapsule(
        _ path: CGPath,
        bounds: CGRect,
        viewSize: CGSize
    ) -> AnalyticShape? {
        // 胶囊形的特征：
        // 1. 宽高比显著不同
        // 2. 较短边完全是圆角
        
        let aspectRatio = bounds.width / bounds.height
        guard abs(aspectRatio - 1.0) > 0.3 else { return nil }
        
        let isVertical = bounds.height > bounds.width
        let minDim = min(bounds.width, bounds.height)
        
        // 胶囊的面积 = 矩形面积 - 2个角的损失面积 + 2个半圆
        // ≈ 矩形面积 - (4-π)*r² + 2*π*r²/2 = 矩形面积 + (π-4+π)*r²/2
        // 简化：如果较短边完全是圆角，面积接近某个特定比例
        
        let pathArea = approximateArea(of: path)
        let rectArea = bounds.width * bounds.height
        
        // 完全胶囊的面积 = (长边-短边)*短边 + π*(短边/2)²
        let longDim = max(bounds.width, bounds.height)
        let expectedCapsuleArea = (longDim - minDim) * minDim + .pi * pow(minDim / 2, 2)
        
        let areaRatio = pathArea / expectedCapsuleArea
        guard abs(areaRatio - 1.0) < 0.1 else { return nil }
        
        let rect = CGRect(
            x: bounds.minX / viewSize.width,
            y: bounds.minY / viewSize.height,
            width: bounds.width / viewSize.width,
            height: bounds.height / viewSize.height
        )
        
        return .capsule(rect: rect, isVertical: isVertical)
    }
    
    // MARK: - 辅助方法
    
    /// 近似计算路径面积（使用积分方法）
    private static func approximateArea(of path: CGPath) -> CGFloat {
        var area: CGFloat = 0
        var firstPoint: CGPoint?
        var currentPoint: CGPoint = .zero
        
        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                currentPoint = element.points[0]
                if firstPoint == nil {
                    firstPoint = currentPoint
                }
                
            case .addLineToPoint:
                let nextPoint = element.points[0]
                // Shoelace formula
                area += (currentPoint.x * nextPoint.y - nextPoint.x * currentPoint.y)
                currentPoint = nextPoint
                
            case .addQuadCurveToPoint, .addCurveToPoint:
                // 对于曲线，简化为直线近似
                let endPoint = element.type == .addQuadCurveToPoint
                    ? element.points[1]
                    : element.points[2]
                area += (currentPoint.x * endPoint.y - endPoint.x * currentPoint.y)
                currentPoint = endPoint
                
            case .closeSubpath:
                if let first = firstPoint {
                    area += (currentPoint.x * first.y - first.x * currentPoint.y)
                }
                
            @unknown default:
                break
            }
        }
        
        return abs(area) / 2
    }
}

// MARK: - PathElement

/// 路径元素类型（内部使用）
private enum PathElement {
    case move(CGPoint)
    case line(CGPoint)
    case quadCurve(CGPoint, CGPoint)
    case cubicCurve(CGPoint, CGPoint, CGPoint)
    case close
    
    var isLine: Bool {
        if case .line = self { return true }
        return false
    }
    
    var isCurve: Bool {
        switch self {
        case .quadCurve, .cubicCurve:
            return true
        default:
            return false
        }
    }
}
