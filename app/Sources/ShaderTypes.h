#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// Mirrors NUNIAegirRenderUniforms + NUNIAegirPipelineConstants as recovered
// from NanoUniverse.framework in iOS 27.0 (24A5408d).
typedef struct {
    matrix_float3x3 modelInverse;        // lookModelInverseMatrix
    vector_float3   cameraPos;
    vector_float3   camRight;
    vector_float3   camUp;
    vector_float3   camForward;
    vector_float3   lightDirection;      // world-space direction to the sun
    vector_float2   resolution;
    float           tanHalfFov;
    float           time;

    // concentric shells the ray is tested against
    float floorRadius;
    float cloudLoRadius;
    float cloudMdRadius;
    float cloudHiRadius;
    float atmosRadiusInner;
    float atmosRadiusOuter;

    // surface
    float earthLightPower;
    float earthSurfaceAmbientStrength;
    float earthSpecularPower;
    float earthSpecularStrength;
    float earthSpecularBreakup;
    float reliefStrength;

    // night side
    vector_float3 earthIllumination;
    float         earthIlluminationStrength;

    // clouds
    float earthCloudAlpha;
    float earthCloudAmbientStrength;
    float earthCloudShadowStrength;
    float earthCloudShadowEaseFrom;
    float earthCloudShadowEaseTo;

    // atmosphere
    vector_float3 earthAtmosphere;
    float         earthAtmosphereStrength;
    float         earthAtmosphereGlowExpMin;
    float         earthAtmosphereTerminatorEaseFrom;
    float         earthAtmosphereTerminatorEaseTo;

    // grading — continent vs ocean, day vs night
    vector_float3 continentDay;
    vector_float3 continentNight;
    vector_float3 oceanDay;
    vector_float3 oceanNight;

    vector_float3 sunColor;

    // location dot
    vector_float3 locationDir;           // model-space unit vector
    float         locationVisible;
    float         locationPulse;         // 0..1

    float starBrightness;
    float exposure;
    float bloomThreshold;
} Uniforms;

#endif /* ShaderTypes_h */
