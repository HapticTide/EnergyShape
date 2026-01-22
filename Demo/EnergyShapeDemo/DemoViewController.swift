//
//  DemoViewController.swift
//  EnergyShapeDemo
//
//  Created by Sun on 2026/1/21.
//  演示界面 - 展示能量动画效果（全屏形状 + 控制面板）
//

import EnergyShape
import UIKit

// MARK: - 形状类型枚举

/// Demo 使用的形状类型
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

/// 能量动画演示控制器
public class DemoViewController: UIViewController {
    // MARK: - UI 组件

    /// 能量视图容器（全屏，禁用交互以穿透到下层控制面板）
    private lazy var energyContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = false
        container.backgroundColor = .clear
        return container
    }()

    /// 能量视图
    private var energyView: EnergyShapeView!
    
    /// 是否启用 MSAA（运行时切换会重建视图）
    private var isMSAAEnabled: Bool = true

    /// 性能统计视图
    private lazy var statsView: PerformanceStatsView = {
        let view = PerformanceStatsView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// 控制面板
    private lazy var controlPanel: ControlPanel = {
        let panel = ControlPanel()
        panel.delegate = self
        panel.translatesAutoresizingMaskIntoConstraints = false
        return panel
    }()

    /// 当前配置
    private var currentConfig = ColorPresets.appleIntelligenceConfig

    /// 当前颜色预设
    private var currentColorPreset: ColorPreset = .appleIntelligence
    
    /// 当前形状参数（圆角半径/半径/纵轴半径，根据形状类型不同含义不同）
    private var currentShapeParam: CGFloat = 0.15
    
    /// 当前横向边距（仅用于椭圆和胶囊）
    /// 归一化值，表示形状边缘到视图边缘的距离
    private var currentHorizontalMargin: CGFloat = 0.1

    /// 面板底部约束（用于展开/收起动画）
    private var panelBottomConstraint: NSLayoutConstraint?

    // MARK: - 生命周期

    override public func viewDidLoad() {
        super.viewDidLoad()
        createEnergyView()
        setupUI()
        setupInitialShape()

        // 使用 Apple Intelligence 预设
        energyView.config = currentConfig
        controlPanel.updateFromConfig(currentConfig)
        controlPanel.updateContentInset(energyView.contentInset.top)
        controlPanel.updateColorPreset(currentColorPreset)
    }
    
    /// 创建能量视图
    private func createEnergyView() {
        let newView = EnergyShapeView(frame: .zero)
        newView.delegate = self
        newView.translatesAutoresizingMaskIntoConstraints = false
        newView.contentInset = .zero
        newView.msaaEnabled = isMSAAEnabled
        energyView = newView
    }
    
    /// 重建能量视图（用于 MSAA 切换）
    private func recreateEnergyView() {
        // 保存当前状态
        let savedConfig = currentConfig
        let savedShape = controlPanel.selectedShapeIndex
        
        // 停止并移除旧视图
        energyView.stop()
        energyView.removeFromSuperview()
        
        // 创建新视图
        createEnergyView()
        
        // 添加到容器（不影响其他视图层级）
        energyContainer.addSubview(energyView)
        
        // 设置约束
        NSLayoutConstraint.activate([
            energyView.topAnchor.constraint(equalTo: energyContainer.topAnchor),
            energyView.leadingAnchor.constraint(equalTo: energyContainer.leadingAnchor),
            energyView.trailingAnchor.constraint(equalTo: energyContainer.trailingAnchor),
            energyView.bottomAnchor.constraint(equalTo: energyContainer.bottomAnchor),
        ])
        
        // 恢复配置
        energyView.config = savedConfig
        
        // 恢复形状
        if let shapeType = ShapeType(rawValue: savedShape) {
            updateShape(for: shapeType)
        }
        
        // 开始动画
        energyView.start()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        energyView.start()
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        energyView.stop()
    }

    deinit {
        energyView.stop()
    }

    // MARK: - UI 设置

    private func setupUI() {
        view.backgroundColor = .black

        // 层级顺序（从底到顶）：energyContainer → controlPanel → statsView
        // energyContainer 禁用交互，所以 controlPanel 可以接收触摸

        // 添加能量视图容器（最底层，全屏，禁用交互）
        view.addSubview(energyContainer)
        energyContainer.addSubview(energyView)

        // 添加控制面板（中间层）
        view.addSubview(controlPanel)

        // 添加性能统计视图（最上层）
        view.addSubview(statsView)

        // 设置约束
        NSLayoutConstraint.activate([
            // 能量视图容器 - 全屏
            energyContainer.topAnchor.constraint(equalTo: view.topAnchor),
            energyContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            energyContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            energyContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // 能量视图 - 填满容器
            energyView.topAnchor.constraint(equalTo: energyContainer.topAnchor),
            energyView.leadingAnchor.constraint(equalTo: energyContainer.leadingAnchor),
            energyView.trailingAnchor.constraint(equalTo: energyContainer.trailingAnchor),
            energyView.bottomAnchor.constraint(equalTo: energyContainer.bottomAnchor),

            // 性能统计视图 - 顶部居中
            statsView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statsView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statsView.widthAnchor.constraint(equalToConstant: 200),

            // 控制面板 - 屏幕中心，高度为屏幕的 1/2
            controlPanel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            controlPanel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            controlPanel.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -48),
            controlPanel.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5),
        ])
    }

    // MARK: - 初始形状

    private func setupInitialShape() {
        // 默认选择圆角矩形
        controlPanel.selectedShapeIndex = ShapeType.roundedRect.rawValue
        updateShape(for: .roundedRect)
    }

    /// 更新形状
    private func updateShape(for type: ShapeType) {
        // 使用当前形状参数
        let param = currentShapeParam
        
        // 设置一个简单的占位路径（仅用于触发 updateMaskForCurrentBounds）
        // 实际渲染使用 analyticShapeOverride
        let placeholderPath = UIBezierPath(rect: view.bounds).cgPath
        
        switch type {
        case .roundedRect:
            // 圆角矩形：填充整个视图，param 控制圆角半径
            energyView.analyticShapeOverride = .roundedRect(
                rect: .zero,  // 会被自动调整到 bounds
                cornerRadius: param
            )
            
        case .circle:
            // 圆形：居中显示，param 控制半径
            energyView.analyticShapeOverride = .circle(
                center: CGPoint(x: 0.5, y: 0.5),
                radius: param
            )
            
        case .ellipse:
            // 椭圆：param 控制纵轴半径（垂直方向）
            // 横轴由外边距控制：horizontalRadius = 0.5 - horizontalMargin
            let horizontalRadius = 0.5 - currentHorizontalMargin
            let verticalRadius = param  // 垂直方向半径由参数控制
            let ellipseRect = CGRect(
                x: currentHorizontalMargin,
                y: 0.5 - verticalRadius,
                width: horizontalRadius * 2,
                height: verticalRadius * 2
            )
            energyView.analyticShapeOverride = .ellipse(rect: ellipseRect)
            
        case .capsule:
            // 胶囊型：param 控制纵轴半径（垂直方向，即短边）
            // 横轴由外边距控制：horizontalRadius = 0.5 - horizontalMargin
            let horizontalRadius = 0.5 - currentHorizontalMargin
            let verticalRadius = param  // 垂直方向半径由参数控制
            let capsuleRect = CGRect(
                x: currentHorizontalMargin,
                y: 0.5 - verticalRadius,
                width: horizontalRadius * 2,
                height: verticalRadius * 2
            )
            // isVertical = false 表示横向是长边（水平胶囊）
            energyView.analyticShapeOverride = .capsule(rect: capsuleRect, isVertical: false)
        }
        
        // 设置路径触发更新
        energyView.shapePath = placeholderPath
    }
}

