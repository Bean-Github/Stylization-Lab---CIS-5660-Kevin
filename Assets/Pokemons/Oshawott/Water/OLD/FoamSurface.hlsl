#ifndef STYLIZED_FOAM_SURFACE_INCLUDED
#define STYLIZED_FOAM_SURFACE_INCLUDED

// Fragment-only helpers. Uniforms and FOAM_TEXTURE(uv) are declared by the caller.
// All bubble/grain distances are continuous: no square-cell alpha masks.

float FoamHash(float2 p)
{
    float3 h = frac(float3(p.x, p.y, p.x) * 0.1031);
    h += dot(h, h.yzx + 33.33);
    return frac((h.x + h.y) * h.z);
}

float2 FoamRandom2(float2 p)
{
    return float2(FoamHash(p), FoamHash(p + float2(43.71, 17.13)));
}

float FoamFade(float2 uv)
{
    float axis = lerp(uv.x, uv.y, saturate(_FadeAxis));
    axis = lerp(axis, 1.0 - axis, saturate(_FlipFade));
    float t = saturate((axis - _FadeStart) / max(_FadeEnd - _FadeStart, 0.001));
    return pow(t, max(_FadePower, 0.05));
}

float2 FoamBreakupUV(float2 uv)
{
    return uv * float2(max(_Aspect, 0.01), 1.0) * _BreakupTiling
         * _BreakupTex_ST.xy + _BreakupTex_ST.zw;
}

// x: signed distance to an active bubble hole.
// y: nearest/second-nearest distance gap (approximate Voronoi wall field).
// z: distance to the rim of ALL bubbles, including filled-in bubbles.
float3 FoamCells(float2 p, float2 scale, float2 offset, float sizeMultiplier,
                 float layerSeed, float holeAmount)
{
    float2 baseCell = floor(p);
    float nearest = 100.0;
    float second = 100.0;
    float holeDistance = 100.0;
    float rimDistance = 100.0;

    // Jitter is limited to the inner 90% of each cell. A 3x3 search includes
    // every circle that can cover this pixel for the clamped radius below.
    [unroll]
    for (int y = -1; y <= 1; ++y)
    {
        [unroll]
        for (int x = -1; x <= 1; ++x)
        {
            float2 cell = baseCell + float2(x, y);
            float2 key = cell + float2(layerSeed, _Seed * 11.17);
            float2 site = cell + 0.05 + 0.9 * FoamRandom2(key);
            float distanceToSite = length(p - site);
            second = min(second, max(nearest, distanceToSite));
            nearest = min(nearest, distanceToSite);

            // Bias toward small bubbles, with occasional larger ones.
            float sizeRandom = FoamHash(key + 71.93);
            float radius = _BubbleRadius * sizeMultiplier
                * lerp(1.0 - _SizeVariation, 1.0 + _SizeVariation,
                       sizeRandom * sizeRandom);
            radius = clamp(radius, 0.06, 0.62);
            float sd = distanceToSite - radius;
            rimDistance = min(rimDistance, abs(sd));

            // Evaluate activation at the site's stable coordinate. The gradient
            // selects whole holes, without scaling their radii along the strip.
            float2 siteUV = (site - offset) / scale;
            float fill = smoothstep(_HoleFillStart, max(_HoleFillEnd,
                                    _HoleFillStart + 0.001), FoamFade(siteUV));
            float activeProbability = saturate(holeAmount) * (1.0 - fill);
            float rank = lerp(0.001, 0.999, FoamHash(key + 133.61));
            if (rank < activeProbability)
                holeDistance = min(holeDistance, sd);
        }
    }
    return float3(holeDistance, max(second - nearest, 0.0), rimDistance);
}

float FoamInside(float sd, float aa)
{
    return 1.0 - smoothstep(-aa, aa, sd);
}

