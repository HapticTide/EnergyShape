//
//  ShapeFactory.swift
//  EnergyShape
//
//  Created by Sun on 2026/1/21.
//  形状路径工厂 - 支持圆角矩形、圆形、椭圆、胶囊型
//

import UIKit

/// 形状类型枚举
enum ShapeType: Int, CaseIterable {
    case roundedRect = 0
    case circle = 1
    case ellipse = 2
    case capsule = 3

    var displayName: String {
        switch self {
        case .roundedRect: "圆角矩形"
        case .circle: "圆形"
        case .ellipse: "椭圆"
        case .capsule: "胶囊型"
        }
    }
}

/// 形状工厂
enum ShapeFactory {
    /// 创建指定类型的形状路径
    /// - Parameters:
    ///   - type: 形状类型
    ///   - size: 目标尺寸
    /// - Returns: CGPath
    static func createShape(type: ShapeType, size: CGSize) -> CGPath {
        switch type {
        case .roundedRect:
            createRoundedRect(size: size)
        case .circle:
            createCircle(size: size)
        case .ellipse:
            createEllipse(size: size)
        case .capsule:
            createCapsule(size: size)
        }
    }

    // MARK: - 程序生成的形状

    /// 圆角矩形
    private static func createRoundedRect(size: CGSize) -> CGPath {
        let cornerRadius = min(size.width, size.height) * 0.15
        return UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: size),
            cornerRadius: cornerRadius
        ).cgPath
    }

    /// 圆形
    private static func createCircle(size: CGSize) -> CGPath {
        let diameter = min(size.width, size.height)
        let origin = CGPoint(
            x: (size.width - diameter) / 2,
            y: (size.height - diameter) / 2
        )
        return UIBezierPath(
            ovalIn: CGRect(origin: origin, size: CGSize(width: diameter, height: diameter))
        ).cgPath
    }
    
    /// 椭圆
    private static func createEllipse(size: CGSize) -> CGPath {
        // 使用 80% 的宽度和 60% 的高度创建椭圆
        let width = size.width * 0.8
        let height = size.height * 0.6
        let origin = CGPoint(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2
        )
        return UIBezierPath(
            ovalIn: CGRect(origin: origin, size: CGSize(width: width, height: height))
        ).cgPath
    }
    
    /// 胶囊型（水平方向）
    private static func createCapsule(size: CGSize) -> CGPath {
        // 胶囊宽高比 3:1
        let capsuleWidth = min(size.width * 0.9, size.height * 2.5)
        let capsuleHeight = capsuleWidth / 2.5
        let origin = CGPoint(
            x: (size.width - capsuleWidth) / 2,
            y: (size.height - capsuleHeight) / 2
        )
        let cornerRadius = capsuleHeight / 2
        return UIBezierPath(
            roundedRect: CGRect(origin: origin, size: CGSize(width: capsuleWidth, height: capsuleHeight)),
            cornerRadius: cornerRadius
        ).cgPath
    }
}
