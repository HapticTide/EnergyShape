//
//  Shaders.metal
//  EnergyShapeKit
//
//  Created by Sun on 2026/1/21.
//  能量动画 GPU 着色器
//

#include <metal_stdlib>
using namespace metal;

// MARK: - 数据结构

/// 顶点输出 / 片段输入
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

/// 能量场 Uniform 参数
struct EnergyUniforms {
    float time;
    float speed;
    float noiseStrength;
    float phaseScale;
    float glowIntensity;
    float edgeBoost;
    float intensity;        // 由状态机控制的整体强度
    float ditherEnabled;    // 是否启用抖动
    float2 resolution;
    float2 texelSize;       // 1.0 / resolution
    int noiseOctaves;       // FBM 噪声层数
    int padding;            // 保持 16 字节对齐
};

/// Bloom Uniform 参数
struct BloomUniforms {
    float threshold;
    float intensity;
    float2 texelSize;
    int blurRadius;
    int isHorizontal;
};

// MARK: - 常量

constant float2 FLOW_DIRECTION = float2(0.7, 0.3);

/// 排列表（全局常量）
constant int permTable[256] = {
    151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,
    8,99,37,240,21,10,23,190,6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,
    35,11,32,57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,74,165,71,
    134,139,48,27,166,77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,
    55,46,245,40,244,102,143,54,65,25,63,161,1,216,80,73,209,76,132,187,208,89,
    18,169,200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,64,52,217,226,
    250,124,123,5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,
    189,28,42,223,183,170,213,119,248,152,2,44,154,163,70,221,153,101,155,167,43,
    172,9,129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,218,246,97,
    228,251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,235,249,14,239,
    107,49,192,214,31,181,199,106,157,184,84,204,176,115,121,50,45,127,4,150,254,
    138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180
};

// MARK: - 噪声函数

/// 伪随机数生成（用于 dithering）
float random(float2 st) {
    return fract(sin(dot(st, float2(12.9898, 78.233))) * 43758.5453123);
}

/// 2D 噪声插值辅助
float2 fade(float2 t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

/// 梯度函数
float grad(int hash, float2 p) {
    int h = hash & 7;
    float2 g;
    g.x = (h < 4) ? ((h & 1) ? 1.0 : -1.0) : 0.0;
    g.y = (h >= 4) ? ((h & 1) ? 1.0 : -1.0) : ((h & 2) ? 1.0 : -1.0);
    return dot(g, p);
}

/// 排列表（简化版）- 使用全局 permTable
int perm(int x) {
    return permTable[x & 255];
}

/// Perlin 噪声 2D
float perlinNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    
    int ix = int(i.x);
    int iy = int(i.y);
    
    float2 u = fade(f);
    
    int aa = perm(perm(ix) + iy);
    int ab = perm(perm(ix) + iy + 1);
    int ba = perm(perm(ix + 1) + iy);
    int bb = perm(perm(ix + 1) + iy + 1);
    
    float g00 = grad(aa, f);
    float g10 = grad(ba, f - float2(1.0, 0.0));
    float g01 = grad(ab, f - float2(0.0, 1.0));
    float g11 = grad(bb, f - float2(1.0, 1.0));
    
    float x1 = mix(g00, g10, u.x);
    float x2 = mix(g01, g11, u.x);
    
    return mix(x1, x2, u.y) * 0.5 + 0.5;
}

