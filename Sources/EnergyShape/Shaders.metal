//
//  Shaders.metal
//  EnergyShape
//
//  Created by Sun on 2026/1/21.
//  能量动画 GPU 着色器 - 边框发光效果
//  采用 IDW (Inverse Distance Weighting) 算法实现颜色弥散
//

#include <metal_stdlib>
using namespace metal;

// MARK: - 常量定义

#define MAX_COLOR_POINTS 8

// MARK: - 数据结构

/// 顶点输出 / 片段输入
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

/// 颜色点数据（位置 + 颜色）
struct ColorPoint {
    float2 position;  // UV 坐标空间的位置 [0, 1]
    float4 color;     // RGBA 颜色
};

/// 能量场 Uniform 参数（IDW 弥散）
struct EnergyUniforms {
    float time;              // 当前时间
    float speed;             // 动画速度
    float noiseStrength;     // 噪声强度（用于颜色位置扰动）
    float phaseScale;        // 相位缩放（噪声细节缩放）
    float glowIntensity;     // 发光强度
    float edgeBoost;         // 边缘增强倍数
    float intensity;         // 整体强度（由状态机控制）
    float ditherEnabled;     // 抖动开关
    float2 resolution;       // 分辨率
    float2 texelSize;        // 像素尺寸
    int noiseOctaves;        // 噪声层数
    int padding;             // 16 字节对齐
    
    // 6 个颜色停靠点（RGBA + position）- 用于 LUT 生成
    float4 color0;
    float color0Pos;
    float4 color1;
    float color1Pos;
    float4 color2;
    float color2Pos;
    float4 color3;
    float color3Pos;
    float4 color4;
    float color4Pos;
    float4 color5;
    float color5Pos;
    
    // 边框发光参数
    float borderWidth;       // 边框宽度（像素单位）
    float innerGlowIntensity; // 内发光强度
    float innerGlowRange;    // 内发光范围（像素单位）
    float outerGlowIntensity; // 外发光强度
    float outerGlowRange;    // 外发光范围（像素单位）
    float colorFlowSpeed;    // 颜色流动速度
    
    // SDF 距离参数（用于单位统一）
    float sdfMaxDist;        // SDF 最大距离（像素单位）
    float colorOffset;       // 颜色整体偏移（替代排序）
    
    // IDW 弥散参数
    float diffusionBias;     // IDW 偏置（控制模糊度）
    float diffusionPower;    // IDW 距离衰减指数
    int colorPointCount;     // 实际颜色点数量
    int padding2;            // 对齐
    
    // 颜色点数组（最多 8 个）
    float2 colorPointPositions[MAX_COLOR_POINTS];
    float4 colorPointColors[MAX_COLOR_POINTS];
};

/// 解析形状参数（用于在 Shader 中实时计算 SDF）
/// 注意：需要与 Swift 端的 ShaderAnalyticShapeParams 结构体对齐
struct AnalyticShapeParams {
    int shapeType;           // 0=圆角矩形, 1=圆形, 2=椭圆, 3=胶囊
    int padding1;            // 对齐填充
    float2 viewSize;         // 视图尺寸（像素）
    float2 center;           // 形状中心（归一化 0-1）
    float2 halfSize;         // 半尺寸（归一化）
    float cornerRadius;      // 圆角半径（归一化）
    float padding2;          // 对齐填充
    float2 radius;           // 圆形/椭圆半径（归一化）
    int isVertical;          // 是否垂直胶囊
    int padding3;            // 对齐填充
};

/// Bloom Uniform 参数
struct BloomUniforms {
    float threshold;
    float intensity;
    float2 texelSize;
    int blurRadius;
    int isHorizontal;
};

// MARK: - 解析 SDF 函数（Inigo Quilez 经典实现）

/// 圆角矩形 SDF
/// p: 相对于形状中心的坐标
/// b: 矩形半尺寸
/// r: 圆角半径
float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

/// 圆形 SDF
float sdCircle(float2 p, float r) {
    return length(p) - r;
}

/// 椭圆 SDF（近似）
float sdEllipse(float2 p, float2 ab) {
    // 归一化到单位圆
    float2 pn = p / ab;
    float dist = length(pn) - 1.0;
    // 缩放回原始空间
    return dist * min(ab.x, ab.y);
}

/// 胶囊 SDF
float sdCapsule(float2 p, float2 a, float2 b, float r) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

