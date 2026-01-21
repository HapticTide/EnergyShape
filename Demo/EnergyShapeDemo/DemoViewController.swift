//
//  DemoViewController.swift
//  EnergyShapeDemo
//
//  Created by Sun on 2026/1/21.
//  演示界面 - 展示能量动画效果
//

import UIKit
import EnergyShape

/// 能量动画演示控制器
public class DemoViewController: UIViewController {
    
    // MARK: - UI 组件
    
    /// 能量视图
    private lazy var energyView: EnergyShapeView = {
        let view = EnergyShapeView(frame: .zero)
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    /// 形状选择器
    private lazy var shapeSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["圆形", "矩形", "Logo", "心形", "星形"])
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(shapeChanged), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    /// 控制面板容器
    private lazy var controlPanel: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    /// Speed Slider
    private lazy var speedSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 0.1
        slider.maximumValue = 3.0
        slider.value = 1.0
        slider.addTarget(self, action: #selector(speedChanged), for: .valueChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        return slider
    }()
    
    /// Glow Slider
    private lazy var glowSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 2.0
        slider.value = 0.5
        slider.addTarget(self, action: #selector(glowChanged), for: .valueChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        return slider
    }()
    
    /// Edge Boost Slider
    private lazy var edgeBoostSlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 3.0
        slider.value = 1.2
        slider.addTarget(self, action: #selector(edgeBoostChanged), for: .valueChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        return slider
    }()
    
    /// Bloom Switch
    private lazy var bloomSwitch: UISwitch = {
        let sw = UISwitch()
        sw.isOn = true
        sw.addTarget(self, action: #selector(bloomToggled), for: .valueChanged)
        sw.translatesAutoresizingMaskIntoConstraints = false
        return sw
    }()
    
    /// Bloom Intensity Slider
    private lazy var bloomIntensitySlider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 1.0
        slider.value = 0.3
        slider.addTarget(self, action: #selector(bloomIntensityChanged), for: .valueChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        return slider
    }()
    
    /// 播放控制按钮容器
    private lazy var buttonStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 12
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    /// 性能统计标签
    private lazy var statsLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .white
        label.numberOfLines = 0
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    /// 当前配置
    private var currentConfig = EnergyConfig.default
    
    // MARK: - 生命周期
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupInitialShape()
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        energyView.start()
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        energyView.stop()
    }
    
    deinit {
        energyView.stop()
    }
    
    // MARK: - UI 设置
    
