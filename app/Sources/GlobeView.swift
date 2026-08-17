import SwiftUI
import MetalKit

/// Hosts the Metal view. One finger spins the globe, pinch zooms,
/// double tap springs back to your location.
struct GlobeView: UIViewRepresentable {

    var locationLatitude: Float
    var locationLongitude: Float

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = TouchMTKView(frame: .zero)
        guard let renderer = Renderer(view: view) else { return view }
        if Renderer.debugHome == nil {
            renderer.locationLatitude = locationLatitude
            renderer.locationLongitude = locationLongitude
            renderer.rotation.setHome(latitude: locationLatitude,
                                      longitude: locationLongitude, snap: true)
        }
        context.coordinator.renderer = renderer
        view.delegate = renderer
        view.coordinator = context.coordinator
        view.backgroundColor = .black
        view.isMultipleTouchEnabled = true

        // NOTE: verified not to be the cause of the touch-delivery bug — the
        // drag was equally dead with this removed. See LEARNINGS.md.
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        guard Renderer.debugHome == nil, let r = context.coordinator.renderer else { return }
        let moved = abs(r.locationLatitude - locationLatitude) > 0.0001
                 || abs(r.locationLongitude - locationLongitude) > 0.0001
        r.locationLatitude = locationLatitude
        r.locationLongitude = locationLongitude
        if moved {
            r.rotation.setHome(latitude: locationLatitude, longitude: locationLongitude,
                               snap: !r.hasBeenTouched)
        }
    }

    final class Coordinator: NSObject {
        var renderer: Renderer?
        private var lastPoint: CGPoint = .zero
        private var lastTime: CFTimeInterval = 0
        private var velocity: CGPoint = .zero
        private var zoomAtPinchStart: Float = 1

        /// Radians of rotation per point of finger travel. Scaled by zoom so the
        /// globe keeps up with the finger when you are close in.
        private func sensitivity(for view: UIView) -> Float {
            let base = Float(2.0 * .pi / (max(view.bounds.width, 1) * 2.1))
            return base / max(renderer?.zoom ?? 1, 0.4)
        }

        // MARK: one finger — spin

        func began(_ p: CGPoint, in view: UIView) {
            renderer?.hasBeenTouched = true
            renderer?.rotation.beginPull()
            lastPoint = p
            lastTime = CACurrentMediaTime()
            velocity = .zero
        }

        func moved(_ p: CGPoint, in view: UIView) {
            guard let r = renderer else { return }
            let k = sensitivity(for: view)
            r.rotation.push(dYaw: -Float(p.x - lastPoint.x) * k,
                            dPitch: -Float(p.y - lastPoint.y) * k)
            let now = CACurrentMediaTime()
            let dt = max(now - lastTime, 1.0 / 240.0)
            velocity = CGPoint(x: (p.x - lastPoint.x) / dt, y: (p.y - lastPoint.y) / dt)
            lastPoint = p
            lastTime = now
        }

        func ended(in view: UIView) {
            guard let r = renderer else { return }
            let k = sensitivity(for: view)
            let stale = CACurrentMediaTime() - lastTime > 0.08
            let s: Float = stale ? 0 : 1
            r.rotation.endPull(velocityYaw: -Float(velocity.x) * k * s,
                               velocityPitch: -Float(velocity.y) * k * s)
        }

        /// A second finger landing mid-spin should stop the throw, not fight it.
        func cancelSpin() {
            renderer?.rotation.endPull(velocityYaw: 0, velocityPitch: 0)
        }

        // MARK: two fingers — zoom

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard let r = renderer else { return }
            switch g.state {
            case .began:
                zoomAtPinchStart = r.zoom
                cancelSpin()
            case .changed:
                r.zoom = zoomAtPinchStart * Float(g.scale)
            default:
                break
            }
        }

        func doubleTapped() { renderer?.rotation.returnHome() }
    }
}

/// Tracking touches directly rather than using a pan recogniser keeps the
/// throw velocity honest; the pinch recogniser runs alongside.
final class TouchMTKView: MTKView {
    weak var coordinator: GlobeView.Coordinator?
    private var active: Set<UITouch> = []

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        DebugLog.write("began incoming=\(touches.count) active=\(active.count) coord=\(coordinator != nil)")
        let wasSingle = active.count == 1
        active.formUnion(touches)
        if let t = touches.first, t.tapCount == 2, active.count == 1 {
            coordinator?.doubleTapped()
            return
        }
        if active.count >= 2 {
            if wasSingle { coordinator?.cancelSpin() }       // hand over to pinch
        } else if let t = active.first {
            coordinator?.began(t.location(in: self), in: self)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        DebugLog.write("moved active=\(active.count) coord=\(coordinator != nil) yaw=\(coordinator?.renderer?.rotation.yaw ?? -99)")
        guard active.count == 1, let t = active.first else { return }
        coordinator?.moved(t.location(in: self), in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasMulti = active.count >= 2
        active.subtract(touches)
        if wasMulti {
            // lifting back down to one finger resumes spinning from that point
            if let t = active.first { coordinator?.began(t.location(in: self), in: self) }
        } else if active.isEmpty {
            coordinator?.ended(in: self)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        DebugLog.write("CANCELLED n=\(touches.count)")
        active.subtract(touches)
        if active.isEmpty { coordinator?.ended(in: self) }
    }
}