/// 计算解析形状的 SDF
/// 返回有符号距离（像素单位），负数表示内部
float computeAnalyticSDF(float2 uv, constant AnalyticShapeParams& shape) {
    // 转换到像素坐标
    float2 pixelCoord = uv * shape.viewSize;
    float2 centerPixel = shape.center * shape.viewSize;
    float2 p = pixelCoord - centerPixel;
    
    float minDim = min(shape.viewSize.x, shape.viewSize.y);
    
    switch (shape.shapeType) {
        case 0: {
            // 圆角矩形
            float2 halfSizePixel = shape.halfSize * shape.viewSize;
            float cornerRadiusPixel = shape.cornerRadius * minDim;
            return sdRoundedBox(p, halfSizePixel, cornerRadiusPixel);
        }
        case 1: {
            // 圆形
            float radiusPixel = shape.radius.x * shape.viewSize.x;
            return sdCircle(p, radiusPixel);
        }
        case 2: {
            // 椭圆
            float2 radiusPixel = shape.radius * shape.viewSize;
            return sdEllipse(p, radiusPixel);
        }
        case 3: {
            // 胶囊
            float2 halfSizePixel = shape.halfSize * shape.viewSize;
            float r = min(halfSizePixel.x, halfSizePixel.y);
            if (shape.isVertical) {
                float2 a = float2(0, -halfSizePixel.y + r);
                float2 b = float2(0, halfSizePixel.y - r);
                return sdCapsule(p, a, b, r);
            } else {
                float2 a = float2(-halfSizePixel.x + r, 0);
                float2 b = float2(halfSizePixel.x - r, 0);
                return sdCapsule(p, a, b, r);
            }
        }
        default:
            return 0.0;
    }
}

/// 计算解析 SDF 的梯度（法线方向）
/// 使用有限差分法计算
float2 computeAnalyticSDFGradient(float2 uv, constant AnalyticShapeParams& shape) {
    float eps = 0.001;  // UV 空间的小偏移量
    float dx = computeAnalyticSDF(uv + float2(eps, 0), shape) - computeAnalyticSDF(uv - float2(eps, 0), shape);
    float dy = computeAnalyticSDF(uv + float2(0, eps), shape) - computeAnalyticSDF(uv - float2(0, eps), shape);
    float2 grad = float2(dx, dy);
    float gradLen = length(grad);
    return gradLen > 0.0001 ? grad / gradLen : float2(0, 0);
}

/// 将外部点投影到边缘上
/// 返回边缘上最近点的 UV 坐标
float2 projectToEdge(float2 uv, float signedDist, constant AnalyticShapeParams& shape, float2 viewSize) {
    if (signedDist <= 0.0) {
        // 已经在内部或边缘上
        return uv;
    }
    
    // 计算梯度方向（指向外部）
    float2 gradient = computeAnalyticSDFGradient(uv, shape);
    
    // 将像素距离转换为 UV 距离
    float2 uvDist = signedDist / viewSize;
    
    // 沿梯度反方向移动到边缘
    float2 edgeUV = uv - gradient * length(uvDist);
    
    // 限制在有效 UV 范围内
    return clamp(edgeUV, float2(0.0), float2(1.0));
}

/// 使用 SDF 纹理计算边缘投影
/// 通过采样 SDF 梯度来找到边缘方向
float2 projectToEdgeTexture(float2 uv, float outerDist, texture2d<float> sdfTexture, sampler texSampler, float2 texelSize, float sdfMaxDist) {
    if (outerDist <= 0.0) {
        return uv;
    }
    
    // 使用有限差分计算 SDF 梯度
    float eps = texelSize.x * 2.0;
    float sdfL = sdfTexture.sample(texSampler, uv + float2(-eps, 0)).r;
    float sdfR = sdfTexture.sample(texSampler, uv + float2(eps, 0)).r;
    float sdfT = sdfTexture.sample(texSampler, uv + float2(0, -eps)).r;
    float sdfB = sdfTexture.sample(texSampler, uv + float2(0, eps)).r;
    
    float2 gradient = float2(sdfR - sdfL, sdfB - sdfT);
    float gradLen = length(gradient);
    
    if (gradLen < 0.0001) {
        return uv;
    }
    
    // 归一化梯度
    gradient /= gradLen;
    
    // 将像素距离转换为 UV 距离（近似）
    float uvDist = outerDist / sdfMaxDist * 0.5;  // SDF 纹理编码范围是 [0, 0.5]
    
    // 沿梯度反方向移动到边缘
    float2 edgeUV = uv + gradient * uvDist;
    
    return clamp(edgeUV, float2(0.0), float2(1.0));
}

// MARK: - JFA Compute Kernels

