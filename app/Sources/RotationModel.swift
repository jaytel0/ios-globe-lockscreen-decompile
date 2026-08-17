import Foundation
import simd

/// Reconstruction of NUNIAstronomyRotationModel.
///
/// The original exposes `push:`, `isPulling` and `isAtHomeCoordinate` — you
/// throw the globe with a finger, it carries momentum, and it knows how to
/// come back to where you are standing.
final class RotationModel {

    /// Longitude at screen centre is `-yaw`; latitude at screen centre is `pitch`.
    private(set) var yaw: Float = 0
    private(set) var pitch: Float = 0

    private var velocityYaw: Float = 0
    private var velocityPitch: Float = 0

    private(set) var isPulling = false
    private var isReturningHome = false

    var homeYaw: Float = 0
    var homePitch: Float = 0

    private let maxPitch: Float = 1.4835          // ~85 degrees
    private let friction: Float = 2.6             // per second
    private let springStiffness: Float = 5.5
    private let springDamping: Float = 2.0 * 2.35

    var isAtHomeCoordinate: Bool {
        abs(shortestAngle(from: yaw, to: homeYaw)) < 0.01 && abs(pitch - homePitch) < 0.01
    }

    func setHome(latitude: Float, longitude: Float, snap: Bool) {
        homePitch = max(-maxPitch, min(maxPitch, latitude * .pi / 180))
        homeYaw = -longitude * .pi / 180
        if snap {
            yaw = homeYaw
            pitch = homePitch
            velocityYaw = 0
            velocityPitch = 0
        }
    }

    // MARK: gesture

    func beginPull() {
        isPulling = true
        isReturningHome = false
        velocityYaw = 0
        velocityPitch = 0
    }

    /// Drag delta in radians.
    func push(dYaw: Float, dPitch: Float) {
        yaw += dYaw
        pitch = max(-maxPitch, min(maxPitch, pitch + dPitch))
    }

    /// Release with a throw velocity in radians per second.
    func endPull(velocityYaw vy: Float, velocityPitch vp: Float) {
        isPulling = false
        velocityYaw = max(-9, min(9, vy))
        velocityPitch = max(-9, min(9, vp))
    }

    func returnHome() {
        isReturningHome = true
        isPulling = false
        velocityYaw = 0
        velocityPitch = 0
    }

    // MARK: integration

    func update(deltaTime dt: Float) {
        guard dt > 0 else { return }

        if isReturningHome {
            let dy = shortestAngle(from: yaw, to: homeYaw)
            let dp = homePitch - pitch
            velocityYaw   += (dy * springStiffness - velocityYaw   * springDamping) * dt
            velocityPitch += (dp * springStiffness - velocityPitch * springDamping) * dt
            yaw   += velocityYaw   * dt
            pitch += velocityPitch * dt
            if abs(dy) < 0.002, abs(dp) < 0.002,
               abs(velocityYaw) < 0.01, abs(velocityPitch) < 0.01 {
                yaw = homeYaw
                pitch = homePitch
                velocityYaw = 0
                velocityPitch = 0
                isReturningHome = false
            }
            return
        }

        guard !isPulling else { return }

        let decay = exp(-friction * dt)
        velocityYaw *= decay
        velocityPitch *= decay
        yaw += velocityYaw * dt
        pitch = max(-maxPitch, min(maxPitch, pitch + velocityPitch * dt))

        if abs(velocityYaw) < 0.0008 { velocityYaw = 0 }
        if abs(velocityPitch) < 0.0008 { velocityPitch = 0 }
    }

    /// Model matrix: Rx(pitch) * Ry(yaw). Sampling uses its inverse.
    var modelMatrix: simd_float3x3 {
        let cy = cos(yaw), sy = sin(yaw)
        let cp = cos(pitch), sp = sin(pitch)
        let ry = simd_float3x3(SIMD3( cy, 0, -sy),
                               SIMD3(  0, 1,   0),
                               SIMD3( sy, 0,  cy))
        let rx = simd_float3x3(SIMD3(1,   0,  0),
                               SIMD3(0,  cp, sp),
                               SIMD3(0, -sp, cp))
        return rx * ry
    }

    var modelInverse: simd_float3x3 { modelMatrix.transpose }

    private func shortestAngle(from a: Float, to b: Float) -> Float {
        var d = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
        if d >  .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return d
    }
}
