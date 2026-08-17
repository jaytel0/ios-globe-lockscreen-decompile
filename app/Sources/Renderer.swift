import Foundation
import Metal
import MetalKit
import simd
import UIKit

final class Renderer: NSObject, MTKViewDelegate {

    // MARK: Metal objects
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var scenePipeline: MTLRenderPipelineState!
    private var thresholdPipeline: MTLRenderPipelineState!
    private var blurPipeline: MTLRenderPipelineState!
    private var postPipeline: MTLRenderPipelineState!

    private var albedoCube: MTLTexture!
    private var reliefCube: MTLTexture!
    private var lightsCube: MTLTexture!
    private var waterCube: MTLTexture!
    private var cloudCube: MTLTexture!

    private var sceneTexture: MTLTexture?
    private var bloomA: MTLTexture?
    private var bloomB: MTLTexture?
    private var drawableSize: CGSize = .zero

    // MARK: model
    let rotation = RotationModel()
    private var lastFrameTime = CACurrentMediaTime()
    private var elapsed: Float = 0

    /// Camera distance in planet radii. Large so the globe reads near-orthographic,
    /// which is how the shipping wallpaper looks.
    private let cameraDistance: Float = 7.4
    private let fovY: Float = 32.0 * .pi / 180.0

    /// Where the location beacon sits.
    var locationLatitude: Float = 51.5074
    var locationLongitude: Float = -0.1278
    var locationVisible = true

    /// Two-finger time travel, in hours from now. The Astronomy watch face
    /// does this with the Digital Crown.
    var timeOffsetHours: Float = 0

    /// Once the user has moved the globe, a late location fix must not yank it.
    var hasBeenTouched = false

    /// Pinch zoom. 1.0 frames the whole globe loosely; the default fills the
    /// screen top to bottom.
    var zoom: Float = 2.20 { didSet { zoom = min(max(zoom, 0.42), 9.0) } }

    /// Diagnostics: pin the sun to a known direction to check conventions.
    static var debugSun: SIMD3<Float>? = nil
    static var debugHome: (Float, Float)? = nil

    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        super.init()

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isOpaque = true
        view.preferredFramesPerSecond = 60

        guard buildPipelines(view: view), loadTextures() else { return nil }