/// JFA 种子点初始化
/// 从 Mask 纹理提取边缘像素作为种子点
kernel void jfaSeedInit(
    texture2d<float, access::read> maskTexture [[texture(0)]],
    texture2d<float, access::write> seedTexture [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float mask = maskTexture.read(gid).r;
    
    // 检查是否在边缘（通过检查邻居）
    int width = maskTexture.get_width();
    int height = maskTexture.get_height();
    
    bool isEdge = false;
    if (mask > 0.1) {
        // 检查 4 邻域
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                if (dx == 0 && dy == 0) continue;
                int nx = clamp(int(gid.x) + dx, 0, width - 1);
                int ny = clamp(int(gid.y) + dy, 0, height - 1);
                float neighborMask = maskTexture.read(uint2(nx, ny)).r;
                if (neighborMask < 0.1) {
                    isEdge = true;
                    break;
                }
            }
            if (isEdge) break;
        }
    }
    
    if (isEdge) {
        // 边缘像素：存储自己的坐标
        seedTexture.write(float4(float(gid.x), float(gid.y), 0, 0), gid);
    } else {
        // 非边缘像素：存储无效坐标
        seedTexture.write(float4(-1, -1, 0, 0), gid);
    }
}

/// JFA 洪泛传播
kernel void jfaFlood(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant int& stepSize [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    int width = inputTexture.get_width();
    int height = inputTexture.get_height();
    
    float2 currentSeed = inputTexture.read(gid).xy;
    float2 currentPos = float2(gid);
    
    // 计算当前最佳距离
    float bestDist = 1e10;
    float2 bestSeed = currentSeed;
    
    if (currentSeed.x >= 0) {
        bestDist = length(currentPos - currentSeed);
        bestSeed = currentSeed;
    }
    
    // 检查 8 个方向的邻居
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            
            int nx = int(gid.x) + dx * stepSize;
            int ny = int(gid.y) + dy * stepSize;
            
            if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
            
            float2 neighborSeed = inputTexture.read(uint2(nx, ny)).xy;
            
            if (neighborSeed.x >= 0) {
                float dist = length(currentPos - neighborSeed);
                if (dist < bestDist) {
                    bestDist = dist;
                    bestSeed = neighborSeed;
                }
            }
        }
    }
    
    outputTexture.write(float4(bestSeed, 0, 0), gid);
}

