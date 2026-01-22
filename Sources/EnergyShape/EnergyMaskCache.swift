//
//  EnergyMaskCache.swift
//  EnergyShape
//
//  Created by Sun on 2026/1/21.
//  Mask/SDF 缓存管理 - 支持后台生成与无缝切换
//

import CoreGraphics
import Metal
import UIKit

// MARK: - Mask 缓存结果

/// Mask 纹理结果
struct MaskTextures {
    let mask: MTLTexture
    let sdf: MTLTexture?
}

// MARK: - EnergyMaskCache

/// Mask 与 SDF 缓存管理器
/// 负责 CGPath → Mask 纹理 → SDF 纹理的生成与缓存
final class EnergyMaskCache {
    // MARK: - 属性

    private let device: MTLDevice
    private let generateQueue = DispatchQueue(label: "energy.mask.generate", qos: .userInitiated)

    /// 当前使用的纹理
    private var currentTextures: MaskTextures?
    /// 待切换的纹理（后台生成完成后）
    private var pendingTextures: MaskTextures?
    /// LUT 纹理
    private(set) var lutTexture: MTLTexture?

    private let lock = NSLock()

    /// 总内存占用
    var totalMemoryBytes: Int {
        lock.lock()
        defer { lock.unlock() }

        var total = 0
        if let mask = currentTextures?.mask {
            total += mask.memorySize
        }
        if let sdf = currentTextures?.sdf {
            total += sdf.memorySize
        }
        if let lut = lutTexture {
            total += lut.memorySize
        }
        return total
    }

    // MARK: - 初始化

    init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - 公开方法

    /// 更新形状路径
    /// - Parameters:
    ///   - path: CGPath 路径
    ///   - size: 目标尺寸
    ///   - scale: 屏幕缩放因子
    ///   - sdfEnabled: 是否生成 SDF
    ///   - sdfQuality: SDF 质量
    ///   - completion: 完成回调（主线程）
    func updatePath(
        _ path: CGPath,
        size: CGSize,
        scale: CGFloat,
        sdfEnabled: Bool,
        sdfQuality: SDFQuality,
        completion: @escaping (Result<MaskTextures, Error>) -> Void
    ) {
        generateQueue.async { [weak self] in
            guard let self else { return }

            do {
                // 计算纹理尺寸（使用原始分辨率，不进行下采样以保持边缘清晰）
                var textureWidth = Int(size.width * scale)
                var textureHeight = Int(size.height * scale)

                guard textureWidth > 0, textureHeight > 0 else {
                    throw EnergyShapeError.invalidPath
                }

                // 关键改动：Mask 使用适中分辨率以平衡质量和性能
                // 过高的分辨率会导致切换形状时卡顿
                let maxMaskSize = 1024
                var actualScale = scale
                if textureWidth > maxMaskSize || textureHeight > maxMaskSize {
                    let scaleFactor = CGFloat(maxMaskSize) / CGFloat(max(textureWidth, textureHeight))
                    textureWidth = max(1, Int(CGFloat(textureWidth) * scaleFactor))
                    textureHeight = max(1, Int(CGFloat(textureHeight) * scaleFactor))
                    actualScale = CGFloat(textureWidth) / size.width
                }

                // 生成 Mask 纹理
                let maskTexture = try generateMaskTexture(
                    from: path,
                    width: textureWidth,
                    height: textureHeight,
                    scale: actualScale
                )

                // 生成 SDF 纹理（如果启用）
                // 性能优化：SDF 使用较低分辨率，通过双线性采样获得平滑效果
                var sdfTexture: MTLTexture?
                if sdfEnabled {
                    // SDF 不需要与屏幕 1:1，使用较低分辨率以提升性能
                    // 双线性采样会自动平滑边缘
                    let sdfScale = sdfQuality.resolutionScale
                    
                    // 基于质量等级计算 SDF 尺寸
                    // 性能优先：限制最大 512，在 Shader 中通过插值获得平滑效果
                    let maxSDFSize = 512
                    var sdfWidth = max(1, Int(Float(textureWidth) * sdfScale))
                    var sdfHeight = max(1, Int(Float(textureHeight) * sdfScale))
                    
                    if sdfWidth > maxSDFSize || sdfHeight > maxSDFSize {
                        let scaleFactor = Float(maxSDFSize) / Float(max(sdfWidth, sdfHeight))
                        sdfWidth = max(1, Int(Float(sdfWidth) * scaleFactor))
                        sdfHeight = max(1, Int(Float(sdfHeight) * scaleFactor))
                    }

                    sdfTexture = try generateSDFTexture(
                        from: maskTexture,
                        targetWidth: sdfWidth,
                        targetHeight: sdfHeight
                    )
                }

                let textures = MaskTextures(mask: maskTexture, sdf: sdfTexture)

                // 保存为待切换纹理
                lock.lock()
                pendingTextures = textures
                lock.unlock()

                DispatchQueue.main.async {
                    completion(.success(textures))
                }

            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// 提交待切换的纹理（在渲染前调用）
    func commitPendingTextures() {
        lock.lock()
        defer { lock.unlock() }

        if let pending = pendingTextures {
            currentTextures = pending
            pendingTextures = nil
        }
    }

    /// 获取当前 Mask 纹理
    var maskTexture: MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        return currentTextures?.mask
    }

    /// 获取当前 SDF 纹理
    var sdfTexture: MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        return currentTextures?.sdf
    }

    /// 更新颜色 LUT
    func updateColorLUT(_ colorStops: [ColorStop]) {
        generateQueue.async { [weak self] in
            guard let self else { return }

            if let texture = generateLUTTexture(from: colorStops) {
                lock.lock()
                lutTexture = texture
                lock.unlock()
            }
        }
    }

    /// 清空缓存
    func purge() {
        lock.lock()
        defer { lock.unlock() }

        currentTextures = nil
        pendingTextures = nil
        lutTexture = nil
    }

    // MARK: - Mask 生成

    /// 将 CGPath 栅格化为 Mask 纹理（带抗锯齿）
    private func generateMaskTexture(
        from path: CGPath,
        width: Int,
        height: Int,
        scale: CGFloat
    ) throws -> MTLTexture {
        // 使用 RGBA 格式以支持抗锯齿
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)

        guard
            let context = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
            throw EnergyShapeError.textureCreationFailed
        }