        if let h = Renderer.debugHome { locationLatitude = h.0; locationLongitude = h.1 }
        rotation.setHome(latitude: locationLatitude, longitude: locationLongitude, snap: true)
        return
    }

    // MARK: setup

    private func buildPipelines(view: MTKView) -> Bool {
        guard let library = device.makeDefaultLibrary() else {
            print("[Aegir] no default Metal library")
            return false
        }
        func make(_ fragment: String, format: MTLPixelFormat) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "fullscreen_vsh")
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = format
            do { return try device.makeRenderPipelineState(descriptor: d) }
            catch { print("[Aegir] pipeline \(fragment) failed: \(error)"); return nil }
        }
        guard let s = make("aegir_earth_fsh", format: .rgba16Float),
              let t = make("aegir_threshold_fsh", format: .rgba16Float),
              let b = make("aegir_blur_fsh", format: .rgba16Float),
              let p = make("aegir_post_fsh", format: view.colorPixelFormat)
        else { return false }
        scenePipeline = s; thresholdPipeline = t; blurPipeline = b; postPipeline = p
        return true
    }

    private func loadTextures() -> Bool {
        func cube(_ base: String, channels: Int) -> MTLTexture? {
            var faces: [CGImage] = []
            for i in 0..<6 {
                guard let url = Bundle.main.url(forResource: "\(base)_\(i)", withExtension: "png"),
                      let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                    print("[Aegir] missing texture \(base)_\(i).png")
                    return nil
                }
                faces.append(img)
            }
            let size = faces[0].width
            let d = MTLTextureDescriptor.textureCubeDescriptor(
                pixelFormat: channels == 1 ? .r8Unorm : .rgba8Unorm_srgb,
                size: size,
                mipmapped: true)
            d.usage = [.shaderRead]
            guard let tex = device.makeTexture(descriptor: d) else { return nil }

            let bpr = size * (channels == 1 ? 1 : 4)
            var bytes = [UInt8](repeating: 0, count: bpr * size)
            let space = channels == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
            let info: UInt32 = channels == 1
                ? CGImageAlphaInfo.none.rawValue
                : CGImageAlphaInfo.premultipliedLast.rawValue
            for (slice, img) in faces.enumerated() {
                bytes.withUnsafeMutableBytes { raw in
                    guard let ctx = CGContext(data: raw.baseAddress,
                                              width: size, height: size,
                                              bitsPerComponent: 8, bytesPerRow: bpr,
                                              space: space, bitmapInfo: info) else { return }
                    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
                    ctx.draw(img, in: CGRect(x: 0, y: 0, width: size, height: size))
                }
                tex.replace(region: MTLRegionMake2D(0, 0, size, size),
                            mipmapLevel: 0, slice: slice,
                            withBytes: bytes, bytesPerRow: bpr, bytesPerImage: bpr * size)
            }
            if let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
                blit.generateMipmaps(for: tex)
                blit.endEncoding()
                cb.commit()
            }
            return tex
        }

        guard let a = cube("earth_albedo", channels: 4),
              let r = cube("earth_relief", channels: 1),
              let l = cube("earth_lights", channels: 4),
              let w = cube("earth_water",  channels: 1),
              let c = cube("earth_cloud",  channels: 1)
        else { return false }
        albedoCube = a; reliefCube = r; lightsCube = l; waterCube = w; cloudCube = c
        return true
    }

    private func makeOffscreen(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        func target(_ w: Int, _ h: Int) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float, width: max(w, 1), height: max(h, 1), mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            return device.makeTexture(descriptor: d)
        }
        let w = Int(size.width), h = Int(size.height)
        sceneTexture = target(w, h)
        bloomA = target(w / 3, h / 3)
        bloomB = target(w / 3, h / 3)
        drawableSize = size
    }

    // MARK: uniforms

    private func makeUniforms(size: CGSize) -> Uniforms {
        var u = Uniforms()

        u.modelInverse = rotation.modelInverse
        u.cameraPos    = SIMD3(0, 0, cameraDistance)
        u.camRight     = SIMD3(1, 0, 0)
        u.camUp        = SIMD3(0, 1, 0)
        u.camForward   = SIMD3(0, 0, -1)
        let when = Date().addingTimeInterval(TimeInterval(timeOffsetHours) * 3600)
        // The sub-solar point is a fixed latitude/longitude — i.e. fixed in the
        // globe's own frame. Rotate it into world space with the model matrix so
        // the terminator stays locked to the geography as the globe is spun.
        let sunModel = Renderer.debugSun ?? SolarPosition.sunDirection(at: when)
        u.lightDirection = rotation.modelMatrix * sunModel
        u.resolution   = SIMD2(Float(size.width), Float(size.height))
        u.tanHalfFov   = tan(fovY * 0.5) / zoom
        u.time         = elapsed

        // concentric shells, in planet radii
        u.floorRadius      = 1.0
        u.cloudLoRadius    = 1.004
        u.cloudMdRadius    = 1.009
        u.cloudHiRadius    = 1.015
        u.atmosRadiusInner = 1.0
        u.atmosRadiusOuter = 1.055

        u.earthLightPower             = 0.62
        u.earthSurfaceAmbientStrength = 0.42
        u.earthSpecularPower          = 68.0
        u.earthSpecularStrength       = 0.42
        u.earthSpecularBreakup        = 0.65
        u.reliefStrength              = 2.2

        u.earthIllumination         = SIMD3(1.00, 0.80, 0.48)   // sodium-warm
        u.earthIlluminationStrength = 3.4

        u.earthCloudAlpha            = 0.95
        u.earthCloudAmbientStrength  = 0.10
        u.earthCloudShadowStrength   = 0.55
        u.earthCloudShadowEaseFrom   = 0.18
        u.earthCloudShadowEaseTo     = 0.85

        u.earthAtmosphere                      = SIMD3(0.33, 0.58, 1.00)
        u.earthAtmosphereStrength              = 1.15
        u.earthAtmosphereGlowExpMin            = 0.55
        u.earthAtmosphereTerminatorEaseFrom    = -0.32
        u.earthAtmosphereTerminatorEaseTo      = 0.22

        u.continentDay   = SIMD3(1.02, 1.00, 0.96)
        u.continentNight = SIMD3(0.42, 0.47, 0.62)
        u.oceanDay       = SIMD3(0.88, 0.96, 1.06)
        u.oceanNight     = SIMD3(0.26, 0.38, 0.70)

        u.sunColor = SIMD3(1.0, 0.97, 0.92)

        u.locationDir     = SolarPosition.direction(latitude: Double(locationLatitude),
                                                    longitude: Double(locationLongitude))
        u.locationVisible = locationVisible ? 1 : 0
        u.locationPulse   = fmod(elapsed, 2.4) / 2.4

        u.starBrightness = 1.0
        u.exposure       = 1.45
        u.bloomThreshold = 0.72

        return u
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        makeOffscreen(size)
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(now - lastFrameTime, 1.0 / 20.0))
        lastFrameTime = now
        elapsed += dt
        rotation.update(deltaTime: dt)

        guard let drawable = view.currentDrawable else { return }
        let size = view.drawableSize
        if sceneTexture == nil || drawableSize != size { makeOffscreen(size) }
        guard let scene = sceneTexture, let bA = bloomA, let bB = bloomB,
              let cb = queue.makeCommandBuffer() else { return }

        var u = makeUniforms(size: size)

        func pass(_ target: MTLTexture,
                  _ pipeline: MTLRenderPipelineState,
                  textures: [MTLTexture],
                  blurDir: SIMD2<Float>? = nil,
                  cubes: [MTLTexture] = []) {
            let d = MTLRenderPassDescriptor()
            d.colorAttachments[0].texture = target
            d.colorAttachments[0].loadAction = .clear
            d.colorAttachments[0].storeAction = .store
            d.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
            guard let e = cb.makeRenderCommandEncoder(descriptor: d) else { return }
            e.setRenderPipelineState(pipeline)
            e.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
            if var dir = blurDir {
                e.setFragmentBytes(&dir, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            }
            for (i, t) in (cubes + textures).enumerated() {
                e.setFragmentTexture(t, index: i)
            }
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            e.endEncoding()
        }

        // 1 — the globe itself
        pass(scene, scenePipeline, textures: [],
             cubes: [albedoCube, reliefCube, lightsCube, waterCube, cloudCube])

        // 2 — bright pass, then a separable blur, at a third resolution
        pass(bA, thresholdPipeline, textures: [scene])
        let texel = SIMD2<Float>(1.0 / Float(bA.width), 1.0 / Float(bA.height))
        pass(bB, blurPipeline, textures: [bA], blurDir: SIMD2(texel.x, 0))
        pass(bA, blurPipeline, textures: [bB], blurDir: SIMD2(0, texel.y))

        // 3 — composite to the screen
        if let d = view.currentRenderPassDescriptor {
            d.colorAttachments[0].loadAction = .clear
            d.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
            if let e = cb.makeRenderCommandEncoder(descriptor: d) {
                e.setRenderPipelineState(postPipeline)
                e.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
                e.setFragmentTexture(scene, index: 0)
                e.setFragmentTexture(bA, index: 1)
                e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                e.endEncoding()
            }
        }

        cb.present(drawable)
        cb.commit()
    }
}