/// JFA 结果转换为 SDF
kernel void jfaToSDF(
    texture2d<float, access::read> jfaTexture [[texture(0)]],
    texture2d<float, access::read> maskTexture [[texture(1)]],
    texture2d<float, access::write> sdfTexture [[texture(2)]],
    constant float& maxDist [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float2 seed = jfaTexture.read(gid).xy;
    float mask = maskTexture.read(gid).r;
    
    float dist = 0;
    if (seed.x >= 0) {
        dist = length(float2(gid) - seed);
    }
    
    // 有符号距离：内部为正，外部为负
    float signedDist = (mask > 0.5) ? dist : -dist;
    
    // 归一化到 [0, 1]，0.5 表示边缘
    float normalized = (signedDist / maxDist + 1.0) * 0.5;
    normalized = clamp(normalized, 0.0, 1.0);
    
    sdfTexture.write(float4(normalized, 0, 0, 1), gid);
}

// MARK: - 辅助函数

/// 伪随机数
float random(float2 st) {
    return fract(sin(dot(st, float2(12.9898, 78.233))) * 43758.5453123);
}

/// 平滑噪声（用于颜色位置扰动）
/// 支持多层 octaves 叠加
float smoothNoise(float2 p, float time) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = random(i + float2(0.0, 0.0) + time);
    float b = random(i + float2(1.0, 0.0) + time);
    float c = random(i + float2(0.0, 1.0) + time);
    float d = random(i + float2(1.0, 1.0) + time);
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

/// 分形噪声（FBM）- 支持 noiseOctaves 参数
float fbmNoise(float2 p, float time, int octaves, float phaseScale) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = phaseScale;
    
    for (int i = 0; i < octaves; i++) {
        value += amplitude * smoothNoise(p * frequency, time);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    
    return value;
}

/// 从渐变中采样颜色（支持动态位置 + 颜色整体偏移）
float4 sampleGradient(float t, constant EnergyUniforms& u) {
    // 应用颜色整体偏移（替代排序跳变）
    t = fract(t + u.colorOffset);
    
    // 颜色和位置数组
    float4 colors[6] = { u.color0, u.color1, u.color2, u.color3, u.color4, u.color5 };
    float positions[6] = { u.color0Pos, u.color1Pos, u.color2Pos, u.color3Pos, u.color4Pos, u.color5Pos };
    
    // 找到 t 所在的区间
    int idx = 0;
    for (int i = 0; i < 5; i++) {
        if (t >= positions[i] && t < positions[i + 1]) {
            idx = i;
            break;
        }
        if (i == 4) idx = 4; // 最后一个区间
    }
    
    // 在区间内插值
    float localT = (t - positions[idx]) / max(positions[idx + 1] - positions[idx], 0.001);
    localT = clamp(localT, 0.0, 1.0);
    
    // 平滑插值
    localT = localT * localT * (3.0 - 2.0 * localT);
    
    return mix(colors[idx], colors[idx + 1], localT);
}

/// 从 LUT 纹理采样颜色
float4 sampleLUT(float t, texture2d<float> lutTexture, sampler texSampler) {
    t = fract(t);
    return lutTexture.sample(texSampler, float2(t, 0.5));
}

// MARK: - IDW 颜色弥散算法（DiffusionKit 风格）

/// 使用反距离加权 (IDW) 算法混合多个颜色点
/// 实现自然的墨水扩散效果
/// - uv: 当前像素的 UV 坐标
/// - uniforms: 包含颜色点位置和颜色的参数
/// - Returns: 混合后的颜色
float4 blendColorsIDW(float2 uv, constant EnergyUniforms& uniforms) {
    if (uniforms.colorPointCount <= 0) {
        return float4(0.5, 0.5, 0.5, 1.0);
    }
    
    float totalContribution = 0.0;
    float4 blendedColor = float4(0.0);
    
    // 计算每个颜色点对当前像素的贡献
    for (int i = 0; i < uniforms.colorPointCount && i < MAX_COLOR_POINTS; i++) {
        float2 pointPos = uniforms.colorPointPositions[i];
        float4 pointColor = uniforms.colorPointColors[i];
        
        // 计算到颜色点的距离
        float dist = length(uv - pointPos);
        
        // IDW 核心公式：贡献 = 1 / (bias + dist^power)
        // bias 防止距离为零时除以零，同时控制扩散模糊度
        // power 控制距离衰减速度
        float contribution = 1.0 / (uniforms.diffusionBias + pow(dist, uniforms.diffusionPower));
        
        blendedColor += pointColor * contribution;
        totalContribution += contribution;
    }
    
    // 归一化颜色
    if (totalContribution > 0.0) {
        blendedColor /= totalContribution;
    }
    
    return blendedColor;
}

// MARK: - 顶点着色器

vertex VertexOut vertexFullscreen(uint vertexID [[vertex_id]]) {
    float2 positions[6] = {
        float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
        float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0)
    };
    
    float2 texCoords[6] = {
        float2(0.0, 1.0), float2(1.0, 1.0), float2(0.0, 0.0),
        float2(0.0, 0.0), float2(1.0, 1.0), float2(1.0, 0.0)
    };
    
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

// MARK: - 边框发光效果

/// 计算沿边缘轮廓的位置参数，减少角落拥挤
/// 使用改进的边缘参数化方法，让颜色沿边缘更均匀流动
/// 
/// 改进思路：
/// 1. 对于圆角矩形，使用边长 + 圆角弧长的线性距离来计算位置
/// 2. 通过 SDF 梯度方向判断当前位于哪条边或圆角
/// 3. 避免纯 atan2 导致的角落密集问题
float calculateEdgePosition(float2 uv, texture2d<float> sdfTexture, sampler texSampler, float2 texelSize) {
    // 使用 Sobel 算子计算 SDF 梯度（采样更大范围获得更平滑的结果）
    float2 offset1 = texelSize * 1.5;
    float2 offset2 = texelSize * 3.0;
    
    // 多采样平滑
    float sdfL1 = sdfTexture.sample(texSampler, uv + float2(-offset1.x, 0)).r;
    float sdfR1 = sdfTexture.sample(texSampler, uv + float2(offset1.x, 0)).r;
    float sdfT1 = sdfTexture.sample(texSampler, uv + float2(0, -offset1.y)).r;
    float sdfB1 = sdfTexture.sample(texSampler, uv + float2(0, offset1.y)).r;
    
    float sdfL2 = sdfTexture.sample(texSampler, uv + float2(-offset2.x, 0)).r;
    float sdfR2 = sdfTexture.sample(texSampler, uv + float2(offset2.x, 0)).r;
    float sdfT2 = sdfTexture.sample(texSampler, uv + float2(0, -offset2.y)).r;
    float sdfB2 = sdfTexture.sample(texSampler, uv + float2(0, offset2.y)).r;
    
    // 加权平均梯度
    float gradX = (sdfR1 - sdfL1) * 0.6 + (sdfR2 - sdfL2) * 0.4;
    float gradY = (sdfB1 - sdfT1) * 0.6 + (sdfB2 - sdfT2) * 0.4;
    
    float2 gradient = float2(gradX, gradY);
    float gradLen = length(gradient);
    
    // 中心坐标 [-1, 1]
    float2 centered = uv * 2.0 - 1.0;
    float absX = abs(centered.x);
    float absY = abs(centered.y);
    
    if (gradLen < 0.001) {
        // 梯度太小时的备选方案
        float baseAngle = atan2(centered.y, centered.x);
        return (baseAngle + M_PI_F) / (2.0 * M_PI_F);
    }
    
    // 计算基于边缘位置的参数化（改进的圆角矩形处理）
    // 将矩形周长分成 4 段，每段对应一条边 + 相邻圆角
    // 这样角落不会过度密集
    
    float baseAngle = atan2(centered.y, centered.x);
    float normalizedAngle = (baseAngle + M_PI_F) / (2.0 * M_PI_F); // [0, 1]
    
    // 对角落区域进行拉伸补偿，减少密集感
    // 检测是否在角落区域（x 和 y 都接近边缘）
    float cornerThreshold = 0.7;
    float isCorner = smoothstep(cornerThreshold, 1.0, absX) * smoothstep(cornerThreshold, 1.0, absY);
    
    // 在角落区域适当拉伸颜色分布
    // 使用梯度方向来调整角落的颜色位置
    float2 normGradient = gradient / gradLen;
    float gradAngle = atan2(normGradient.y, normGradient.x);
    float gradInfluence = (gradAngle + M_PI_F) / (2.0 * M_PI_F);
    
    // 混合：非角落区域使用 UV 角度，角落区域融入梯度信息
    float edgePosition = mix(normalizedAngle, gradInfluence, isCorner * 0.3);
    
    return edgePosition;
}

/// 主能量场渲染 - 边框发光效果
/// 
/// 效果描述：
/// 1. 沿着形状轮廓边缘均匀发光
/// 2. 发光从边缘向内部扩散，向中心逐渐减弱
/// 3. 多颜色沿边缘缓慢混合流动（墨水扩散效果）
/// 4. 外发光可选开启
fragment float4 fragmentEnergy(
    VertexOut in [[stage_in]],
    texture2d<float> maskTexture [[texture(0)]],
    texture2d<float> sdfTexture [[texture(1)]],
    texture2d<float> lutTexture [[texture(2)]],
    constant EnergyUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    float2 uv = in.texCoord;

    // 1. 采样 SDF - 使用双线性插值获得平滑的距离值
    float sdf = sdfTexture.sample(texSampler, uv).r;

    // SDF 转换：sdf=0.5 表示边缘，<0.5 表示外部，>0.5 表示内部
    // distToEdgePx: 正数表示内部，负数表示外部
    float distNorm = (sdf - 0.5) * 2.0;
    float signedDistPx = distNorm * uniforms.sdfMaxDist;
    
    // 2. 计算抗锯齿过渡宽度（增加系数使边缘更平滑）
    float aaWidth = fwidth(signedDistPx) * 2.5;
    
    // 3. 内部/外部距离
    float innerDist = max(0.0, signedDistPx);
    float outerDist = max(0.0, -signedDistPx);
    
    // 4. 检查外发光是否启用
    bool outerGlowEnabled = uniforms.outerGlowIntensity > 0.001 && uniforms.outerGlowRange > 0.001;
    
    // 5. 形状外部处理
    if (signedDistPx < 0.0) {
        // 在形状外部
        if (!outerGlowEnabled) {
            // 外发光关闭：只在抗锯齿过渡带内渲染
            if (outerDist > aaWidth) {
                return float4(0.0);
            }
        } else {
            // 外发光开启：超出外发光范围则不渲染
            if (outerDist > uniforms.outerGlowRange) {
                return float4(0.0);
            }
        }
    }
    
    // 6. 边框发光（仅在内部，从边缘向内衰减）
    float borderGlow = 0.0;
    if (signedDistPx >= 0.0) {
        borderGlow = exp(-innerDist / max(uniforms.borderWidth, 1.0)) * uniforms.glowIntensity;
    }
    
    // 7. 内发光（从边缘向内部扩散，仅在内部）
    float innerGlow = 0.0;
    if (signedDistPx >= 0.0) {
        innerGlow = exp(-innerDist / max(uniforms.innerGlowRange, 1.0)) * uniforms.innerGlowIntensity;
    }
    
    // 8. 外发光（从边缘向外部扩散）- 仅在启用且在外部时计算
    float outerGlow = 0.0;
    float outerGlowFactor = 0.0;  // 用于颜色衰减
    if (outerGlowEnabled && signedDistPx < 0.0) {
        // 使用更陡峭的衰减曲线
        float normalizedDist = outerDist / uniforms.outerGlowRange;
        outerGlowFactor = 1.0 - smoothstep(0.0, 1.0, normalizedDist);
        outerGlowFactor = outerGlowFactor * outerGlowFactor;
        outerGlow = outerGlowFactor * uniforms.outerGlowIntensity;
    }
    
    // 9. 组合所有发光效果
    float totalGlow = borderGlow + innerGlow + outerGlow;
    
    // 边缘增强（仅在内部边缘附近）
    if (signedDistPx >= 0.0 && innerDist < uniforms.borderWidth * 3.0) {
        totalGlow *= (1.0 + uniforms.edgeBoost * exp(-innerDist * 0.3));
    }
    
    // 10. 计算最终 alpha
    float finalAlpha = 1.0;
    if (signedDistPx < 0.0) {
        // 在形状外部：alpha 由外发光衰减决定
        if (outerGlowEnabled) {
            finalAlpha = outerGlowFactor;
        } else {
            finalAlpha = 1.0 - smoothstep(0.0, aaWidth, outerDist);
        }
    }
    
    if (totalGlow < 0.001 && finalAlpha < 0.001) {
        return float4(0.0);
    }

    // 11. 计算颜色
    // 对于外部区域，使用边缘投影的 UV 来获取颜色，实现与内发光一致的效果
    float2 colorUV = uv;
    if (outerGlowEnabled && signedDistPx < 0.0) {
        // 外发光区域：投影到边缘获取颜色
        float2 texelSize = float2(1.0 / sdfTexture.get_width(), 1.0 / sdfTexture.get_height());
        colorUV = projectToEdgeTexture(uv, outerDist, sdfTexture, texSampler, texelSize, uniforms.sdfMaxDist);
    }
    
    // 使用 IDW 算法混合颜色（DiffusionKit 风格弥散）
    float4 gradientColor = blendColorsIDW(colorUV, uniforms);

    // 12. 最终颜色
    float4 finalColor = gradientColor * totalGlow * uniforms.intensity;
    finalColor.a = clamp(totalGlow * uniforms.intensity * finalAlpha, 0.0, 1.0);

    // 13. Dithering（减少色带）
    if (uniforms.ditherEnabled > 0.5) {
        float dither = (random(uv + uniforms.time) - 0.5) / 255.0;
        finalColor.rgb += dither;
    }

    finalColor.rgb = max(finalColor.rgb, float3(0.0));
    return finalColor;
}

/// 解析 SDF 版本 - 使用数学公式实时计算 SDF
/// 适用于圆角矩形、圆形、椭圆等简单形状
/// 优点：零延迟、完美平滑边缘、无内存占用
fragment float4 fragmentEnergyAnalytic(
    VertexOut in [[stage_in]],
    texture2d<float> lutTexture [[texture(0)]],
    constant EnergyUniforms& uniforms [[buffer(0)]],
    constant AnalyticShapeParams& shape [[buffer(1)]]
) {
    // 注：lutTexture 参数保留以保持管线兼容性，IDW 模式下不使用
    float2 uv = in.texCoord;

    // 1. 使用数学公式计算 SDF（像素单位）
    // SDF 惯例：负数表示内部，正数表示外部
    float signedDistPx = computeAnalyticSDF(uv, shape);
    
    // 2. 计算抗锯齿过渡宽度（基于屏幕像素）
    float aaWidth = fwidth(signedDistPx) * 2.5;  // 2.5 像素宽的平滑带，使边缘更平滑
    
    // 3. 边缘到内部的距离（正数表示在内部）
    float innerDist = max(0.0, -signedDistPx);
    
    // 4. 边缘到外部的距离（正数表示在外部）
    float outerDist = max(0.0, signedDistPx);
    
    // 5. 检查外发光是否启用（强度 > 0 且范围 > 0）
    bool outerGlowEnabled = uniforms.outerGlowIntensity > 0.001 && uniforms.outerGlowRange > 0.001;
    
    // 6. 形状外部处理
    if (signedDistPx > 0.0) {
        // 在形状外部
        if (!outerGlowEnabled) {
            // 外发光关闭：只在抗锯齿过渡带内渲染
            if (signedDistPx > aaWidth) {
                return float4(0.0);
            }
        } else {
            // 外发光开启：超出外发光范围则不渲染
            if (outerDist > uniforms.outerGlowRange) {
                return float4(0.0);
            }
        }
    }
    
    // 7. 边框发光（仅在内部，从边缘向内衰减）
    float borderGlow = 0.0;
    if (signedDistPx <= 0.0) {
        // 在内部：边缘处最亮，向内衰减
        borderGlow = exp(-innerDist / max(uniforms.borderWidth, 1.0)) * uniforms.glowIntensity;
    }
    
    // 8. 内发光（从边缘向内部扩散，仅在内部）
    float innerGlow = 0.0;
    if (signedDistPx <= 0.0) {
        innerGlow = exp(-innerDist / max(uniforms.innerGlowRange, 1.0)) * uniforms.innerGlowIntensity;
    }
    
    // 9. 外发光（从边缘向外部扩散）- 仅在启用且在外部时计算
    float outerGlow = 0.0;
    float outerGlowFactor = 0.0;  // 用于颜色衰减
    if (outerGlowEnabled && signedDistPx > 0.0) {
        // 使用更陡峭的衰减曲线：距离归一化 + 平方衰减
        float normalizedDist = outerDist / uniforms.outerGlowRange;
        // 使用 smoothstep 实现更自然的衰减（边缘最亮，向外快速衰减）
        outerGlowFactor = 1.0 - smoothstep(0.0, 1.0, normalizedDist);
        // 再进行平方使衰减更陡峭
        outerGlowFactor = outerGlowFactor * outerGlowFactor;
        outerGlow = outerGlowFactor * uniforms.outerGlowIntensity;
    }
    
    // 10. 组合所有发光效果
    float totalGlow = borderGlow + innerGlow + outerGlow;
    
    // 边缘增强（仅在内部边缘附近）
    if (signedDistPx <= 0.0 && innerDist < uniforms.borderWidth * 3.0) {
        totalGlow *= (1.0 + uniforms.edgeBoost * exp(-innerDist * 0.3));
    }
    
    // 11. 计算最终 alpha
    float finalAlpha = 1.0;
    if (signedDistPx > 0.0) {
        // 在形状外部：alpha 由外发光衰减决定
        if (outerGlowEnabled) {
            // 使用与 outerGlow 相同的衰减因子
            finalAlpha = outerGlowFactor;
        } else {
            // 外发光关闭：只在抗锯齿带内平滑过渡
            finalAlpha = 1.0 - smoothstep(0.0, aaWidth, signedDistPx);
        }
    }
    
    if (totalGlow < 0.001 && finalAlpha < 0.001) {
        return float4(0.0);
    }

    // 12. 计算颜色
    // 对于外部区域，使用边缘投影的 UV 来获取颜色，实现与内发光一致的效果
    float2 colorUV = uv;
    if (outerGlowEnabled && signedDistPx > 0.0) {
        // 外发光区域：投影到边缘获取颜色
        colorUV = projectToEdge(uv, signedDistPx, shape, shape.viewSize);
    }
    
    // 使用 IDW 算法混合颜色（DiffusionKit 风格弥散）
    float4 gradientColor = blendColorsIDW(colorUV, uniforms);

    // 13. 最终颜色
    float4 finalColor = gradientColor * totalGlow * uniforms.intensity;
    finalColor.a = clamp(totalGlow * uniforms.intensity * finalAlpha, 0.0, 1.0);

    // 14. Dithering
    if (uniforms.ditherEnabled > 0.5) {
        float dither = (random(uv + uniforms.time) - 0.5) / 255.0;
        finalColor.rgb += dither;
    }

    finalColor.rgb = max(finalColor.rgb, float3(0.0));
    return finalColor;
}

/// 无 SDF 版本
fragment float4 fragmentEnergyNoSDF(
    VertexOut in [[stage_in]],
    texture2d<float> maskTexture [[texture(0)]],
    texture2d<float> lutTexture [[texture(1)]],
    constant EnergyUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    
    float2 uv = in.texCoord;
    
    // 1. 采样 Mask（使用多采样平滑）
    float2 texelSize = uniforms.texelSize;
    float mask = 0.0;
    
    // 3x3 高斯核平滑采样
    float weights[9] = { 1.0, 2.0, 1.0, 2.0, 4.0, 2.0, 1.0, 2.0, 1.0 };
    float totalWeight = 0.0;
    int idx = 0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 offset = float2(float(dx), float(dy)) * texelSize;
            float w = weights[idx++];
            mask += maskTexture.sample(texSampler, uv + offset).r * w;
            totalWeight += w;
        }
    }
    mask /= totalWeight;
    
    // 计算边缘强度（用于检测边缘位置）
    float maskL = maskTexture.sample(texSampler, uv + float2(-texelSize.x * 2.0, 0)).r;
    float maskR = maskTexture.sample(texSampler, uv + float2(texelSize.x * 2.0, 0)).r;
    float maskT = maskTexture.sample(texSampler, uv + float2(0, -texelSize.y * 2.0)).r;
    float maskB = maskTexture.sample(texSampler, uv + float2(0, texelSize.y * 2.0)).r;
    
    float gradMag = length(float2(maskR - maskL, maskB - maskT));
    float edgeStrength = smoothstep(0.0, 0.2, gradMag);
    
    // 2. 估算距离边缘的深度（无 SDF 时使用 mask 梯度估算）
    // depth: 正数表示内部，负数表示外部
    float depth = (mask - 0.5) * 2.0;
    float absDepth = abs(depth);
    
    // 3. 边框核心发光
    float borderGlow = exp(-absDepth * 10.0 / max(uniforms.borderWidth, 0.1)) * uniforms.glowIntensity;
    borderGlow = max(borderGlow, edgeStrength * 0.8 * uniforms.glowIntensity);
    
    // 4. 内发光（从边缘向内部扩散）
    float innerDist = max(0.0, depth);
    float innerGlow = exp(-innerDist * 5.0 / max(uniforms.innerGlowRange, 0.01)) * uniforms.innerGlowIntensity;
    
    // 5. 外发光（从边缘向外部扩散）
    float outerDist = max(0.0, -depth);
    float outerGlow = exp(-outerDist * 5.0 / max(uniforms.outerGlowRange, 0.01)) * uniforms.outerGlowIntensity;
    
    // 6. 组合所有发光效果
    float totalGlow = borderGlow + innerGlow + outerGlow;
    
    // 边缘增强
    totalGlow *= (1.0 + uniforms.edgeBoost * edgeStrength);
    
    // 提前剔除低强度像素
    if (totalGlow < 0.001) {
        return float4(0.0);
    }
    
    // 7. 计算边缘位置
    float2 normalizedUV = uv * 2.0 - 1.0;
    float angle = atan2(normalizedUV.y, normalizedUV.x);
    float edgePosition = (angle + M_PI_F) / (2.0 * M_PI_F);
    
    // 8. 动画
    float flowSpeed = uniforms.colorFlowSpeed;
    float animatedPosition = fract(edgePosition + uniforms.time * flowSpeed);
    
    // 使用分形噪声
    float noise = fbmNoise(uv * uniforms.phaseScale, uniforms.time * 0.15, uniforms.noiseOctaves, 2.0);
    animatedPosition = fract(animatedPosition + noise * uniforms.noiseStrength * 0.1);
    
    // 9. 从 LUT 采样颜色
    float4 gradientColor = sampleLUT(animatedPosition, lutTexture, texSampler);
    
    // 10. 最终颜色（HDR 输出）
    float4 finalColor = gradientColor * totalGlow * uniforms.intensity;
    finalColor.a = clamp(totalGlow * uniforms.intensity, 0.0, 1.0);
    
    // 11. Dithering
    if (uniforms.ditherEnabled > 0.5) {
        float dither = (random(uv + uniforms.time) - 0.5) / 255.0;
        finalColor.rgb += dither;
    }
    
    finalColor.rgb = max(finalColor.rgb, float3(0.0));
    
    return finalColor;
}

