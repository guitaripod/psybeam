import MetalKit
import simd
import UIKit

private struct WaveUniforms {
    var colorA: SIMD4<Float> = .zero
    var colorB: SIMD4<Float> = .zero
    var colorAccent: SIMD4<Float> = .zero
    var resolution: SIMD2<Float> = .zero
    var time: Float = 0
    var amplitude: Float = 0
    var mode: Float = 0
}

struct WaveStyle: Equatable {
    var colorA: SIMD4<Float>
    var colorB: SIMD4<Float>
    var accent: SIMD4<Float>
    var baseAmplitude: Float

    static let idle = WaveStyle(
        colorA: [0.03, 0.04, 0.11, 1], colorB: [0.09, 0.11, 0.28, 1],
        accent: [0.32, 0.45, 0.95, 1], baseAmplitude: 0.12
    )
    static let listening = WaveStyle(
        colorA: [0.02, 0.09, 0.24, 1], colorB: [0.04, 0.34, 0.74, 1],
        accent: [0.34, 0.82, 1.0, 1], baseAmplitude: 0.30
    )
    static let processing = WaveStyle(
        colorA: [0.16, 0.09, 0.02, 1], colorB: [0.55, 0.30, 0.05, 1],
        accent: [1.0, 0.66, 0.22, 1], baseAmplitude: 0.42
    )
    static let speaking = WaveStyle(
        colorA: [0.02, 0.15, 0.10, 1], colorB: [0.04, 0.46, 0.30, 1],
        accent: [0.42, 1.0, 0.72, 1], baseAmplitude: 0.32
    )
    static let error = WaveStyle(
        colorA: [0.18, 0.03, 0.05, 1], colorB: [0.50, 0.08, 0.12, 1],
        accent: [1.0, 0.32, 0.36, 1], baseAmplitude: 0.22
    )
}

final class WaveVisualizerView: MTKView {
    private let renderer: WaveRenderer

    init() {
        guard let device = MTLCreateSystemDefaultDevice(), let renderer = WaveRenderer(device: device) else {
            fatalError("Metal unavailable")
        }
        self.renderer = renderer
        super.init(frame: .zero, device: device)
        delegate = renderer
        preferredFramesPerSecond = 60
        isPaused = false
        enableSetNeedsDisplay = false
        framebufferOnly = true
        isUserInteractionEnabled = false
        contentScaleFactor = 2.0
        clearColor = MTLClearColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1)
        apply(.idle)
    }

    func apply(_ style: WaveStyle) { renderer.apply(style) }
    func setLevel(_ level: Float) { renderer.level = level }
    func setPaused(_ paused: Bool) { isPaused = paused }
    func bloom() { renderer.addBloom() }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }
}

private final class WaveRenderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var uniforms = WaveUniforms()
    private var accumulatedTime: Float = 0
    private var lastFrameTime = CACurrentMediaTime()

    private var current = WaveStyle.idle
    private var target = WaveStyle.idle
    private var amp: Float = 0.12
    private var smoothedLevel: Float = 0
    private var bloomLevel: Float = 0
    var level: Float = 0

    init?(device: MTLDevice) {
        guard
            let queue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let vertexFn = library.makeFunction(name: "wave_vertex"),
            let fragmentFn = library.makeFunction(name: "wave_fragment")
        else { return nil }
        self.queue = queue
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.pipeline = pipeline
        super.init()
    }

    func apply(_ style: WaveStyle) { target = style }

    func addBloom() { bloomLevel = 1.0 }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        uniforms.resolution = SIMD2(Float(size.width), Float(size.height))
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        var delta = Float(now - lastFrameTime)
        lastFrameTime = now
        if delta <= 0 || delta > 0.1 { delta = 1.0 / 60.0 }
        accumulatedTime += delta

        ease(delta: delta)
        uniforms.colorA = current.colorA
        uniforms.colorB = current.colorB
        uniforms.colorAccent = current.accent
        uniforms.amplitude = amp
        uniforms.time = accumulatedTime
        if uniforms.resolution == .zero {
            uniforms.resolution = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        }

        guard
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let buffer = queue.makeCommandBuffer(),
            let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WaveUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    private func ease(delta: Float) {
        let colorK = 1 - exp(-delta * 3.0)
        current.colorA += (target.colorA - current.colorA) * colorK
        current.colorB += (target.colorB - current.colorB) * colorK
        current.accent += (target.accent - current.accent) * colorK
        current.baseAmplitude += (target.baseAmplitude - current.baseAmplitude) * colorK

        if bloomLevel > 0 { bloomLevel = max(0, bloomLevel - delta * 2.0) }
        smoothedLevel += (max(level, bloomLevel) - smoothedLevel) * (1 - exp(-delta * 6.0))
        let desired = max(current.baseAmplitude, min(1.0, smoothedLevel * 1.5))
        let rate: Float = desired > amp ? 6.5 : 2.0
        amp += (desired - amp) * (1 - exp(-delta * rate))
    }
}
