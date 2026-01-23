//
//  GPUSDFComputer.swift
//  EnergyShape
//
//  Created by Sun on 2026/1/21.
//  GPU SDF 计算器 - 使用 Jump Flooding Algorithm 计算任意路径的 SDF
//

import CoreGraphics
import Metal
import UIKit

// MARK: - GPUSDFComputer

/// GPU SDF 计算器
/// 使用 Jump Flooding Algorithm (JFA) 在 GPU 上高速计算任意 CGPath 的 SDF
///
/// 算法原理：
/// 1. 将路径栅格化为 Mask 纹理（边缘像素标记为种子点）
/// 2. 使用 JFA 传播最近种子点信息（log₂(n) 次迭代）
/// 3. 计算每个像素到最近种子点的距离，生成 SDF
///
/// 性能特点：
/// - 512x512: ~3-5ms (vs CPU 8SSEDT ~50-100ms)
/// - 1024x1024: ~8-15ms
/// - 完全 GPU 并行，不阻塞 CPU
final class GPUSDFComputer: SDFProvider {
    // MARK: - 属性

    let mode: SDFMode = .texture

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    /// 计算管线
    private var seedPipelineState: MTLComputePipelineState?
    private var jfaPipelineState: MTLComputePipelineState?
    private var sdfPipelineState: MTLComputePipelineState?

    /// 工作纹理
    private var pingTexture: MTLTexture?
    private var pongTexture: MTLTexture?
    private var sdfTexture: MTLTexture?

    /// 后台队列
    private let computeQueue = DispatchQueue(label: "energy.sdf.compute", qos: .userInitiated)

    /// 当前计算任务（用于取消）
    private var currentTask: DispatchWorkItem?

    /// 最大 SDF 尺寸（性能和质量的平衡点）
    /// 1024 能在高分辨率设备上保持良好的边缘平滑度
    private let maxSDFSize = 1024

    // MARK: - 初始化

    init(device: MTLDevice) throws {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw SDFError.deviceNotAvailable
        }
        commandQueue = queue