// MARK: - Bloom 着色器

/// Bloom 阈值提取
fragment float4 fragmentBloomThreshold(
    VertexOut in [[stage_in]],
    texture2d<float> inputTexture [[texture(0)]],
    constant BloomUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    
    float4 color = inputTexture.sample(texSampler, in.texCoord);
    float brightness = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    
    if (brightness > uniforms.threshold) {
        float softness = 0.1;
        float contribution = smoothstep(uniforms.threshold - softness, uniforms.threshold + softness, brightness);
        return color * contribution;
    }
    
    return float4(0.0);
}

/// 高斯模糊权重
float gaussianWeight(int offset, int radius) {
    float sigma = float(radius) / 2.0;
    float x = float(offset);
    return exp(-(x * x) / (2.0 * sigma * sigma));
}

/// 分离式高斯模糊
fragment float4 fragmentBloomBlur(
    VertexOut in [[stage_in]],
    texture2d<float> inputTexture [[texture(0)]],
    constant BloomUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    
    float2 uv = in.texCoord;
    float4 result = float4(0.0);
    float totalWeight = 0.0;
    
    int radius = uniforms.blurRadius;
    float2 direction = uniforms.isHorizontal > 0
        ? float2(uniforms.texelSize.x, 0.0)
        : float2(0.0, uniforms.texelSize.y);
    
    for (int i = -radius; i <= radius; i++) {
        float2 offset = direction * float(i);
        float weight = gaussianWeight(i, radius);
        result += inputTexture.sample(texSampler, uv + offset) * weight;
        totalWeight += weight;
    }
    
    return result / totalWeight;
}

