//
//  TexturePool.swift
//  EnergyShape
//
//  Created by Sun on 2026/1/21.
//  纹理复用池 - 避免频繁创建/销毁 Metal 纹理
//

import Foundation
import Metal
#if canImport(UIKit)
    import UIKit
#endif

// MARK: - 纹理池

/// Metal 纹理复用池
/// 按尺寸分类管理，自动清理过期纹理
final class TexturePool {
    // MARK: - 属性

    private let device: MTLDevice
    private var pool: [TextureKey: [PooledTexture]] = [:]
    private let lock = NSLock()

    /// 最大空闲纹理数量（每个尺寸）
    private let maxIdleTexturesPerSize: Int = 3

    /// 纹理过期时间（秒）
    private let textureExpirationTime: TimeInterval = 10.0

    /// 总内存占用
    private(set) var totalMemoryBytes: Int = 0

    // MARK: - 初始化

    init(device: MTLDevice) {
        self.device = device

        // 监听内存警告（仅 iOS/tvOS）
        #if canImport(UIKit) && !os(watchOS)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleMemoryWarning),
                name: UIApplication.didReceiveMemoryWarningNotification,
                object: nil
            )
        #endif
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 公开方法

    /// 获取纹理（从池中取出或新建）
    func acquire(
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat,
        usage: MTLTextureUsage = [.shaderRead, .renderTarget]
    ) -> MTLTexture? {
        let key = TextureKey(width: width, height: height, format: pixelFormat, usage: usage)

        lock.lock()
        defer { lock.unlock() }

        // 尝试从池中获取
        if var textures = pool[key], !textures.isEmpty {
            let pooled = textures.removeLast()
            pool[key] = textures
            return pooled.texture
        }

        // 创建新纹理
        return createTexture(key: key)
    }

    /// 归还纹理到池中
    func release(_ texture: MTLTexture) {
        let key = TextureKey(
            width: texture.width,
            height: texture.height,
            format: texture.pixelFormat,
            usage: texture.usage
        )

        lock.lock()
        defer { lock.unlock() }

        var textures = pool[key] ?? []

        // 如果池已满，直接丢弃（让 ARC 释放）并减少内存统计
        guard textures.count < maxIdleTexturesPerSize else {
            totalMemoryBytes -= texture.memorySize
            return
        }

        let pooled = PooledTexture(texture: texture, returnTime: Date())
        textures.append(pooled)
        pool[key] = textures
    }

    /// 清理过期纹理
    func purgeExpired() {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        var removedBytes = 0

        for (key, textures) in pool {
            let (active, expired) = textures
                .partitioned { now.timeIntervalSince($0.returnTime) < textureExpirationTime }

            for pooled in expired {
                removedBytes += pooled.texture.memorySize
            }

            if active.isEmpty {
                pool.removeValue(forKey: key)
            } else {
                pool[key] = active
            }
        }

        totalMemoryBytes -= removedBytes
    }

    /// 清空所有缓存
    func purgeAll() {
        lock.lock()
        defer { lock.unlock() }

        pool.removeAll()
        totalMemoryBytes = 0
    }

    /// 获取池统计信息
    var statistics: String {
        lock.lock()
        defer { lock.unlock() }

        let totalCount = pool.values.reduce(0) { $0 + $1.count }
        let sizeCount = pool.count
        return "TexturePool: \(totalCount) textures in \(sizeCount) sizes, \(ByteCountFormatter.string(fromByteCount: Int64(totalMemoryBytes), countStyle: .memory))"
    }

    // MARK: - 私有方法

    private func createTexture(key: TextureKey) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: key.format,
            width: key.width,
            height: key.height,
            mipmapped: false
        )
        descriptor.usage = key.usage
        descriptor.storageMode = .private

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        totalMemoryBytes += texture.memorySize
        return texture
    }

    @objc private func handleMemoryWarning() {
        purgeAll()
    }
}

// MARK: - 辅助类型

/// 纹理缓存键
private struct TextureKey: Hashable {
    let width: Int
    let height: Int
    let format: MTLPixelFormat
    let usage: MTLTextureUsage

    // 显式实现 Hashable，因为 MTLPixelFormat 和 MTLTextureUsage 需要用 rawValue
    func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
        hasher.combine(format.rawValue)
        hasher.combine(usage.rawValue)
    }

    static func == (lhs: TextureKey, rhs: TextureKey) -> Bool {
        lhs.width == rhs.width &&
            lhs.height == rhs.height &&
            lhs.format == rhs.format &&
            lhs.usage == rhs.usage
    }
}

/// 池化纹理
private struct PooledTexture {
    let texture: MTLTexture
    let returnTime: Date
}

// MARK: - MTLTexture 扩展

extension MTLTexture {
    /// 估算纹理内存大小
    var memorySize: Int {
        let bytesPerPixel = switch pixelFormat {
        case .r8Unorm, .a8Unorm:
            1
        case .rg8Unorm, .r16Float:
            2
        case .rgba8Unorm, .rgba8Unorm_srgb, .bgra8Unorm, .bgra8Unorm_srgb, .r32Float, .rg16Float:
            4
        case .rgba16Float:
            8
        case .rgba32Float:
            16
        default:
            4
        }
        return width * height * bytesPerPixel
    }
}

// MARK: - Array 扩展

private extension Array {
    /// 分区：满足条件的和不满足条件的
    func partitioned(by predicate: (Element) -> Bool) -> (matching: [Element], notMatching: [Element]) {
        var matching: [Element] = []
        var notMatching: [Element] = []
        for element in self {
            if predicate(element) {
                matching.append(element)
            } else {
                notMatching.append(element)
            }
        }
        return (matching, notMatching)
    }
}