// MARK: - ControlPanelDelegate

extension DemoViewController: ControlPanelDelegate {
    func panelDidChangeShape(_ panel: ControlPanel, shapeIndex: Int) {
        guard let shapeType = ShapeType(rawValue: shapeIndex) else { return }
        
        // 设置不同形状的默认参数值
        switch shapeType {
        case .roundedRect:
            currentShapeParam = 0.15  // 圆角半径
        case .circle:
            currentShapeParam = 0.5   // 半径（占满）
        case .ellipse:
            currentShapeParam = 0.30  // 纵轴半径
        case .capsule:
            currentShapeParam = 0.12  // 纵轴半径
        }
        
        // 更新形状参数标签和滑块值
        panel.updateShapeParamLabel(for: shapeType)
        panel.updateShapeParamValue(currentShapeParam)
        
        updateShape(for: shapeType)
    }

    func panelDidChangeSpeed(_ panel: ControlPanel, value: Float) {
        currentConfig.speed = value
        energyView.config = currentConfig
    }

    func panelDidChangeGlow(_ panel: ControlPanel, value: Float) {
        currentConfig.glowIntensity = value
        energyView.config = currentConfig
    }

    func panelDidChangeEdgeBoost(_ panel: ControlPanel, value: Float) {
        currentConfig.edgeBoost = value
        energyView.config = currentConfig
    }

    func panelDidChangeBorderWidth(_ panel: ControlPanel, value: Float) {
        currentConfig.borderWidth = value
        energyView.config = currentConfig
    }

    func panelDidChangeInnerGlow(_ panel: ControlPanel, value: Float) {
        currentConfig.innerGlowIntensity = value
        energyView.config = currentConfig
    }