/// Simplex 噪声 2D（性能更优）
float simplexNoise(float2 v) {
    const float2 C = float2(0.211324865405187, 0.366025403784439);
    
    float2 i = floor(v + dot(v, C.yy));
    float2 x0 = v - i + dot(i, C.xx);
    
    float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float2 x1 = x0.xy - i1 + C.xx;
    float2 x2 = x0.xy - 1.0 + 2.0 * C.xx;
    
    i = fmod(i, 289.0);
    float3 p = fmod(
        fmod(float3(i.y, i.y + i1.y, i.y + 1.0) + 34.0, 289.0) *
        (float3(i.y, i.y + i1.y, i.y + 1.0) + 1.0),
        289.0
    );
    p = fmod(
        fmod(p + float3(i.x, i.x + i1.x, i.x + 1.0) + 34.0, 289.0) *
        (p + float3(i.x, i.x + i1.x, i.x + 1.0) + 1.0),
        289.0
    );
    
    float3 m = max(0.5 - float3(dot(x0, x0), dot(x1, x1), dot(x2, x2)), 0.0);
    m = m * m;
    m = m * m;
    
    float3 x = 2.0 * fract(p * (1.0 / 41.0)) - 1.0;
    float3 h = abs(x) - 0.5;
    float3 ox = floor(x + 0.5);
    float3 a0 = x - ox;
    
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    
    float3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.y = a0.y * x1.x + h.y * x1.y;
    g.z = a0.z * x2.x + h.z * x2.y;
    
    return 130.0 * dot(m, g) * 0.5 + 0.5;
}

/// FBM（Fractal Brownian Motion）多层噪声
float fbmNoise(float2 p, float time, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    float maxValue = 0.0;
    
    for (int i = 0; i < octaves && i < 4; i++) {
        float2 animatedP = p * frequency + float2(time * 0.1 * float(i + 1));
        value += amplitude * simplexNoise(animatedP);
        maxValue += amplitude;
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value / maxValue;
}

// MARK: - 顶点着色器

/// 全屏四边形顶点着色器
vertex VertexOut vertexFullscreen(
    uint vertexID [[vertex_id]]
) {
    // 生成全屏四边形（两个三角形组成）
    float2 positions[6] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2(-1.0,  1.0),
        float2( 1.0, -1.0),
        float2( 1.0,  1.0)
    };
    
    float2 texCoords[6] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(0.0, 0.0),
        float2(1.0, 1.0),
        float2(1.0, 0.0)
    };
    
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

// MARK: - 能量场片段着色器

/// 主能量场渲染
/// LUT 使用 2D 纹理（高度=1）以确保设备兼容性
fragment float4 fragmentEnergy(
    VertexOut in [[stage_in]],
    texture2d<float> maskTexture [[texture(0)]],
    texture2d<float> sdfTexture [[texture(1)]],
    texture2d<float> lutTexture [[texture(2)]],
    constant EnergyUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    constexpr sampler lutSampler(mag_filter::linear, min_filter::linear, address::repeat);
    
    float2 uv = in.texCoord;
    
    // 1. 采样 Mask
    float mask = maskTexture.sample(texSampler, uv).r;
    
    // 早期退出：完全透明区域
    if (mask < 0.001) {
        discard_fragment();
    }
    
    // 2. 生成多层 FBM 噪声
    float2 noiseUV = uv * 4.0;
    float noise = fbmNoise(noiseUV, uniforms.time, uniforms.noiseOctaves);
    
    // 3. 计算相位（核心流动效果）
    float2 flowDir = normalize(FLOW_DIRECTION);
    float phase = dot(uv, flowDir) * uniforms.phaseScale
                + uniforms.time * uniforms.speed
                + noise * uniforms.noiseStrength;
    
    // 4. 从 LUT 采样颜色（使用 2D 坐标，y=0.5）
    float lutCoord = fract(phase);
    float4 color = lutTexture.sample(lutSampler, float2(lutCoord, 0.5));
    
    // 5. SDF 边缘增强
    float sdf = sdfTexture.sample(texSampler, uv).r;
    // SDF 纹理中 0.5 表示边缘，>0.5 内部，<0.5 外部
    float distFromEdge = abs(sdf - 0.5) * 2.0;
    float edge = 1.0 - smoothstep(0.0, 0.3, distFromEdge);
    
    // 6. 应用边缘增强
    color.rgb += color.rgb * edge * uniforms.edgeBoost;
    
    // 7. Glow 效果
    float glow = edge * uniforms.glowIntensity;
    color.rgb += color.rgb * glow;
    
    // 8. 应用 Mask 和整体强度
    color.a = mask * uniforms.intensity;
    color.rgb *= color.a;
    
    // 9. Dithering 抗色带
    if (uniforms.ditherEnabled > 0.5) {
        float dither = (random(uv + uniforms.time) - 0.5) / 255.0;
        color.rgb += dither;
    }
    
    return color;
}