    private func setupUI() {
        view.backgroundColor = .black
        
        // 添加能量视图
        view.addSubview(energyView)
        
        // 添加性能统计
        view.addSubview(statsLabel)
        
        // 添加形状选择器
        view.addSubview(shapeSegmentedControl)
        
        // 添加控制面板
        view.addSubview(controlPanel)
        setupControlPanel()
        
        // 设置约束
        NSLayoutConstraint.activate([
            // 能量视图 - 上半部分
            energyView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            energyView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            energyView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            energyView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.4),
            
            // 性能统计 - 右上角
            statsLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            statsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            statsLabel.widthAnchor.constraint(equalToConstant: 180),
            
            // 形状选择器
            shapeSegmentedControl.topAnchor.constraint(equalTo: energyView.bottomAnchor, constant: 20),
            shapeSegmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            shapeSegmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // 控制面板
            controlPanel.topAnchor.constraint(equalTo: shapeSegmentedControl.bottomAnchor, constant: 20),
            controlPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            controlPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            controlPanel.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])
    }
    
    private func setupControlPanel() {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        controlPanel.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: controlPanel.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: controlPanel.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: controlPanel.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: controlPanel.bottomAnchor, constant: -16),
        ])
        
        // 添加滑块
        stackView.addArrangedSubview(createSliderRow(label: "速度", slider: speedSlider, valueLabel: createValueLabel("1.0")))
        stackView.addArrangedSubview(createSliderRow(label: "发光", slider: glowSlider, valueLabel: createValueLabel("0.5")))
        stackView.addArrangedSubview(createSliderRow(label: "边缘", slider: edgeBoostSlider, valueLabel: createValueLabel("1.2")))
        stackView.addArrangedSubview(createSwitchRow(label: "Bloom", sw: bloomSwitch))
        stackView.addArrangedSubview(createSliderRow(label: "Bloom强度", slider: bloomIntensitySlider, valueLabel: createValueLabel("0.3")))
        
        // 添加按钮
        setupButtons()
        stackView.addArrangedSubview(buttonStack)
    }
    
    private func createSliderRow(label: String, slider: UISlider, valueLabel: UILabel) -> UIView {
        let container = UIView()
        
        let titleLabel = UILabel()
        titleLabel.text = label
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        slider.tag = slider.hashValue
        valueLabel.tag = slider.hashValue + 1000
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(titleLabel)
        container.addSubview(slider)
        container.addSubview(valueLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 70),
            
            slider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            slider.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            
            valueLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 40),
            
            container.heightAnchor.constraint(equalToConstant: 30),
        ])
        
        return container
    }
    
    private func createSwitchRow(label: String, sw: UISwitch) -> UIView {
        let container = UIView()
        
        let titleLabel = UILabel()
        titleLabel.text = label
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(titleLabel)
        container.addSubview(sw)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            
            sw.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sw.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            
            container.heightAnchor.constraint(equalToConstant: 30),
        ])
        
        return container
    }
    
    private func createValueLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .lightGray
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textAlignment = .right
        return label
    }
    
    private func setupButtons() {
        let startButton = createButton(title: "开始", action: #selector(startTapped))
        let stopButton = createButton(title: "停止", action: #selector(stopTapped))
        let pauseButton = createButton(title: "暂停", action: #selector(pauseTapped))
        let resumeButton = createButton(title: "恢复", action: #selector(resumeTapped))
        
        buttonStack.addArrangedSubview(startButton)
        buttonStack.addArrangedSubview(stopButton)
        buttonStack.addArrangedSubview(pauseButton)
        buttonStack.addArrangedSubview(resumeButton)
    }
    
    private func createButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return button
    }
    
    // MARK: - 初始形状
    
    private func setupInitialShape() {
        let size = CGSize(width: 200, height: 200)
        energyView.shapePath = ShapeGenerator.circle(diameter: size.width)
    }
    
    // MARK: - Actions
    
    @objc private func shapeChanged(_ sender: UISegmentedControl) {
        let size = CGSize(width: 200, height: 200)
        
        switch sender.selectedSegmentIndex {
        case 0: // 圆形
            energyView.shapePath = ShapeGenerator.circle(diameter: size.width)
        case 1: // 矩形
            energyView.shapePath = ShapeGenerator.roundedRect(size: size, cornerRadius: 20)
        case 2: // Logo
            energyView.shapePath = AppleLogoPath.create(size: CGSize(width: 200, height: 240))
        case 3: // 心形
            energyView.shapePath = ShapeGenerator.heart(size: 200)
        case 4: // 星形
            energyView.shapePath = ShapeGenerator.star(points: 5, innerRadius: 50, outerRadius: 100)
        default:
            break
        }
    }
    
    @objc private func speedChanged(_ sender: UISlider) {
        currentConfig.speed = sender.value
        energyView.config = currentConfig
        updateValueLabel(for: sender)
    }
    
    @objc private func glowChanged(_ sender: UISlider) {
        currentConfig.glowIntensity = sender.value
        energyView.config = currentConfig
        updateValueLabel(for: sender)
    }
    
    @objc private func edgeBoostChanged(_ sender: UISlider) {
        currentConfig.edgeBoost = sender.value
        energyView.config = currentConfig
        updateValueLabel(for: sender)
    }
    
    @objc private func bloomToggled(_ sender: UISwitch) {
        currentConfig.bloomEnabled = sender.isOn
        bloomIntensitySlider.isEnabled = sender.isOn
        energyView.config = currentConfig
    }
    
    @objc private func bloomIntensityChanged(_ sender: UISlider) {
        currentConfig.bloomIntensity = sender.value
        energyView.config = currentConfig
        updateValueLabel(for: sender)
    }
    
    @objc private func startTapped() {
        energyView.start()
    }
    
    @objc private func stopTapped() {
        energyView.stop()
    }
    
    @objc private func pauseTapped() {
        energyView.pause()
    }
    
    @objc private func resumeTapped() {
        energyView.resume()
    }
    
    private func updateValueLabel(for slider: UISlider) {
        if let valueLabel = controlPanel.viewWithTag(slider.tag + 1000) as? UILabel {
            valueLabel.text = String(format: "%.1f", slider.value)
        }
    }
}

// MARK: - EnergyShapeViewDelegate

extension DemoViewController: EnergyShapeViewDelegate {
    
    public func energyShapeView(_ view: EnergyShapeView, didUpdateStats stats: EnergyPerformanceStats) {
        DispatchQueue.main.async { [weak self] in
            self?.statsLabel.text = "  " + stats.description.replacingOccurrences(of: "\n", with: "\n  ") + "  "
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
        print("动画状态变化: \(state)")
    }
}