    func panelDidChangeInnerGlowRange(_ panel: ControlPanel, value: Float) {
        currentConfig.innerGlowRange = value
        energyView.config = currentConfig
    }
    
    func panelDidToggleOuterGlow(_ panel: ControlPanel, enabled: Bool) {
        if enabled {
            // 启用外发光：设置默认值
            currentConfig.outerGlowIntensity = 0.3
            currentConfig.outerGlowRange = 0.1
        } else {
            // 禁用外发光
            currentConfig.outerGlowIntensity = 0.0
            currentConfig.outerGlowRange = 0.0
        }
        energyView.config = currentConfig
    }
    
    func panelDidChangeOuterGlowIntensity(_ panel: ControlPanel, value: Float) {
        currentConfig.outerGlowIntensity = value
        energyView.config = currentConfig
    }
    
    func panelDidChangeOuterGlowRange(_ panel: ControlPanel, value: Float) {
        currentConfig.outerGlowRange = value
        energyView.config = currentConfig
    }
    
    func panelDidChangeShapeParam(_ panel: ControlPanel, value: Float) {
        let shapeIndex = controlPanel.selectedShapeIndex
        guard let shapeType = ShapeType(rawValue: shapeIndex) else { return }
        currentShapeParam = CGFloat(value)
        updateShape(for: shapeType)
    }

    func panelDidChangeContentInset(_ panel: ControlPanel, value: Float) {
        let shapeIndex = controlPanel.selectedShapeIndex
        guard let shapeType = ShapeType(rawValue: shapeIndex) else { return }
        
        switch shapeType {
        case .roundedRect, .circle:
            // 圆角矩形和圆形：外边距控制 contentInset
            let inset = CGFloat(value)
            energyView.contentInset = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
            
        case .ellipse, .capsule:
            // 椭圆和胶囊：外边距控制横向边距（归一化值）
            // 将像素值转换为归一化值（假设 60 像素对应 0.1 的归一化边距）
            currentHorizontalMargin = CGFloat(value) / 600.0
            updateShape(for: shapeType)
        }
    }

    func panelDidChangeColorPreset(_ panel: ControlPanel, preset: ColorPreset) {
        currentColorPreset = preset
        // 只更新颜色，保留用户当前的其他参数设置
        currentConfig.colorStops = preset.colorStops
        energyView.config = currentConfig
    }

    func panelDidToggleBloom(_ panel: ControlPanel, enabled: Bool) {
        currentConfig.bloomEnabled = enabled
        energyView.config = currentConfig
    }

    func panelDidChangeBloomIntensity(_ panel: ControlPanel, value: Float) {
        currentConfig.bloomIntensity = value
        energyView.config = currentConfig
    }

    func panelDidTapReset(_ panel: ControlPanel) {
        // 保留当前颜色和形状
        let currentColors = currentConfig.colorStops
        let selectedIndex = controlPanel.selectedShapeIndex
        
        // 使用 Apple Intelligence 配置作为默认参数模板（但不改变颜色）
        currentConfig = ColorPresets.appleIntelligenceConfig
        currentConfig.colorStops = currentColors
        
        // 更新视图配置
        energyView.config = currentConfig
        
        // 更新面板 UI（包括外发光等开关状态）
        controlPanel.updateFromConfig(currentConfig)
        
        // 重置形状参数并应用到视图
        switch selectedIndex {
        case 0: // roundedRect
            currentShapeParam = 0.15
            controlPanel.updateShapeParamValue(0.15)
        case 1: // circle
            currentShapeParam = 0.5
            controlPanel.updateShapeParamValue(0.5)
        case 2: // ellipse
            currentShapeParam = 0.30
            controlPanel.updateShapeParamValue(0.30)
        case 3: // capsule
            currentShapeParam = 0.12
            controlPanel.updateShapeParamValue(0.12)
        default:
            break
        }
        
        // 重置外边距为 0
        controlPanel.updateContentInset(0)
        energyView.contentInset = .zero
        
        // 重新应用形状（使用重置后的参数）
        if let shapeType = ShapeType(rawValue: selectedIndex) {
            updateShape(for: shapeType)
        }
    }

    func panelDidTapStart(_ panel: ControlPanel) {
        energyView.start()
    }

    func panelDidTapStop(_ panel: ControlPanel) {
        energyView.stop()
    }

    func panelDidTapPause(_ panel: ControlPanel) {
        energyView.pause()
    }

    func panelDidTapResume(_ panel: ControlPanel) {
        energyView.resume()
    }
    
    func panelDidToggleMSAA(_ panel: ControlPanel, enabled: Bool) {
        guard isMSAAEnabled != enabled else { return }
        isMSAAEnabled = enabled
        recreateEnergyView()
    }
}

