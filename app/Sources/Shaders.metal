#include <metal_stdlib>
#include "ShaderTypes.h"

using namespace metal;

// ---------------------------------------------------------------------------
// Aegir reconstruction.
//
// There is no sphere mesh. A single full-screen triangle is drawn and every
// pixel fires a ray at a stack of concentric spheres — surface, three cloud
// decks, two atmosphere shells — exactly as NUNIAegirRenderer's
// _renderRaytraceSpheroid: does. Textures are Apple's own, sampled as a cube
// map through the inverse model matrix.
// ---------------------------------------------------------------------------

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

vertex VSOut fullscreen_vsh(uint vid [[vertex_id]]) {
    // one oversized triangle covering the viewport
    float2 p = float2((vid << 1) & 2, vid & 2);   // (0,0) (2,0) (0,2)
    VSOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    // uv.y = 0 at the top, matching Metal's texture convention, so every
    // offscreen pass samples the previous one without a vertical flip
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

// --- helpers ---------------------------------------------------------------

// Nearest intersection of a ray with a sphere of radius R centred on origin.
// Returns false when the ray misses or the hit is behind the camera.
static bool hitSphere(float3 ro, float3 rd, float R, thread float &t) {
    float b = dot(ro, rd);
    float c = dot(ro, ro) - R * R;
    float h = b * b - c;
    if (h < 0.0) return false;
    h = sqrt(h);
    float t0 = -b - h;
    if (t0 < 0.0) return false;
    t = t0;
    return true;
}

// Distance along +rd from a point inside the shells out to radius R.
static float exitDistance(float3 p, float3 rd, float R) {
    float b = dot(p, rd);
    float c = dot(p, p) - R * R;
    float h = max(b * b - c, 0.0);
    return -b + sqrt(h);
}

static float hash21(float2 p) {
    p = fract(p * float2(443.897, 441.423));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

// Cheap procedural starfield for background rays (Apple uses sprite stars).
static float3 starfield(float3 rd, float brightness) {
    // quantise the direction into cells and light a few of them
    float3 acc = float3(0.0);
    float3 a = abs(rd);
    float2 uv = (a.x > a.y && a.x > a.z) ? rd.yz / a.x
              : (a.y > a.z)              ? rd.xz / a.y
                                         : rd.xy / a.z;
    for (int layer = 0; layer < 2; layer++) {
        float scale = 190.0 * (layer == 0 ? 1.0 : 2.3);
        float2 g = uv * scale;
        float2 cell = floor(g);
        float2 f = fract(g) - 0.5;
        float r = hash21(cell + float(layer) * 37.0);
        if (r > 0.982) {
            float mag = fract(r * 91.7);
            float d = length(f);
            float i = smoothstep(0.42, 0.0, d) * (0.25 + mag * 0.75);
            // slight colour temperature variation
            float3 tint = mix(float3(0.75, 0.83, 1.0), float3(1.0, 0.93, 0.82), fract(r * 53.3));
            acc += tint * i;
        }
    }
    return acc * brightness;
}

// --- fragment --------------------------------------------------------------

fragment float4 aegir_earth_fsh(VSOut in [[stage_in]],
                                constant Uniforms &u [[buffer(0)]],
                                texturecube<float> albedoTex [[texture(0)]],
                                texturecube<float> reliefTex [[texture(1)]],
                                texturecube<float> lightsTex [[texture(2)]],
                                texturecube<float> waterTex  [[texture(3)]],
                                texturecube<float> cloudTex  [[texture(4)]])
{
    constexpr sampler smp(filter::linear, mip_filter::linear, address::clamp_to_edge);

    float aspect = u.resolution.x / u.resolution.y;
    float2 ndc = float2(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);

    float3 rd = normalize(u.camForward
                          + u.camRight * (ndc.x * u.tanHalfFov * aspect)
                          + u.camUp    * (ndc.y * u.tanHalfFov));
    float3 ro = u.cameraPos;
    float3 L  = normalize(u.lightDirection);

    float3 colour = float3(0.0);

    // ---- background ------------------------------------------------------
    colour += starfield(rd, u.starBrightness);

    // the sun itself, when it drifts into frame
    float sunDot = dot(rd, L);
    if (sunDot > 0.0) {
        float glow = pow(saturate(sunDot), 2200.0);
        colour += u.sunColor * glow * 6.0;
        colour += u.sunColor * pow(saturate(sunDot), 90.0) * 0.06;
    }

    // ---- surface ---------------------------------------------------------
    float tSurf;
    bool hitSurf = hitSphere(ro, rd, u.floorRadius, tSurf);
    float3 surface = float3(0.0);
    float3 surfaceNormal = float3(0.0);

    if (hitSurf) {
        float3 p = ro + rd * tSurf;
        float3 n = normalize(p);
        float3 md = normalize(u.modelInverse * n);

        float3 albedo = albedoTex.sample(smp, md).rgb;
        float3 lights = lightsTex.sample(smp, md).rgb;  // city lights, in colour
        float  water  = waterTex.sample(smp, md).r;     // 1 = water (rivers included)
        float  land   = 1.0 - water;

        // relief: perturb the normal from the greyscale bump map, on land only
        float3 t1 = normalize(cross(md, abs(md.y) < 0.95 ? float3(0, 1, 0) : float3(1, 0, 0)));
        float3 t2 = cross(md, t1);
        const float e = 0.0018;
        float hL = reliefTex.sample(smp, normalize(md - t1 * e)).r;
        float hR = reliefTex.sample(smp, normalize(md + t1 * e)).r;
        float hD = reliefTex.sample(smp, normalize(md - t2 * e)).r;
        float hU = reliefTex.sample(smp, normalize(md + t2 * e)).r;
        float3 bumpM = normalize(md + (t1 * (hL - hR) + t2 * (hD - hU)) * u.reliefStrength * land);
        // carry the perturbation back into world space
        float3 bumpW = normalize(n + (bumpM - md));

        float ndl = dot(bumpW, L);
        // a real terminator is not a hard edge — the atmosphere scatters light
        // a little way onto the night side
        float ramp = smoothstep(-0.13, 0.16, ndl);
        float dayF = pow(ramp, u.earthLightPower);
        float nightF = 1.0 - smoothstep(-0.16, 0.04, ndl);

        float3 dayTint   = mix(u.continentDay,   u.oceanDay,   water);
        float3 nightTint = mix(u.continentNight, u.oceanNight, water);

        // cloud shadow: walk from the surface point toward the sun and see
        // what the mid deck has overhead
        float tc = exitDistance(p, L, u.cloudMdRadius);
        float3 cdir = normalize(u.modelInverse * normalize(p + L * tc));
        float cover = cloudTex.sample(smp, cdir).r;
        float shadow = smoothstep(u.earthCloudShadowEaseFrom,
                                  u.earthCloudShadowEaseTo, cover)
                       * u.earthCloudShadowStrength;

        float3 lit = albedo * dayTint * u.sunColor * dayF * (1.0 - shadow);
        // ambient, weighted toward the night side so the dark half reads as a
        // dim planet rather than a hole in the screen
        lit += albedo * nightTint * u.earthSurfaceAmbientStrength * mix(1.0, 0.22, dayF);

        // ocean sun-glint, broken up so it never reads as a perfect mirror
        float3 h = normalize(L - rd);
        float breakup = mix(1.0, 0.35 + 0.65 * hL, u.earthSpecularBreakup);
        float spec = pow(saturate(dot(bumpW, h)), u.earthSpecularPower)
                     * u.earthSpecularStrength * water * saturate(ndl * 4.0) * breakup;
        lit += u.sunColor * spec;

        // city lights on the night side
        lit += lights * u.earthIllumination * u.earthIlluminationStrength * nightF;

        // location beacon
        float dotAmt = dot(md, normalize(u.locationDir));
        if (u.locationVisible > 0.5 && dotAmt > 0.0) {
            float ang = acos(clamp(dotAmt, -1.0, 1.0));
            float core = smoothstep(0.016, 0.007, ang);
            float ring = smoothstep(0.020 + 0.045 * u.locationPulse, 0.0, ang)
                         - smoothstep(0.014 + 0.040 * u.locationPulse, 0.0, ang);
            float fade = 1.0 - u.locationPulse;
            lit = mix(lit, float3(0.42, 0.72, 1.0), saturate(core));
            lit += float3(0.30, 0.60, 1.0) * saturate(ring) * fade * 0.9;
        }

        surface = lit;
        surfaceNormal = n;
    }

    float3 scene = hitSurf ? surface : colour;

    // ---- cloud decks, composited back to front ---------------------------
    // lo is nearest the surface, hi nearest the camera
    float radii[3]   = { u.cloudLoRadius, u.cloudMdRadius, u.cloudHiRadius };
    float weights[3] = { 1.0, 0.85, 0.62 };

    for (int i = 0; i < 3; i++) {
        float tc;
        if (!hitSphere(ro, rd, radii[i], tc)) continue;
        if (hitSurf && tc > tSurf) continue;

        float3 p = ro + rd * tc;
        float3 n = normalize(p);
        float3 md = normalize(u.modelInverse * n);

        float a = cloudTex.sample(smp, md).r;
        a = saturate((a - 0.04) * 1.25) * u.earthCloudAlpha * weights[i];
        if (a <= 0.001) continue;

        // fade the deck out at the limb so shells do not stack into a hard edge
        a *= smoothstep(0.0, 0.35, dot(n, -rd));

        // clouds need the same soft terminator as the surface, otherwise they
        // clip to black along a hard line
        float cndl = smoothstep(-0.16, 0.20, dot(n, L));
        float3 cl = u.sunColor * pow(cndl, 0.8)
                  + u.earthAtmosphere * u.earthCloudAmbientStrength * mix(0.25, 1.0, cndl);
        scene = mix(scene, cl, a);
    }

    // ---- atmosphere ------------------------------------------------------
    // closest approach of the ray to the planet centre gives an exact limb profile
    float bClose = -dot(ro, rd);
    float3 nearest = ro + rd * max(bClose, 0.0);
    float dClose = length(nearest);
    float3 ndir = normalize(nearest);

    float shell = smoothstep(u.atmosRadiusOuter, u.atmosRadiusInner, dClose);
    float inner = smoothstep(u.floorRadius * 0.986, u.floorRadius, dClose);
    float rim = shell * mix(0.30, 1.0, inner);            // brightest right at the limb

    float sunFacing = dot(ndir, L);
    float term = smoothstep(u.earthAtmosphereTerminatorEaseFrom,
                            u.earthAtmosphereTerminatorEaseTo, sunFacing);
    float glow = pow(saturate(sunFacing), u.earthAtmosphereGlowExpMin);

    float3 atmos = u.earthAtmosphere * u.earthAtmosphereStrength * rim
                   * mix(0.04, 1.0, term) * mix(0.45, 1.0, glow);

    // in front of the disc the haze is additive; beyond it, it is the halo
    scene += atmos * (hitSurf ? 0.55 : 1.0);

    scene *= u.exposure;
    return float4(scene, 1.0);
}

// ---------------------------------------------------------------------------
// Bloom: bright-pass, separable blur, composite — the offscreen chain
// NUNIAegirRenderer runs as _renderOffscreenBloom / _renderOffscreenPost.
// ---------------------------------------------------------------------------

fragment float4 aegir_threshold_fsh(VSOut in [[stage_in]],
                                    constant Uniforms &u [[buffer(0)]],
                                    texture2d<float> src [[texture(0)]])
{
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    float3 c = src.sample(smp, in.uv).rgb;
    float lum = dot(c, float3(0.2126, 0.7152, 0.0722));
    float k = max(lum - u.bloomThreshold, 0.0) / max(lum, 1e-4);
    return float4(c * k, 1.0);
}

fragment float4 aegir_blur_fsh(VSOut in [[stage_in]],
                               constant float2 &dir [[buffer(1)]],
                               texture2d<float> src [[texture(0)]])
{
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    const float w[5] = { 0.2270270270, 0.1945945946, 0.1216216216, 0.0540540541, 0.0162162162 };
    float3 acc = src.sample(smp, in.uv).rgb * w[0];
    for (int i = 1; i < 5; i++) {
        float2 off = dir * float(i) * 1.32;
        acc += src.sample(smp, in.uv + off).rgb * w[i];
        acc += src.sample(smp, in.uv - off).rgb * w[i];
    }
    return float4(acc, 1.0);
}

fragment float4 aegir_post_fsh(VSOut in [[stage_in]],
                               constant Uniforms &u [[buffer(0)]],
                               texture2d<float> scene [[texture(0)]],
                               texture2d<float> bloom [[texture(1)]])
{
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    float3 c = scene.sample(smp, in.uv).rgb;
    c += bloom.sample(smp, in.uv).rgb * u.starBrightness * 0.0 + bloom.sample(smp, in.uv).rgb;

    // filmic-ish shoulder so the lit limb rolls off instead of clipping
    c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
    c = saturate(c);

    // a touch of dither to keep the deep blacks from banding on OLED
    float d = (hash21(in.uv * u.resolution) - 0.5) / 255.0;
    return float4(c + d, 1.0);
}