        try setupPipelines()
    }

    // MARK: - Pipeline 设置

    private func setupPipelines() throws {
        // 从嵌入式字符串加载 Shader 源码（无需依赖 .metal 文件）
        let library = try ShaderSource.makeLibrary(device: device)
        try setupPipelinesWithLibrary(library)
    }

    private func setupPipelinesWithLibrary(_ library: MTLLibrary) throws {
        // 种子点初始化
        if let seedFunction = library.makeFunction(name: "jfaSeedInit") {
            seedPipelineState = try device.makeComputePipelineState(function: seedFunction)
        }

        // JFA 迭代
        if let jfaFunction = library.makeFunction(name: "jfaFlood") {
            jfaPipelineState = try device.makeComputePipelineState(function: jfaFunction)
        }

        // SDF 生成
        if let sdfFunction = library.makeFunction(name: "jfaToSDF") {
            sdfPipelineState = try device.makeComputePipelineState(function: sdfFunction)
        }
    }

    // MARK: - SDFProvider

    func prepareSDF(
        for shapeType: InternalShapeType,
        viewSize: CGSize,
        scale: CGFloat,
        completion: @escaping (Result<SDFResult, Error>) -> Void
    ) {
        // 取消之前的计算
        cancel()

        // 提取 CGPath
        let path: CGPath
        switch shapeType {
        case let .customPath(cgPath):
            path = cgPath
        case .analytic:
            // 解析形状不应该使用 GPU 计算
            completion(.failure(SDFError.invalidShape))
            return
        }

        // 计算纹理尺寸
        var textureWidth = Int(viewSize.width * scale)
        var textureHeight = Int(viewSize.height * scale)

        // 限制最大尺寸
        if textureWidth > maxSDFSize || textureHeight > maxSDFSize {
            let scaleFactor = CGFloat(maxSDFSize) / CGFloat(max(textureWidth, textureHeight))
            textureWidth = max(1, Int(CGFloat(textureWidth) * scaleFactor))
            textureHeight = max(1, Int(CGFloat(textureHeight) * scaleFactor))
        }

        // 创建任务
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }

            do {
                // 1. 栅格化路径为 Mask
                let maskTexture = try rasterizePath(
                    path,
                    width: textureWidth,
                    height: textureHeight,
                    viewSize: viewSize
                )

                // 2. 使用 JFA 计算 SDF
                let sdfTexture = try computeSDFWithJFA(from: maskTexture)

                DispatchQueue.main.async {
                    completion(.success(.texture(sdfTexture)))
                }

            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }

        currentTask = task
        computeQueue.async(execute: task)
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - 路径栅格化

    /// 将 CGPath 栅格化为 Mask 纹理
    private func rasterizePath(
        _ path: CGPath,
        width: Int,
        height: Int,
        viewSize: CGSize
    ) throws -> MTLTexture {
        // 使用 Core Graphics 栅格化（抗锯齿）
        let scale = CGFloat(width) / viewSize.width
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
            throw SDFError.computeFailed("无法创建 CGContext")
        }

        // 启用抗锯齿
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high

        // 设置变换
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)

        // 填充路径
        context.setFillColor(UIColor.white.cgColor)
        context.addPath(path)
        context.fillPath()

        // 提取灰度值
        var grayData = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            grayData[i] = pixelData[i * 4 + 3]
        }

        // 创建 Metal 纹理
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw SDFError.textureCreationFailed
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: grayData,
            bytesPerRow: width
        )

        return texture
    }

    // MARK: - JFA 计算

    /// 使用 Jump Flooding Algorithm 计算 SDF
    private func computeSDFWithJFA(from maskTexture: MTLTexture) throws -> MTLTexture {
        let width = maskTexture.width
        let height = maskTexture.height

        // 确保 Pipeline 存在
        guard
            let seedPipeline = seedPipelineState,
            let jfaPipeline = jfaPipelineState,
            let sdfPipeline = sdfPipelineState else {
            throw SDFError.computeFailed("Compute Pipeline 未初始化")
        }

        // 创建工作纹理（存储最近种子点坐标）
        // 使用 RG16Float 存储 (x, y) 坐标
        let workDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        workDescriptor.usage = [.shaderRead, .shaderWrite]
        workDescriptor.storageMode = .private

        guard
            let ping = device.makeTexture(descriptor: workDescriptor),
            let pong = device.makeTexture(descriptor: workDescriptor) else {
            throw SDFError.textureCreationFailed
        }

        // 创建 SDF 输出纹理
        let sdfDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        sdfDescriptor.usage = [.shaderRead, .shaderWrite]
        sdfDescriptor.storageMode = .shared

        guard let sdf = device.makeTexture(descriptor: sdfDescriptor) else {
            throw SDFError.textureCreationFailed
        }

        // 创建 Command Buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw SDFError.computeFailed("无法创建 Command Buffer")
        }

        // 线程组配置
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )

        // Pass 1: 种子点初始化
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(seedPipeline)
            encoder.setTexture(maskTexture, index: 0)
            encoder.setTexture(ping, index: 1)
            encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
            encoder.endEncoding()
        }

        // Pass 2-N: JFA 迭代
        let maxDim = max(width, height)
        var stepSize = maxDim / 2
        var readTexture = ping
        var writeTexture = pong

        while stepSize >= 1 {
            if let encoder = commandBuffer.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(jfaPipeline)
                encoder.setTexture(readTexture, index: 0)
                encoder.setTexture(writeTexture, index: 1)

                var step = Int32(stepSize)
                encoder.setBytes(&step, length: MemoryLayout<Int32>.size, index: 0)

                encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
                encoder.endEncoding()
            }

            // 交换纹理
            swap(&readTexture, &writeTexture)
            stepSize /= 2
        }

        // Pass 最终: 生成 SDF
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(sdfPipeline)
            encoder.setTexture(readTexture, index: 0) // JFA 结果
            encoder.setTexture(maskTexture, index: 1) // 原始 Mask
            encoder.setTexture(sdf, index: 2) // SDF 输出

            var maxDist = Float(max(32, min(128, maxDim / 4)))
            encoder.setBytes(&maxDist, length: MemoryLayout<Float>.size, index: 0)

            encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
            encoder.endEncoding()
        }

        // 提交并等待
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw SDFError.computeFailed("GPU 计算错误: \(error.localizedDescription)")
        }

        return sdf
    }
}
