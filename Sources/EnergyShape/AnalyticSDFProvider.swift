//
//  AnalyticSDFProvider.swift
//  EnergyShape
//
//  Created by Sun on 2026/1/21.
//  解析 SDF 提供者 - 使用数学公式计算 SDF
//

import CoreGraphics
import Metal

// MARK: - AnalyticSDFProvider

/// 解析 SDF 提供者
/// 对于简单形状（圆角矩形、圆形等），直接计算形状参数
/// 在 Shader 中使用数学公式实时计算 SDF
/// 
/// 优点：
/// - 零延迟：无需预计算
/// - 完美平滑：数学精确，无锯齿
/// - 零内存：不需要 SDF 纹理
final class AnalyticSDFProvider: SDFProvider {
    // MARK: - 属性
    
    let mode: SDFMode = .analytic
    
    /// 当前解析形状
    private var currentShape: AnalyticShape?
    
    /// 当前形状参数
    private(set) var currentParams: AnalyticShapeParams?
    
    // MARK: - 初始化
    
    init() {}
    
    // MARK: - SDFProvider
    
    func prepareSDF(
        for shapeType: InternalShapeType,
        viewSize: CGSize,
        scale: CGFloat,
        completion: @escaping (Result<SDFResult, Error>) -> Void
    ) {
        switch shapeType {
        case .analytic(let shape):
            currentShape = shape
            let params = AnalyticShapeParams.from(shape, viewSize: viewSize)
            currentParams = params
            completion(.success(.analytic(params)))
            
        case .customPath:
            // 解析 SDF 不支持自定义路径
            completion(.failure(SDFError.invalidShape))
        }
    }
    
    func cancel() {
        // 解析 SDF 是同步计算，无需取消
    }
    
    // MARK: - 便捷方法
    
    /// 快速更新形状（同步）
    /// - Parameters:
    ///   - shape: 解析形状
    ///   - viewSize: 视图尺寸
    /// - Returns: 形状参数
    func updateShape(_ shape: AnalyticShape, viewSize: CGSize) -> AnalyticShapeParams {
        currentShape = shape
        let params = AnalyticShapeParams.from(shape, viewSize: viewSize)
        currentParams = params
        return params
    }
    
    /// 从 CGPath 尝试创建解析形状
    /// - Parameters:
    ///   - path: CGPath
    ///   - viewSize: 视图尺寸
    /// - Returns: 形状参数（如果路径可解析）
    func tryCreateFromPath(_ path: CGPath, viewSize: CGSize) -> AnalyticShapeParams? {
        let shapeType = PathAnalyzer.analyze(path, viewSize: viewSize)
        
        switch shapeType {
        case .analytic(let shape):
            return updateShape(shape, viewSize: viewSize)
        case .customPath:
            return nil
        }
    }
}