// Stochastic halftoning with jittered circular holes, not square pixels.
// Each grain has a fixed radius and a stable activation rank. The gradient and
// texture determine its probability of being removed. Neighboring holes overlap.
float FoamHalftone(float2 uv)
{
    float2 scale = float2(max(_Aspect, 0.01), 1.0) * max(_GrainScale, 1.0);
    float2 p = uv * scale;
    float2 baseCell = floor(p);
    float holeDistance = 100.0;

    [unroll]
    for (int y = -1; y <= 1; ++y)
    {
        [unroll]
        for (int x = -1; x <= 1; ++x)
        {
            float2 cell = baseCell + float2(x, y);
            float2 key = cell + float2(193.19, _Seed * 7.31);
            float2 site = cell + 0.05 + 0.9 * FoamRandom2(key);
            float2 siteUV = site / scale;
            float t = FoamFade(siteUV);

            // Sampling density at the site also keeps texture breakup from
            // slicing individual circular grains into blocky fragments.
            // Fixed LOD keeps the activation rank consistent within a grain,
            // including pixel quads that cross a procedural cell boundary.
            float patch = FOAM_TEXTURE_LOD0(FoamBreakupUV(siteUV)).r;
            float density = lerp(_FadedCoverage, 1.0, t);
            density += (patch - 0.5) * _BreakupStrength * 4.0 * t * (1.0 - t);
            density = saturate(density);
            float rank = lerp(0.001, 0.999, FoamHash(key + 59.37));
            float radius = clamp(_GrainRadius * lerp(0.86, 1.14,
                                 FoamHash(key + 27.13)), 0.2, 0.78);
            if (rank > density)
                holeDistance = min(holeDistance, length(p - site) - radius);
        }
    }

    float footprint = max(length(fwidth(p)), 0.0001);
    float keep = 1.0 - FoamInside(holeDistance, max(footprint * 0.55, 0.001));

    // Once grains become subpixel, use their approximate mean coverage instead
    // of trying to resolve them. This reduces distant sparkling. Never evaluate
    // derivatives after clip/discard or inside the per-grain activation branch.
    float t = FoamFade(uv);
    float patch = FOAM_TEXTURE(FoamBreakupUV(uv)).r;
    float density = saturate(lerp(_FadedCoverage, 1.0, t)
        + (patch - 0.5) * _BreakupStrength * 4.0 * t * (1.0 - t));
    float meanCoverage = pow(max(density, 0.001), 1.1);
    return lerp(keep, meanCoverage, smoothstep(0.65, 1.6, footprint));
}

// Straight RGB + coverage alpha. The ShaderLab wrapper premultiplies RGB.
float4 EvaluateFoam(float2 uv)
{
    float4 breakup = FOAM_TEXTURE(FoamBreakupUV(uv));
    float t = FoamFade(uv);

    float2 scale = float2(max(_Aspect, 0.01), 1.0) * max(_BubbleScale, 0.1);
    float2 offset = float2(3.17, 7.91);
    float2 warp = (breakup.gb * 2.0 - 1.0) * _WarpStrength;
    float2 p = uv * scale + offset + warp;
    float3 coarse = FoamCells(p, scale, offset, 1.0, 13.19, _HoleAmount);
    float aa = max(length(fwidth(p)) * 0.55, 0.001);

    // F2-F1 is a fast, approximate wall metric. Textured domain warping bends
    // the cellular structure. Rounded SDF holes supply the visible bubble edges.
    float walls = 1.0 - smoothstep(_WallWidth, _WallWidth + aa, coarse.y);
    float coarseHole = FoamInside(coarse.x, aa) * (1.0 - walls);
    float rims = 1.0 - smoothstep(_RimWidth, _RimWidth + aa, coarse.z);

    float fineHole = 0.0;
    float fineWalls = 0.0;
    if (_FineStrength > 0.001)
    {
        float2 fineScale = scale * max(_FineScale, 1.0);
        float2 fineOffset = float2(47.13, 11.73);
        float2 fineP = uv * fineScale + fineOffset + warp * 1.3;
        float3 fine = FoamCells(fineP, fineScale, fineOffset, 0.83,
                               79.71, _FineHoleAmount);
        float fineAA = max(length(fwidth(fineP)) * 0.55, 0.001);
        fineWalls = 1.0 - smoothstep(_WallWidth * 0.85,
                                    _WallWidth * 0.85 + fineAA, fine.y);
        fineHole = FoamInside(fine.x, fineAA) * (1.0 - fineWalls);
    }

    // The field is a white foam sheet with round openings. Fine holes live in
    // the surviving sheet; they cannot refill or scribble over the larger holes.
    float alpha = (1.0 - coarseHole)
                * (1.0 - fineHole * _FineStrength * (1.0 - walls));

    float grainKeep = FoamHalftone(uv);
    float grainWeight = _HalftoneStrength * (1.0 - smoothstep(0.18, 0.65, t));
    alpha *= lerp(1.0, grainKeep, grainWeight);

    // Broad texture breakup is strongest at the faded side and vanishes at the
    // dense side. Texture never changes the procedural bubble scale.
    float patches = smoothstep(0.18, 0.62, breakup.r + t * 0.45);
    alpha *= lerp(1.0, patches, _BreakupStrength * (1.0 - t));

    float axis = lerp(uv.x, uv.y, saturate(_FadeAxis));
    axis = lerp(axis, 1.0 - axis, saturate(_FlipFade));
    float edge = smoothstep(_FadeStart, _FadeStart + max(_EdgeSoftness, 0.001), axis);
    alpha *= edge * saturate(_Opacity);

    float shade = saturate(0.72 + 0.24 * breakup.r + 0.04 * breakup.a);
    float3 color = lerp(_ShadeColor.rgb, _FoamColor.rgb, shade);
    float relief = saturate(rims * 0.6 + walls * _WallHighlight
                          + fineWalls * _FineStrength * 0.22);
    // Retain a little bubble relief in color even when the dense end fills in.
    color = lerp(color, _RimColor.rgb, relief * lerp(0.8, 0.25, t));
    return float4(color, saturate(alpha));
}

#endif
