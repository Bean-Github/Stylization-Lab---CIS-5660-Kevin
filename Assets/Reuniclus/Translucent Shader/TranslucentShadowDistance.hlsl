#ifndef TRANSLUCENT_SHADOW_DISTANCE_INCLUDED
#define TRANSLUCENT_SHADOW_DISTANCE_INCLUDED

#ifndef SHADERGRAPH_PREVIEW
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

// Returns 0 in shadow, 1 in light (including soft-shadow fractions).
float SampleTranslucentShadow(float3 posWS)
{
    float4 coord;

#if defined(_MAIN_LIGHT_SHADOWS_SCREEN)
        coord = ComputeScreenPos(TransformWorldToHClip(posWS));
#else
    coord = TransformWorldToShadowCoord(posWS);
#endif

    return MainLightRealtimeShadow(coord);
}
#endif

// Shader Graph Custom Function (File, Float precision)
// Inputs:  WorldPos (Vector3, World), MaxDistance (Float, world units)
// Outputs: Distance (Float: 0 deep inside, 1 at/outside edge),
//          ShadowMask (Float: 0 lit, 1 shadowed)
// Works best for a flat XZ receiving surface and main-light shadows.
void TranslucentShadowDistance_float(
    float3 WorldPos,
    float MaxDistance,
    out float Distance,
    out float ShadowMask)
{
    Distance = 1.0;
    ShadowMask = 0.0;

#ifndef SHADERGRAPH_PREVIEW
    float centerLight = SampleTranslucentShadow(WorldPos);
    ShadowMask = saturate(1.0 - centerLight);

    // Lit or mostly lit: the boundary-normalized value is 1.
    if (centerLight >= 0.5)
        return;

    float radius = max(MaxDistance, 0.0001);
    float nearestEdge = radius;
    const int RINGS = 8;
    float spacing = radius / float(RINGS);

    const float2 directions[8] =
    {
        float2(1.0, 0.0),
        float2(-1.0, 0.0),
        float2(0.0, 1.0),
        float2(0.0, -1.0),
        float2(0.707107, 0.707107),
        float2(-0.707107, 0.707107),
        float2(0.707107, -0.707107),
        float2(-0.707107, -0.707107)
    };

    // Search in 8 directions along the receiver's XZ plane.
    for (int d = 0; d < 8; ++d)
    {
        float3 ray = float3(directions[d].x, 0.0, directions[d].y);
        float lowerDistance = 0.0;
        float lowerLight = centerLight;

        for (int r = 1; r <= RINGS; ++r)
        {
            float upperDistance = spacing * float(r);
            float upperLight = SampleTranslucentShadow(WorldPos + ray * upperDistance);

            // Find where shadow attenuation crosses 0.5.
            if (upperLight >= 0.5)
            {
                // Binary refinement between last shadowed and first lit sample.
                for (int b = 0; b < 3; ++b)
                {
                    float midpoint = 0.5 * (lowerDistance + upperDistance);
                    float middleLight = SampleTranslucentShadow(WorldPos + ray * midpoint);

                    if (middleLight >= 0.5)
                    {
                        upperDistance = midpoint;
                        upperLight = middleLight;
                    }
                    else
                    {
                        lowerDistance = midpoint;
                        lowerLight = middleLight;
                    }
                }

                // Refine further for fractional (soft) shadow attenuation.
                float blend = saturate((0.5 - lowerLight) /
                                       max(upperLight - lowerLight, 0.00001));
                float edgeDistance = lerp(lowerDistance, upperDistance, blend);
                nearestEdge = min(nearestEdge, edgeDistance);
                break;
            }

            lowerDistance = upperDistance;
            lowerLight = upperLight;
        }
    }

    // Exactly within [0, 1]:
    // 1 near the shadow edge, 0 when the edge is >= MaxDistance away.
    float normalizedDepth = saturate(nearestEdge / radius);
    float smoothDepth = normalizedDepth * normalizedDepth *
                        (3.0 - 2.0 * normalizedDepth);
    Distance = 1.0 - smoothDepth;
#endif
}

#endif