// MARK: - EnergyShapeViewDelegate

extension DemoViewController: EnergyShapeViewDelegate {
    public func energyShapeView(_ view: EnergyShapeView, didUpdateStats stats: EnergyPerformanceStats) {
        DispatchQueue.main.async { [weak self] in
            self?.statsView.update(with: stats)
        }
    }

    public func energyShapeView(_ view: EnergyShapeView, didFailWithError error: Error) {
        let alert = UIAlertController(
            title: "错误",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    public func energyShapeView(_ view: EnergyShapeView, didChangeState state: EnergyAnimationState) {
        // 可以在这里更新 UI 状态
    }
}

// MARK: - ControlPanel

/// 控制面板代理
protocol ControlPanelDelegate: AnyObject {
    func panelDidChangeShape(_ panel: ControlPanel, shapeIndex: Int)
    func panelDidChangeSpeed(_ panel: ControlPanel, value: Float)
    func panelDidChangeGlow(_ panel: ControlPanel, value: Float)
    func panelDidChangeEdgeBoost(_ panel: ControlPanel, value: Float)
    func panelDidToggleBloom(_ panel: ControlPanel, enabled: Bool)
    func panelDidChangeBloomIntensity(_ panel: ControlPanel, value: Float)
    // 边框发光参数
    func panelDidChangeBorderWidth(_ panel: ControlPanel, value: Float)
    func panelDidChangeInnerGlow(_ panel: ControlPanel, value: Float)
    func panelDidChangeInnerGlowRange(_ panel: ControlPanel, value: Float)
    func panelDidChangeContentInset(_ panel: ControlPanel, value: Float)
    // 外发光参数
    func panelDidToggleOuterGlow(_ panel: ControlPanel, enabled: Bool)
    func panelDidChangeOuterGlowIntensity(_ panel: ControlPanel, value: Float)
    func panelDidChangeOuterGlowRange(_ panel: ControlPanel, value: Float)
    // 形状参数（边距/半径）
    func panelDidChangeShapeParam(_ panel: ControlPanel, value: Float)
    // 颜色预设
    func panelDidChangeColorPreset(_ panel: ControlPanel, preset: ColorPreset)
    // MSAA 开关
    func panelDidToggleMSAA(_ panel: ControlPanel, enabled: Bool)
    // 参数重置
    func panelDidTapReset(_ panel: ControlPanel)
    func panelDidTapStart(_ panel: ControlPanel)
    func panelDidTapStop(_ panel: ControlPanel)
    func panelDidTapPause(_ panel: ControlPanel)
    func panelDidTapResume(_ panel: ControlPanel)
}

/// 固定居中的控制面板
class ControlPanel: UIView {
    weak var delegate: ControlPanelDelegate?

    /// 当前选中的形状索引
    var selectedShapeIndex: Int {
        get { shapeSegmentedControl.selectedSegmentIndex }
        set { shapeSegmentedControl.selectedSegmentIndex = newValue }
    }

    // MARK: - UI 组件

    /// 顶部固定区域（形状和颜色选择）
    private lazy var headerStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// 中间滚动区域
    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = true
        sv.showsHorizontalScrollIndicator = false
        sv.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 24, right: 0)
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    /// 滚动内容容器
    private lazy var scrollContentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// 底部固定区域（控制按钮）
    private lazy var footerStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// 形状选择器
    private lazy var shapeSegmentedControl: UISegmentedControl = {
        let items = ShapeType.allCases.map(\.displayName)
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(shapeChanged), for: .valueChanged)
        control.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 11)], for: .normal)
        return control
    }()

    /// 颜色预设选择器
    private lazy var colorPresetSegmentedControl: UISegmentedControl = {
        let items = ColorPreset.allCases.map(\.rawValue)
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(colorPresetChanged), for: .valueChanged)
        control.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 10)], for: .normal)
        return control
    }()

    /// 滑块
    private lazy var speedSlider: UISlider = createSlider(min: 0.1, max: 3.0, value: 0.5)
    private lazy var glowSlider: UISlider = createSlider(min: 0, max: 2.0, value: 1.2)
    private lazy var edgeBoostSlider: UISlider = createSlider(min: 0, max: 3.0, value: 1.5)
    private lazy var bloomIntensitySlider: UISlider = createSlider(min: 0, max: 1.0, value: 0.6)

    // 边框发光参数滑块
    private lazy var borderWidthSlider: UISlider = createSlider(min: 0.005, max: 0.08, value: 0.018)
    private lazy var innerGlowSlider: UISlider = createSlider(min: 0, max: 1.0, value: 0.45)
    private lazy var innerGlowRangeSlider: UISlider = createSlider(min: 0.01, max: 0.5, value: 0.2)
    private lazy var contentInsetSlider: UISlider = createSlider(min: 0, max: 60, value: 0)
    
    // 外发光参数
    private lazy var outerGlowSlider: UISlider = createSlider(min: 0, max: 1.0, value: 0.0)
    private lazy var outerGlowRangeSlider: UISlider = createSlider(min: 0.01, max: 0.1, value: 0.03)
    
    // 形状参数滑块（边距/半径，根据形状类型动态变化）
    private lazy var shapeParamSlider: UISlider = createSlider(min: 0, max: 0.5, value: 0.15)
    
    /// 形状参数标签（动态显示：外边距/半径/短半径）
    private weak var shapeParamTitleLabel: UILabel?
    
    /// 外发光开关
    private lazy var outerGlowSwitch: UISwitch = {
        let sw = UISwitch()
        sw.isOn = false
        sw.addTarget(self, action: #selector(outerGlowToggled), for: .valueChanged)
        return sw
    }()

    /// Bloom 开关
    private lazy var bloomSwitch: UISwitch = {
        let sw = UISwitch()
        sw.isOn = true
        sw.addTarget(self, action: #selector(bloomToggled), for: .valueChanged)
        return sw
    }()
    
    /// MSAA 开关
    private lazy var msaaSwitch: UISwitch = {
        let sw = UISwitch()
        sw.isOn = true  // 默认开启
        sw.addTarget(self, action: #selector(msaaToggled), for: .valueChanged)
        return sw
    }()

    /// 按钮容器
    private lazy var buttonStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        return stack
    }()

    // MARK: - 初始化

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - UI 设置

    private func setupUI() {
        layer.cornerRadius = 16

        // 添加模糊效果
        let blurEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 16
        blurView.clipsToBounds = true
        insertSubview(blurView, at: 0)

        // 添加三个区域
        addSubview(headerStack)
        addSubview(scrollView)
        scrollView.addSubview(scrollContentStack)
        addSubview(footerStack)

        // 顶部固定区：形状和颜色
        headerStack.addArrangedSubview(shapeSegmentedControl)
        headerStack.addArrangedSubview(colorPresetSegmentedControl)

        // 中间滚动区：参数滑块
        scrollContentStack.addArrangedSubview(createSliderRow(
            label: "速度",
            slider: speedSlider,
            action: #selector(speedChanged)
        ))
        scrollContentStack.addArrangedSubview(createSliderRow(
            label: "发光",
            slider: glowSlider,
            action: #selector(glowChanged)
        ))
        scrollContentStack.addArrangedSubview(createSliderRow(
            label: "边框宽度",
            slider: borderWidthSlider,
            action: #selector(borderWidthChanged)
        ))
        scrollContentStack.addArrangedSubview(createSliderRow(
            label: "内发光",
            slider: innerGlowSlider,
            action: #selector(innerGlowChanged)
        ))
        scrollContentStack.addArrangedSubview(createSliderRow(
            label: "内发光范围",
            slider: innerGlowRangeSlider,
            action: #selector(innerGlowRangeChanged)
        ))
        // 外发光控制
        scrollContentStack.addArrangedSubview(createSwitchRow(label: "外发光", sw: outerGlowSwitch))
        scrollContentStack.addArrangedSubview(createSliderRow(
            label: "外发光强度",
            slider: outerGlowSlider,
            action: #selector(outerGlowIntensityChanged)
        ))
        scrollContentStack.addArrangedSubview(createSliderRow(
            label: "外发光范围",
            slider: outerGlowRangeSlider,
            action: #selector(outerGlowRangeChanged)
        ))
        // 形状参数（动态标签）
        let shapeParamRow = createDynamicSliderRow(
            initialLabel: "圆角半径",
            slider: shapeParamSlider,
            action: #selector(shapeParamChanged)
        )
        scrollContentStack.addArrangedSubview(shapeParamRow)
        scrollContentStack.addArrangedSubview(createSliderRow(
            label: "外边距",
            slider: contentInsetSlider,
            action: #selector(contentInsetChanged)
        ))
        scrollContentStack.addArrangedSubview(createSwitchRow(label: "Bloom", sw: bloomSwitch))
        scrollContentStack.addArrangedSubview(createSliderRow(
            label: "Bloom强度",
            slider: bloomIntensitySlider,
            action: #selector(bloomIntensityChanged)
        ))
        scrollContentStack.addArrangedSubview(createSwitchRow(label: "MSAA 4x", sw: msaaSwitch))

        // 底部固定区：控制按钮
        setupButtons()
        footerStack.addArrangedSubview(buttonStack)

        // 约束
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 顶部固定区
            headerStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            // 中间滚动区
            scrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            scrollView.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -12),

            // 滚动内容
            scrollContentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            scrollContentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            scrollContentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -12),
            scrollContentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            scrollContentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -12),

            // 底部固定区
            footerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            footerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            footerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    private func createSlider(min: Float, max: Float, value: Float) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        return slider
    }

    private func createSliderRow(label: String, slider: UISlider, action: Selector) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = label
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.text = String(format: "%.1f", slider.value)
        valueLabel.textColor = .lightGray
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.tag = slider.hash + 1000

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(self, action: action, for: .valueChanged)

        container.addSubview(titleLabel)
        container.addSubview(slider)
        container.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 80),

            slider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            slider.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            valueLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 35),

            container.heightAnchor.constraint(equalToConstant: 28),
        ])

        return container
    }

    private func createSwitchRow(label: String, sw: UISwitch) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = label
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        sw.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(sw)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            // 给 UISwitch 右侧留出一点空间，避免被剪裁
            sw.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            sw.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            container.heightAnchor.constraint(equalToConstant: 32),
        ])

        return container
    }
    
    /// 创建动态标签的滑块行（标签可以根据形状类型更新）
    private func createDynamicSliderRow(initialLabel: String, slider: UISlider, action: Selector) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = initialLabel
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        // 保存引用以便后续更新
        shapeParamTitleLabel = titleLabel

        let valueLabel = UILabel()
        valueLabel.text = String(format: "%.2f", slider.value)
        valueLabel.textColor = .lightGray
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.tag = slider.hash + 1000

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(self, action: action, for: .valueChanged)

        container.addSubview(titleLabel)
        container.addSubview(slider)
        container.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 80),

            slider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            slider.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            valueLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 35),

            container.heightAnchor.constraint(equalToConstant: 28),
        ])

        return container
    }
    
    /// 根据形状类型更新形状参数标签
    func updateShapeParamLabel(for shapeType: ShapeType) {
        switch shapeType {
        case .roundedRect:
            shapeParamTitleLabel?.text = "圆角半径"
            shapeParamSlider.minimumValue = 0
            shapeParamSlider.maximumValue = 0.5
        case .circle:
            shapeParamTitleLabel?.text = "半径"
            shapeParamSlider.minimumValue = 0.1
            shapeParamSlider.maximumValue = 0.5
        case .ellipse:
            // 椭圆：控制纵轴（垂直方向）半径
            shapeParamTitleLabel?.text = "纵轴半径"
            shapeParamSlider.minimumValue = 0.1
            shapeParamSlider.maximumValue = 0.5
        case .capsule:
            // 胶囊：控制纵轴（垂直方向，即短边）半径
            shapeParamTitleLabel?.text = "纵轴半径"
            shapeParamSlider.minimumValue = 0.05
            shapeParamSlider.maximumValue = 0.3
        }
        updateValueLabel(for: shapeParamSlider)
    }
    
    /// 更新形状参数滑块的值
    func updateShapeParamValue(_ value: CGFloat) {
        shapeParamSlider.value = Float(value)
        updateValueLabel(for: shapeParamSlider)
    }

    private func setupButtons() {
        let startBtn = createButton(title: "开始", action: #selector(startTapped))
        let stopBtn = createButton(title: "停止", action: #selector(stopTapped))
        let pauseBtn = createButton(title: "暂停", action: #selector(pauseTapped))
        let resumeBtn = createButton(title: "恢复", action: #selector(resumeTapped))
        let resetBtn = createButton(title: "重置", action: #selector(resetTapped))
        resetBtn.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.8)

        buttonStack.addArrangedSubview(startBtn)
        buttonStack.addArrangedSubview(stopBtn)
        buttonStack.addArrangedSubview(pauseBtn)
        buttonStack.addArrangedSubview(resumeBtn)
        buttonStack.addArrangedSubview(resetBtn)
    }

    private func createButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.layer.cornerRadius = 6
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }

    // MARK: - 公开方法

    /// 从配置更新 UI
    func updateFromConfig(_ config: EnergyConfig) {
        speedSlider.value = config.speed
        glowSlider.value = config.glowIntensity
        edgeBoostSlider.value = config.edgeBoost
        bloomSwitch.isOn = config.bloomEnabled
        bloomIntensitySlider.value = config.bloomIntensity
        bloomIntensitySlider.isEnabled = config.bloomEnabled

        // 边框发光参数
        borderWidthSlider.value = config.borderWidth
        innerGlowSlider.value = config.innerGlowIntensity
        innerGlowRangeSlider.value = config.innerGlowRange
        
        // 外发光参数
        let hasOuterGlow = config.outerGlowIntensity > 0
        outerGlowSwitch.isOn = hasOuterGlow
        outerGlowSlider.value = config.outerGlowIntensity
        outerGlowSlider.isEnabled = hasOuterGlow
        outerGlowRangeSlider.value = config.outerGlowRange
        outerGlowRangeSlider.isEnabled = hasOuterGlow

        updateValueLabel(for: speedSlider)
        updateValueLabel(for: glowSlider)
        updateValueLabel(for: edgeBoostSlider)
        updateValueLabel(for: bloomIntensitySlider)
        updateValueLabel(for: borderWidthSlider)
        updateValueLabel(for: innerGlowSlider)
        updateValueLabel(for: innerGlowRangeSlider)
        updateValueLabel(for: outerGlowSlider)
        updateValueLabel(for: outerGlowRangeSlider)
        updateValueLabel(for: contentInsetSlider)
    }

    /// 更新 contentInset 显示
    func updateContentInset(_ value: CGFloat) {
        contentInsetSlider.value = Float(value)
        updateValueLabel(for: contentInsetSlider)
    }

    /// 更新颜色预设显示
    func updateColorPreset(_ preset: ColorPreset) {
        if let index = ColorPreset.allCases.firstIndex(of: preset) {
            colorPresetSegmentedControl.selectedSegmentIndex = index
        }
    }

    // MARK: - Actions

    @objc private func shapeChanged(_ sender: UISegmentedControl) {
        delegate?.panelDidChangeShape(self, shapeIndex: sender.selectedSegmentIndex)
    }

    @objc private func colorPresetChanged(_ sender: UISegmentedControl) {
        let preset = ColorPreset.allCases[sender.selectedSegmentIndex]
        delegate?.panelDidChangeColorPreset(self, preset: preset)
    }

    @objc private func speedChanged(_ sender: UISlider) {
        updateValueLabel(for: sender)
        delegate?.panelDidChangeSpeed(self, value: sender.value)
    }

    @objc private func glowChanged(_ sender: UISlider) {
        updateValueLabel(for: sender)
        delegate?.panelDidChangeGlow(self, value: sender.value)
    }

    @objc private func edgeBoostChanged(_ sender: UISlider) {
        updateValueLabel(for: sender)
        delegate?.panelDidChangeEdgeBoost(self, value: sender.value)
    }

    @objc private func borderWidthChanged(_ sender: UISlider) {
        updateValueLabel(for: sender)
        delegate?.panelDidChangeBorderWidth(self, value: sender.value)
    }

    @objc private func innerGlowChanged(_ sender: UISlider) {
        updateValueLabel(for: sender)
        delegate?.panelDidChangeInnerGlow(self, value: sender.value)
    }

    @objc private func innerGlowRangeChanged(_ sender: UISlider) {
        updateValueLabel(for: sender)
        delegate?.panelDidChangeInnerGlowRange(self, value: sender.value)
    }
    
    @objc private func outerGlowToggled(_ sender: UISwitch) {
        outerGlowSlider.isEnabled = sender.isOn
        outerGlowRangeSlider.isEnabled = sender.isOn
        delegate?.panelDidToggleOuterGlow(self, enabled: sender.isOn)
    }
    
    @objc private func outerGlowIntensityChanged(_ sender: UISlider) {
        updateValueLabel(for: sender)
        delegate?.panelDidChangeOuterGlowIntensity(self, value: sender.value)
    }
    
    @objc private func outerGlowRangeChanged(_ sender: UISlider) {
        updateValueLabel(for: sender)
        delegate?.panelDidChangeOuterGlowRange(self, value: sender.value)
    }
    
    @objc private func shapeParamChanged(_ sender: UISlider) {
        updateValueLabel(for: sender)
        delegate?.panelDidChangeShapeParam(self, value: sender.value)
    }

    @objc private func contentInsetChanged(_ sender: UISlider) {
        updateValueLabel(for: sender)
        delegate?.panelDidChangeContentInset(self, value: sender.value)
    }

    @objc private func bloomToggled(_ sender: UISwitch) {
        bloomIntensitySlider.isEnabled = sender.isOn
        delegate?.panelDidToggleBloom(self, enabled: sender.isOn)
    }

    @objc private func bloomIntensityChanged(_ sender: UISlider) {
        updateValueLabel(for: sender)
        delegate?.panelDidChangeBloomIntensity(self, value: sender.value)
    }
    
    @objc private func msaaToggled(_ sender: UISwitch) {
        delegate?.panelDidToggleMSAA(self, enabled: sender.isOn)
    }

    @objc private func resetTapped() {
        delegate?.panelDidTapReset(self)
    }

    @objc private func startTapped() {
        delegate?.panelDidTapStart(self)
    }

    @objc private func stopTapped() {
        delegate?.panelDidTapStop(self)
    }

    @objc private func pauseTapped() {
        delegate?.panelDidTapPause(self)
    }

    @objc private func resumeTapped() {
        delegate?.panelDidTapResume(self)
    }

    private func updateValueLabel(for slider: UISlider) {
        if let valueLabel = viewWithTag(slider.hash + 1000) as? UILabel {
            // 边框宽度需要更高精度显示
            if slider === borderWidthSlider {
                valueLabel.text = String(format: "%.3f", slider.value)
            } else if slider === innerGlowRangeSlider || slider === innerGlowSlider ||
                      slider === outerGlowSlider || slider === outerGlowRangeSlider ||
                      slider === shapeParamSlider {
                valueLabel.text = String(format: "%.2f", slider.value)
            } else {
                valueLabel.text = String(format: "%.1f", slider.value)
            }
        }
    }
}

// MARK: - PerformanceStatsView

/// 性能统计视图 - 使用颜色区分性能等级
final class PerformanceStatsView: UIView {
    // MARK: - UI 组件

    /// FPS 行
    private lazy var fpsLabel: UILabel = createLabel()
    /// 帧耗时行
    private lazy var frameTimeLabel: UILabel = createLabel()
    /// GPU/CPU 详情行
    private lazy var detailLabel: UILabel = createLabel()

    /// 内容栈
    private lazy var contentStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [fpsLabel, frameTimeLabel, detailLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - 初始化

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - UI 设置

    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.6)
        layer.cornerRadius = 8
        clipsToBounds = true

        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    private func createLabel() -> UILabel {
        let label = UILabel()
        label.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .white.withAlphaComponent(0.9)
        return label
    }

    // MARK: - 公开方法

    /// 更新统计数据
    func update(with stats: EnergyPerformanceStats) {
        // FPS 行 - 根据性能等级着色
        let fpsColor = colorForGrade(stats.performanceGrade)
        let fpsText = String(format: "%.0f", stats.currentFPS)
        let avgFpsText = String(format: "%.0f", stats.averageFPS)

        let fpsAttr = NSMutableAttributedString()
        fpsAttr.append(NSAttributedString(string: "FPS: ", attributes: [
            .foregroundColor: UIColor.white.withAlphaComponent(0.7)
        ]))
        fpsAttr.append(NSAttributedString(string: fpsText, attributes: [
            .foregroundColor: fpsColor,
            .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        ]))
        fpsAttr.append(NSAttributedString(string: " (avg: \(avgFpsText))", attributes: [
            .foregroundColor: UIColor.white.withAlphaComponent(0.5),
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        ]))
        fpsLabel.attributedText = fpsAttr

        // 帧耗时行
        let totalText = String(format: "%.2f", stats.totalFrameTime)
        let budgetText = String(format: "%.0f%%", stats.frameBudgetUsage)
        let budgetColor = colorForBudgetUsage(stats.frameBudgetUsage)

        let frameAttr = NSMutableAttributedString()
        frameAttr.append(NSAttributedString(string: "帧耗时: ", attributes: [
            .foregroundColor: UIColor.white.withAlphaComponent(0.7)
        ]))
        frameAttr.append(NSAttributedString(string: "\(totalText)ms", attributes: [
            .foregroundColor: UIColor.white.withAlphaComponent(0.9)
        ]))
        frameAttr.append(NSAttributedString(string: " [\(budgetText)]", attributes: [
            .foregroundColor: budgetColor,
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        ]))
        frameTimeLabel.attributedText = frameAttr

        // GPU/CPU 详情行
        let gpuText = String(format: "%.2f", stats.gpuTime)
        let cpuText = String(format: "%.2f", stats.cpuTime)
        detailLabel.text = "GPU: \(gpuText)ms | CPU: \(cpuText)ms"
        detailLabel.textColor = .white.withAlphaComponent(0.6)
    }

    // MARK: - 颜色计算

    private func colorForGrade(_ grade: EnergyPerformanceStats.PerformanceGrade) -> UIColor {
        switch grade {
        case .excellent:
            return UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1.0)  // 亮绿色
        case .good:
            return UIColor(red: 0.4, green: 0.85, blue: 0.4, alpha: 1.0) // 绿色
        case .normal:
            return UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0) // 黄色
        case .warning:
            return UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)  // 橙色
        case .critical:
            return UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)  // 红色
        }
    }

    private func colorForBudgetUsage(_ usage: Double) -> UIColor {
        switch usage {
        case ..<50:
            return UIColor(red: 0.4, green: 0.85, blue: 0.4, alpha: 1.0) // 绿色
        case 50 ..< 75:
            return UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0) // 黄色
        case 75 ..< 100:
            return UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)  // 橙色
        default:
            return UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)  // 红色
        }
    }
}