        // 启用抗锯齿
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high

        // 设置变换（翻转 Y 轴以匹配 Metal 坐标系）
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)

        // 填充路径（白色）
        context.setFillColor(UIColor.white.cgColor)
        context.addPath(path)
        context.fillPath()

        // 提取灰度值（从 RGBA 转为单通道）
        var grayData = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            // 使用 alpha 通道作为灰度值（抗锯齿效果在 alpha 通道）
            grayData[i] = pixelData[i * 4 + 3]
        }

        // 创建 Metal 纹理
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw EnergyShapeError.textureCreationFailed
        }

        // 上传数据
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: grayData,
            bytesPerRow: width
        )

        return texture
    }

    // MARK: - SDF 生成（8SSEDT 算法）

    /// 生成 SDF 纹理
    private func generateSDFTexture(
        from maskTexture: MTLTexture,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> MTLTexture {
        // 从 mask 纹理读取数据
        let sourceWidth = maskTexture.width
        let sourceHeight = maskTexture.height
        var maskData = [UInt8](repeating: 0, count: sourceWidth * sourceHeight)

        maskTexture.getBytes(
            &maskData,
            bytesPerRow: sourceWidth,
            from: MTLRegionMake2D(0, 0, sourceWidth, sourceHeight),
            mipmapLevel: 0
        )

        // 下采样（如果需要）
        let workWidth: Int
        let workHeight: Int
        var workData: [UInt8]

        if targetWidth < sourceWidth || targetHeight < sourceHeight {
            workWidth = targetWidth
            workHeight = targetHeight
            workData = downsample(maskData, from: (sourceWidth, sourceHeight), to: (targetWidth, targetHeight))
        } else {
            workWidth = sourceWidth
            workHeight = sourceHeight
            workData = maskData
        }

        // 计算 SDF
        let sdfData = computeSDF(from: workData, width: workWidth, height: workHeight)

        // 创建 SDF 纹理
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: workWidth,
            height: workHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw EnergyShapeError.textureCreationFailed
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, workWidth, workHeight),
            mipmapLevel: 0,
            withBytes: sdfData,
            bytesPerRow: workWidth
        )

        return texture
    }

    /// 8SSEDT (8-points Signed Sequential Euclidean Distance Transform)
    /// 高性能版本 - 简化初始化逻辑以提升速度
    private func computeSDF(from mask: [UInt8], width: Int, height: Int) -> [UInt8] {
        let inf = Int32(width + height)

        // 使用 (dx, dy) 存储最近边缘点的偏移
        var gridInside = [(dx: Int32, dy: Int32)](repeating: (0, 0), count: width * height)
        var gridOutside = [(dx: Int32, dy: Int32)](repeating: (0, 0), count: width * height)

        // 简化的初始化：使用 128 作为阈值
        for i in 0..<(width * height) {
            if mask[i] >= 128 {
                gridInside[i] = (0, 0)
                gridOutside[i] = (inf, inf)
            } else {
                gridInside[i] = (inf, inf)
                gridOutside[i] = (0, 0)
            }
        }

        // 对内部和外部分别计算距离
        compute8SSEDT(&gridInside, width: width, height: height)
        compute8SSEDT(&gridOutside, width: width, height: height)

        // 计算有符号距离并归一化
        var result = [UInt8](repeating: 0, count: width * height)

        // maxDist 决定 SDF 的有效范围
        let smallerDimension = min(width, height)
        let maxDist = Float(max(32, min(128, smallerDimension / 4)))

        for i in 0..<(width * height) {
            let insideDist = sqrt(Float(gridInside[i].dx * gridInside[i].dx + gridInside[i].dy * gridInside[i].dy))
            let outsideDist = sqrt(Float(gridOutside[i].dx * gridOutside[i].dx + gridOutside[i].dy * gridOutside[i].dy))
            
            // 有符号距离
            let signedDist = insideDist - outsideDist

            // 归一化到 [0, 1]，0.5 表示边缘
            let normalized = (signedDist / maxDist + 1.0) * 0.5
            result[i] = UInt8(max(0, min(255, normalized * 255)))
        }

        return result
    }

    /// 真正的 8SSEDT 两遍扫描算法
    private func compute8SSEDT(_ grid: inout [(dx: Int32, dy: Int32)], width: Int, height: Int) {
        // 8 个方向的偏移 (包括对角线)
        // 第一遍：从左上到右下，检查左上方的 4 个邻居
        // 第二遍：从右下到左上，检查右下方的 4 个邻居

        // --- 第一遍：左上到右下 ---
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                var p = grid[idx]

                // 检查上方 (0, -1)
                if y > 0 {
                    let nIdx = (y - 1) * width + x
                    let n = grid[nIdx]
                    let newDx = n.dx
                    let newDy = n.dy + 1
                    if newDx * newDx + newDy * newDy < p.dx * p.dx + p.dy * p.dy {
                        p = (newDx, newDy)
                    }
                }

                // 检查左方 (-1, 0)
                if x > 0 {
                    let nIdx = y * width + (x - 1)
                    let n = grid[nIdx]
                    let newDx = n.dx + 1
                    let newDy = n.dy
                    if newDx * newDx + newDy * newDy < p.dx * p.dx + p.dy * p.dy {
                        p = (newDx, newDy)
                    }
                }

                // 检查左上 (-1, -1)
                if x > 0, y > 0 {
                    let nIdx = (y - 1) * width + (x - 1)
                    let n = grid[nIdx]
                    let newDx = n.dx + 1
                    let newDy = n.dy + 1
                    if newDx * newDx + newDy * newDy < p.dx * p.dx + p.dy * p.dy {
                        p = (newDx, newDy)
                    }
                }

                // 检查右上 (+1, -1)
                if x < width - 1, y > 0 {
                    let nIdx = (y - 1) * width + (x + 1)
                    let n = grid[nIdx]
                    let newDx = n.dx - 1
                    let newDy = n.dy + 1
                    if newDx * newDx + newDy * newDy < p.dx * p.dx + p.dy * p.dy {
                        p = (newDx, newDy)
                    }
                }

                grid[idx] = p
            }
        }

        // --- 第二遍：右下到左上 ---
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: width - 1, through: 0, by: -1) {
                let idx = y * width + x
                var p = grid[idx]

                // 检查下方 (0, +1)
                if y < height - 1 {
                    let nIdx = (y + 1) * width + x
                    let n = grid[nIdx]
                    let newDx = n.dx
                    let newDy = n.dy - 1
                    if newDx * newDx + newDy * newDy < p.dx * p.dx + p.dy * p.dy {
                        p = (newDx, newDy)
                    }
                }

                // 检查右方 (+1, 0)
                if x < width - 1 {
                    let nIdx = y * width + (x + 1)
                    let n = grid[nIdx]
                    let newDx = n.dx - 1
                    let newDy = n.dy
                    if newDx * newDx + newDy * newDy < p.dx * p.dx + p.dy * p.dy {
                        p = (newDx, newDy)
                    }
                }

                // 检查右下 (+1, +1)
                if x < width - 1, y < height - 1 {
                    let nIdx = (y + 1) * width + (x + 1)
                    let n = grid[nIdx]
                    let newDx = n.dx - 1
                    let newDy = n.dy - 1
                    if newDx * newDx + newDy * newDy < p.dx * p.dx + p.dy * p.dy {
                        p = (newDx, newDy)
                    }
                }

                // 检查左下 (-1, +1)
                if x > 0, y < height - 1 {
                    let nIdx = (y + 1) * width + (x - 1)
                    let n = grid[nIdx]
                    let newDx = n.dx + 1
                    let newDy = n.dy - 1
                    if newDx * newDx + newDy * newDy < p.dx * p.dx + p.dy * p.dy {
                        p = (newDx, newDy)
                    }
                }

                grid[idx] = p
            }
        }
    }

    /// 双线性插值下采样（抗锯齿）
    /// 比最近邻采样更平滑，能更好地保留边缘细节
    private func downsample(_ data: [UInt8], from source: (Int, Int), to target: (Int, Int)) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: target.0 * target.1)

        let scaleX = Float(source.0) / Float(target.0)
        let scaleY = Float(source.1) / Float(target.1)

        for y in 0..<target.1 {
            for x in 0..<target.0 {
                // 计算源坐标（使用中心点采样）
                let srcX = (Float(x) + 0.5) * scaleX - 0.5
                let srcY = (Float(y) + 0.5) * scaleY - 0.5
                
                // 双线性插值的四个角点
                let x0 = max(0, Int(floor(srcX)))
                let x1 = min(source.0 - 1, x0 + 1)
                let y0 = max(0, Int(floor(srcY)))
                let y1 = min(source.1 - 1, y0 + 1)
                
                // 插值权重
                let fx = srcX - Float(x0)
                let fy = srcY - Float(y0)
                
                // 采样四个角点
                let v00 = Float(data[y0 * source.0 + x0])
                let v10 = Float(data[y0 * source.0 + x1])
                let v01 = Float(data[y1 * source.0 + x0])
                let v11 = Float(data[y1 * source.0 + x1])
                
                // 双线性插值
                let v0 = v00 * (1.0 - fx) + v10 * fx
                let v1 = v01 * (1.0 - fx) + v11 * fx
                let value = v0 * (1.0 - fy) + v1 * fy
                
                result[y * target.0 + x] = UInt8(max(0, min(255, value)))
            }
        }

        return result
    }

    // MARK: - LUT 生成

    /// 生成 256 宽度的 2D 颜色查找表（高度=1，与 Shader 中的 texture2d 匹配）
    private func generateLUTTexture(from colorStops: [ColorStop]) -> MTLTexture? {
        let width = 256
        var pixels = [UInt8](repeating: 0, count: width * 4)

        // 确保 colorStops 已排序
        let sortedStops = colorStops.sorted { $0.position < $1.position }

        guard sortedStops.count >= 2 else { return nil }

        for i in 0..<width {
            let t = Float(i) / Float(width - 1)
            let color = interpolateColor(at: t, stops: sortedStops)

            pixels[i * 4 + 0] = UInt8(max(0, min(255, color.r * 255)))
            pixels[i * 4 + 1] = UInt8(max(0, min(255, color.g * 255)))
            pixels[i * 4 + 2] = UInt8(max(0, min(255, color.b * 255)))
            pixels[i * 4 + 3] = 255
        }

        // 创建 2D 纹理（高度=1），与 Shader 中的 texture2d 匹配
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, 1),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width * 4
        )

        return texture
    }

    /// 在 colorStops 之间插值
    private func interpolateColor(at t: Float, stops: [ColorStop]) -> (r: Float, g: Float, b: Float) {
        // 找到 t 所在的区间
        var lowerIndex = 0
        var upperIndex = stops.count - 1

        for i in 0..<(stops.count - 1) {
            if t >= stops[i].position, t <= stops[i + 1].position {
                lowerIndex = i
                upperIndex = i + 1
                break
            }
        }

        let lower = stops[lowerIndex]
        let upper = stops[upperIndex]

        // 计算局部 t
        let range = upper.position - lower.position
        let localT = range > 0 ? (t - lower.position) / range : 0

        // 使用 smoothstep 插值以获得更平滑的过渡
        let smoothT = localT * localT * (3 - 2 * localT)

        // 线性插值颜色
        let lowerRGBA = lower.rgba
        let upperRGBA = upper.rgba

        return (
            r: lowerRGBA.r + (upperRGBA.r - lowerRGBA.r) * smoothT,
            g: lowerRGBA.g + (upperRGBA.g - lowerRGBA.g) * smoothT,
            b: lowerRGBA.b + (upperRGBA.b - lowerRGBA.b) * smoothT
        )
    }
}
