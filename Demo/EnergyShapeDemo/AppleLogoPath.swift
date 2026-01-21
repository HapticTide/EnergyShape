//
//  AppleLogoPath.swift
//  EnergyShapeKit
//
//  Created by Sun on 2026/1/21.
//  Apple Logo CGPath 数据（仅用于 Demo）
//

import UIKit

/// Apple Logo 路径生成器
/// 注意：此路径仅用于演示目的
enum AppleLogoPath {
    
    /// 创建 Apple Logo 路径
    /// - Parameter size: 目标尺寸
    /// - Returns: CGPath
    static func create(size: CGSize = CGSize(width: 200, height: 240)) -> CGPath {
        let path = UIBezierPath()
        
        // 基准尺寸
        let baseWidth: CGFloat = 200
        let baseHeight: CGFloat = 240
        
        // 缩放因子
        let scaleX = size.width / baseWidth
        let scaleY = size.height / baseHeight
        
        // 苹果主体 - 使用贝塞尔曲线近似
        // 左半边
        path.move(to: CGPoint(x: 100 * scaleX, y: 50 * scaleY))
        
        // 顶部凹陷（咬掉的部分）
        path.addCurve(
            to: CGPoint(x: 70 * scaleX, y: 70 * scaleY),
            controlPoint1: CGPoint(x: 90 * scaleX, y: 50 * scaleY),
            controlPoint2: CGPoint(x: 80 * scaleX, y: 55 * scaleY)
        )
        
        // 左上曲线
        path.addCurve(
            to: CGPoint(x: 20 * scaleX, y: 100 * scaleY),
            controlPoint1: CGPoint(x: 45 * scaleX, y: 70 * scaleY),
            controlPoint2: CGPoint(x: 20 * scaleX, y: 80 * scaleY)
        )
        
        // 左侧曲线
        path.addCurve(
            to: CGPoint(x: 30 * scaleX, y: 180 * scaleY),
            controlPoint1: CGPoint(x: 20 * scaleX, y: 130 * scaleY),
            controlPoint2: CGPoint(x: 20 * scaleX, y: 160 * scaleY)
        )
        
        // 左下曲线
        path.addCurve(
            to: CGPoint(x: 75 * scaleX, y: 230 * scaleY),
            controlPoint1: CGPoint(x: 40 * scaleX, y: 205 * scaleY),
            controlPoint2: CGPoint(x: 55 * scaleX, y: 225 * scaleY)
        )
        
        // 底部凹陷
        path.addCurve(
            to: CGPoint(x: 100 * scaleX, y: 220 * scaleY),
            controlPoint1: CGPoint(x: 85 * scaleX, y: 232 * scaleY),
            controlPoint2: CGPoint(x: 95 * scaleX, y: 228 * scaleY)
        )
        
        // 右半边（对称）
        path.addCurve(
            to: CGPoint(x: 125 * scaleX, y: 230 * scaleY),
            controlPoint1: CGPoint(x: 105 * scaleX, y: 228 * scaleY),
            controlPoint2: CGPoint(x: 115 * scaleX, y: 232 * scaleY)
        )
        
        // 右下曲线
        path.addCurve(
            to: CGPoint(x: 170 * scaleX, y: 180 * scaleY),
            controlPoint1: CGPoint(x: 145 * scaleX, y: 225 * scaleY),
            controlPoint2: CGPoint(x: 160 * scaleX, y: 205 * scaleY)
        )
        
        // 右侧曲线
        path.addCurve(
            to: CGPoint(x: 180 * scaleX, y: 100 * scaleY),
            controlPoint1: CGPoint(x: 180 * scaleX, y: 160 * scaleY),
            controlPoint2: CGPoint(x: 180 * scaleX, y: 130 * scaleY)
        )
        
        // 右上曲线
        path.addCurve(
            to: CGPoint(x: 130 * scaleX, y: 70 * scaleY),
            controlPoint1: CGPoint(x: 180 * scaleX, y: 80 * scaleY),
            controlPoint2: CGPoint(x: 155 * scaleX, y: 70 * scaleY)
        )
        
        // 回到顶部
        path.addCurve(
            to: CGPoint(x: 100 * scaleX, y: 50 * scaleY),
            controlPoint1: CGPoint(x: 120 * scaleX, y: 55 * scaleY),
            controlPoint2: CGPoint(x: 110 * scaleX, y: 50 * scaleY)
        )
        
        path.close()
        
        // 叶子
        let leafPath = UIBezierPath()
        leafPath.move(to: CGPoint(x: 105 * scaleX, y: 45 * scaleY))
        
        leafPath.addCurve(
            to: CGPoint(x: 130 * scaleX, y: 10 * scaleY),
            controlPoint1: CGPoint(x: 105 * scaleX, y: 30 * scaleY),
            controlPoint2: CGPoint(x: 115 * scaleX, y: 15 * scaleY)
        )
        
        leafPath.addCurve(
            to: CGPoint(x: 115 * scaleX, y: 40 * scaleY),
            controlPoint1: CGPoint(x: 140 * scaleX, y: 20 * scaleY),
            controlPoint2: CGPoint(x: 130 * scaleX, y: 35 * scaleY)
        )
        
        leafPath.close()
        
        path.append(leafPath)
        
        return path.cgPath
    }
    