/// 无 SDF 版本（使用梯度近似边缘）
/// 无 SDF 版本（使用梯度近似边缘）
/// LUT 使用 2D 纹理（高度=1）以确保设备兼容性
fragment float4 fragmentEnergyNoSDF(
    VertexOut in [[stage_in]],
    texture2d<float> maskTexture [[texture(0)]],
    texture2d<float> lutTexture [[texture(1)]],
    constant EnergyUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    constexpr sampler lutSampler(mag_filter::linear, min_filter::linear, address::repeat);
    
    float2 uv = in.texCoord;
    
    // 1. 采样 Mask
    float mask = maskTexture.sample(texSampler, uv).r;
    
    if (mask < 0.001) {
        discard_fragment();
    }
    
    // 2. 计算边缘（使用 Sobel 梯度）
    float2 texelSize = uniforms.texelSize;
    float maskL = maskTexture.sample(texSampler, uv + float2(-texelSize.x, 0)).r;
    float maskR = maskTexture.sample(texSampler, uv + float2( texelSize.x, 0)).r;
    float maskT = maskTexture.sample(texSampler, uv + float2(0, -texelSize.y)).r;
    float maskB = maskTexture.sample(texSampler, uv + float2(0,  texelSize.y)).r;
    
    float gradX = maskR - maskL;
    float gradY = maskB - maskT;
    float edge = length(float2(gradX, gradY)) * 2.0;
    edge = smoothstep(0.0, 0.5, edge);
    
    // 3. 生成噪声
    float2 noiseUV = uv * 4.0;
    float noise = fbmNoise(noiseUV, uniforms.time, uniforms.noiseOctaves);
    
    // 4. 计算相位
    float2 flowDir = normalize(FLOW_DIRECTION);
    float phase = dot(uv, flowDir) * uniforms.phaseScale
                + uniforms.time * uniforms.speed
                + noise * uniforms.noiseStrength;
    
    // 5. 从 LUT 采样颜色（使用 2D 坐标，y=0.5）
    float lutCoord = fract(phase);
    float4 color = lutTexture.sample(lutSampler, float2(lutCoord, 0.5));
    
    // 6. 应用边缘增强和 glow
    color.rgb += color.rgb * edge * uniforms.edgeBoost;
    color.rgb += color.rgb * edge * uniforms.glowIntensity;
    
    // 7. 应用 Mask 和强度
    color.a = mask * uniforms.intensity;
    color.rgb *= color.a;
    
    // 8. Dithering
    if (uniforms.ditherEnabled > 0.5) {
        float dither = (random(uv + uniforms.time) - 0.5) / 255.0;
        color.rgb += dither;
    }
    
    return color;
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
    
    // 计算亮度
    float brightness = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    
    // 阈值过滤
    if (brightness > uniforms.threshold) {
        // 软阈值：平滑过渡
        float softness = 0.1;
        float contribution = smoothstep(uniforms.threshold - softness, uniforms.threshold + softness, brightness);
        return color * contribution;
    }
    
    return float4(0.0);
}

/// 高斯模糊权重（预计算）
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

/// Bloom 合成
fragment float4 fragmentBloomComposite(
    VertexOut in [[stage_in]],
    texture2d<float> mainTexture [[texture(0)]],
    texture2d<float> bloomTexture [[texture(1)]],
    constant BloomUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    
    float4 mainColor = mainTexture.sample(texSampler, in.texCoord);
    float4 bloomColor = bloomTexture.sample(texSampler, in.texCoord);
    
    // 叠加 bloom
    float4 result = mainColor + bloomColor * uniforms.intensity;
    
    // 防止过曝
    result.rgb = min(result.rgb, float3(1.0));
    
    return result;
}

// MARK: - 辅助着色器

/// 简单的纹理复制
fragment float4 fragmentCopy(
    VertexOut in [[stage_in]],
    texture2d<float> inputTexture [[texture(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    return inputTexture.sample(texSampler, in.texCoord);
}

/// 清除为透明
fragment float4 fragmentClear(VertexOut in [[stage_in]]) {
    return float4(0.0);
}
