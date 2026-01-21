# EnergyShape

iOS Metal 优先的通用 Shape 能量动画组件，在任意 CGPath 形状内部渲染高质感的能量流动动画。

![iOS 14.0+](https://img.shields.io/badge/iOS-14.0+-blue.svg)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)
![Metal](https://img.shields.io/badge/Metal-Supported-green.svg)
![License MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

## ✨ 特性

- 🎨 **任意形状支持** - 支持任何 CGPath 定义的形状
- ⚡️ **高性能 Metal 渲染** - 60fps 流畅动画
- 🌈 **可配置颜色渐变** - 自定义 LUT 颜色映射
- ✨ **Bloom 辉光效果** - 4-Pass 高质量 Bloom
- 📐 **精准 SDF 边缘** - 8SSEDT 算法生成精确距离场
- 🔄 **状态机动画** - idle → startup → loop ⇄ settle
- 📱 **降级兼容** - 不支持 Metal 时自动降级到 CoreAnimation

## 📦 安装

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/your-repo/EnergyShape.git", from: "1.0.0")
]
```

### 本地引用

在 Xcode 项目中：
1. File → Add Package Dependencies
2. 选择 "Add Local..."
3. 选择 EnergyShape 目录

## 🚀 快速开始

```swift
import EnergyShapeKit

// 创建能量视图
let energyView = EnergyShapeView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))

// 设置形状（任意 CGPath）
let path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 100, height: 100))
energyView.shapePath = path.cgPath

// 自定义配置（可选）
var config = EnergyConfig()
config.speed = 1.5
config.bloomEnabled = true
config.colorStops = [
    ColorStop(position: 0.0, color: .blue),
    ColorStop(position: 0.5, color: .purple),
    ColorStop(position: 1.0, color: .red)
]
energyView.config = config

// 添加到视图
view.addSubview(energyView)

// 开始动画
energyView.start()
```

## ⚙️ 配置参数

| 参数 | 类型 | 范围 | 默认值 | 说明 |
|------|------|------|--------|------|
| `speed` | Float | 0.1~3.0 | 1.0 | 流动速度 |
| `noiseStrength` | Float | 0~1.0 | 0.3 | 噪声强度 |
| `phaseScale` | Float | 0.5~5.0 | 2.0 | 相位缩放 |
| `glowIntensity` | Float | 0~2.0 | 0.5 | 发光强度 |
| `edgeBoost` | Float | 0~3.0 | 1.2 | 边缘增强 |
| `bloomEnabled` | Bool | - | true | 启用 Bloom |
| `bloomIntensity` | Float | 0~1.0 | 0.3 | Bloom 强度 |
| `bloomThreshold` | Float | 0~1.0 | 0.7 | Bloom 阈值 |
| `sdfEnabled` | Bool | - | true | 启用 SDF |

## 📁 项目结构

```
EnergyShape/
├── Package.swift                 # SwiftPM 配置
├── Sources/
│   └── EnergyShapeKit/
│       ├── EnergyConfig.swift        # 配置参数
│       ├── EnergyShapeView.swift     # 公开 API
│       ├── EnergyMetalRenderer.swift # Metal 渲染
│       ├── EnergyMaskCache.swift     # Mask/SDF 缓存
│       ├── EnergyStateMachine.swift  # 状态机
│       ├── TexturePool.swift         # 纹理复用池
│       └── Shaders.metal             # GPU 着色器
├── Tests/
│   └── EnergyShapeKitTests/
└── Demo/
    └── EnergyShape.xcodeproj         # Demo 工程
```

## 🔧 技术实现

### 渲染管线
1. **Mask 生成** - CGPath → 灰度位图
2. **SDF 生成** - 8SSEDT 算法计算有符号距离场
3. **能量场渲染** - FBM 噪声 + LUT 颜色映射
4. **Bloom 后处理** - 阈值提取 → 高斯模糊 → 合成

### 噪声算法
- Simplex Noise 2D
- FBM (Fractal Brownian Motion) 多层叠加

### 状态机
```
idle → startup → loop ⇄ settle → idle
       (1.2s)           (0.8s)
```

## 📱 系统要求

- iOS 14.0+
- Swift 5.9+
- 支持 Metal 的设备

## 📄 License

MIT License