/// Bloom 合成（带 Tone Mapping）
fragment float4 fragmentBloomComposite(
    VertexOut in [[stage_in]],
    texture2d<float> mainTexture [[texture(0)]],
    texture2d<float> bloomTexture [[texture(1)]],
    constant BloomUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    
    float4 mainColor = mainTexture.sample(texSampler, in.texCoord);
    float4 bloomColor = bloomTexture.sample(texSampler, in.texCoord);
    
    // HDR 合成
    float3 hdr = mainColor.rgb + bloomColor.rgb * uniforms.intensity;
    
    // Reinhard Tone Mapping（替代硬截断）
    // 保留高光细节，避免 min(1.0) 导致的高光损失
    float3 mapped = hdr / (1.0 + hdr);
    
    // 可选：使用曝光参数的 tone mapping
    // float exposure = 1.2;
    // float3 mapped = 1.0 - exp(-hdr * exposure);
    
    float4 result;
    result.rgb = mapped;
    result.a = clamp(mainColor.a + bloomColor.a * uniforms.intensity * 0.5, 0.0, 1.0);
    
    return result;
}

// MARK: - 辅助着色器

fragment float4 fragmentCopy(
    VertexOut in [[stage_in]],
    texture2d<float> inputTexture [[texture(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    return inputTexture.sample(texSampler, in.texCoord);
}

fragment float4 fragmentClear(VertexOut in [[stage_in]]) {
    return float4(0.0);
}