    /// 创建简化版 Apple Logo（性能更好）
    static func createSimplified(size: CGSize = CGSize(width: 200, height: 240)) -> CGPath {
        let path = UIBezierPath()
        
        let scaleX = size.width / 200
        let scaleY = size.height / 240
        
        // 简化的苹果形状（使用更少的控制点）
        path.move(to: CGPoint(x: 100 * scaleX, y: 55 * scaleY))
        
        // 左侧
        path.addQuadCurve(
            to: CGPoint(x: 25 * scaleX, y: 130 * scaleY),
            controlPoint: CGPoint(x: 25 * scaleX, y: 55 * scaleY)
        )
        
        path.addQuadCurve(
            to: CGPoint(x: 100 * scaleX, y: 220 * scaleY),
            controlPoint: CGPoint(x: 25 * scaleX, y: 220 * scaleY)
        )
        
        // 右侧
        path.addQuadCurve(
            to: CGPoint(x: 175 * scaleX, y: 130 * scaleY),
            controlPoint: CGPoint(x: 175 * scaleX, y: 220 * scaleY)
        )
        
        path.addQuadCurve(
            to: CGPoint(x: 100 * scaleX, y: 55 * scaleY),
            controlPoint: CGPoint(x: 175 * scaleX, y: 55 * scaleY)
        )
        
        path.close()
        
        // 叶子
        let leafPath = UIBezierPath()
        leafPath.move(to: CGPoint(x: 100 * scaleX, y: 50 * scaleY))
        leafPath.addQuadCurve(
            to: CGPoint(x: 130 * scaleX, y: 15 * scaleY),
            controlPoint: CGPoint(x: 100 * scaleX, y: 15 * scaleY)
        )
        leafPath.addQuadCurve(
            to: CGPoint(x: 100 * scaleX, y: 50 * scaleY),
            controlPoint: CGPoint(x: 130 * scaleX, y: 50 * scaleY)
        )
        leafPath.close()
        
        path.append(leafPath)
        
        return path.cgPath
    }
}

// MARK: - 其他形状生成器

/// 常用形状生成器
enum ShapeGenerator {
    
    /// 创建圆形
    static func circle(diameter: CGFloat) -> CGPath {
        return UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: diameter, height: diameter)).cgPath
    }
    
    /// 创建圆角矩形
    static func roundedRect(size: CGSize, cornerRadius: CGFloat) -> CGPath {
        return UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius).cgPath
    }
    
    /// 创建星形
    static func star(points: Int, innerRadius: CGFloat, outerRadius: CGFloat) -> CGPath {
        let path = UIBezierPath()
        let center = CGPoint(x: outerRadius, y: outerRadius)
        let angleIncrement = CGFloat.pi / CGFloat(points)
        
        for i in 0..<(points * 2) {
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let angle = CGFloat(i) * angleIncrement - CGFloat.pi / 2
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        
        path.close()
        return path.cgPath
    }
    
    /// 创建心形
    static func heart(size: CGFloat) -> CGPath {
        let path = UIBezierPath()
        let width = size
        let height = size
        
        path.move(to: CGPoint(x: width / 2, y: height))
        
        // 左半边
        path.addCurve(
            to: CGPoint(x: 0, y: height / 4),
            controlPoint1: CGPoint(x: width / 2 - width / 4, y: height * 3 / 4),
            controlPoint2: CGPoint(x: 0, y: height / 2)
        )
        
        path.addArc(
            withCenter: CGPoint(x: width / 4, y: height / 4),
            radius: width / 4,
            startAngle: .pi,
            endAngle: 0,
            clockwise: true
        )
        
        // 右半边
        path.addArc(
            withCenter: CGPoint(x: width * 3 / 4, y: height / 4),
            radius: width / 4,
            startAngle: .pi,
            endAngle: 0,
            clockwise: true
        )
        
        path.addCurve(
            to: CGPoint(x: width / 2, y: height),
            controlPoint1: CGPoint(x: width, y: height / 2),
            controlPoint2: CGPoint(x: width / 2 + width / 4, y: height * 3 / 4)
        )
        
        path.close()
        return path.cgPath
    }
    
    /// 创建闪电形状
    static func lightning(size: CGSize) -> CGPath {
        let path = UIBezierPath()
        let w = size.width
        let h = size.height
        
        path.move(to: CGPoint(x: w * 0.6, y: 0))
        path.addLine(to: CGPoint(x: w * 0.2, y: h * 0.45))
        path.addLine(to: CGPoint(x: w * 0.45, y: h * 0.45))
        path.addLine(to: CGPoint(x: w * 0.4, y: h))
        path.addLine(to: CGPoint(x: w * 0.8, y: h * 0.55))
        path.addLine(to: CGPoint(x: w * 0.55, y: h * 0.55))
        path.close()
        
        return path.cgPath
    }
}
