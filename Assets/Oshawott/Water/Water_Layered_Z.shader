// Local Z controls the color bands. Existing material property IDs are retained.
// Keep this renderer out of static batching to preserve original mesh coordinates.
Shader "Custom/Water/LayeredColorNoiseLocalZ"
{
    Properties
    {
        [Header(Local Z Gradient Mapping)]
        // Band coordinate = mesh local Z * scale + offset. Negative scale reverses it.
        _GradientZScale ("Local Z Gradient Scale", Float) = 1
        _GradientZOffset ("Local Z Gradient Offset", Float) = 0

        [Header(Seven Color Gradient)]
        // Alpha of each HDR color controls its opacity.
        [HDR] _NearColor ("Near Color + Opacity (Alpha)", Color) = (0.12, 0.70, 0.80, 1)
        [HDR] _AfterNearColor ("After Near Color + Opacity (Alpha)", Color) = (0.06, 0.51, 0.68, 1)
        [HDR] _Mid1Color ("Mid 1 Color + Opacity (Alpha)", Color) = (0.06, 0.51, 0.68, 1)
        [HDR] _Mid2Color ("Mid 2 Color + Opacity (Alpha)", Color) = (0.03, 0.35, 0.55, 1)
        [HDR] _FarColor ("Far Color + Opacity (Alpha)", Color) = (0.01, 0.07, 0.20, 1)
        [HDR] _AfterFarColor ("After Far Color + Opacity (Alpha)", Color) = (0.008, 0.04, 0.12, 1)
        [HDR] _BeyondFarColor ("Beyond Far Color + Opacity (Alpha)", Color) = (0.005, 0.02, 0.08, 1)

        [Header(Color Local Z Bands)]
        // Start, End, Edge Width, and noise displacement use the mapped Z coordinate.
        // Colors are fully active between Start and End.
        // Edge Width creates a fading tail outside each end.
        _NearStartDistance ("Near Start Z", Float) = 0
        _NearEndDistance ("Near End Z", Float) = 6
        _NearEdgeWidth ("Near Edge Width", Float) = 1.5

        _AfterNearStartDistance ("After Near Start Z", Float) = 4    
        _AfterNearEndDistance ("After Near End Z", Float) = 10
        _AfterNearEdgeWidth ("After Near Edge Width", Float) = 1.5

        _Mid1StartDistance ("Mid 1 Start Z", Float) = 3
        _Mid1EndDistance ("Mid 1 End Z", Float) = 10
        _Mid1EdgeWidth ("Mid 1 Edge Width", Float) = 1.5

        _Mid2StartDistance ("Mid 2 Start Z", Float) = 7
        _Mid2EndDistance ("Mid 2 End Z", Float) = 16
        _Mid2EdgeWidth ("Mid 2 Edge Width", Float) = 2

        _FarStartDistance ("Far Start Z", Float) = 12
        _FarEndDistance ("Far End Z", Float) = 40
        _FarEdgeWidth ("Far Edge Width", Float) = 3

        _AfterFarStartDistance ("After Far Start Z", Float) = 32
        _AfterFarEndDistance ("After Far End Z", Float) = 43
        _AfterFarEdgeWidth ("After Far Edge Width", Float) = 3

        _BeyondFarStartDistance ("Beyond Far Start Z", Float) = 45
        _BeyondFarEndDistance ("Beyond Far End Z", Float) = 10000
        _BeyondFarEdgeWidth ("Beyond Far Edge Width", Float) = 3


        [Header(Near Color Boundary Noise)]
        _NearNoiseStrength ("Near Noise Displacement (Gradient Units)", Range(0, 5)) = 1.2
        _NearNoiseScale ("Near Noise Size (Local Units)", Float) = 2
        _NearNoiseStretch ("Near Noise Stretch (X Z)", Vector) = (5, 1, 0, 0)

        [Header(After Near Color Boundary Noise)]
        _AfterNearNoiseStrength ("After Near Noise Displacement (Gradient Units)", Range(0, 5)) = 1.2
        _AfterNearNoiseScale ("After Near Noise Size (Local Units)", Float) = 2
        _AfterNearNoiseStretch ("After Near Noise Stretch (X Z)", Vector) = (5, 1, 0, 0)

        [Header(Mid 1 Color Boundary Noise)]
        _Mid1NoiseStrength ("Mid 1 Noise Displacement (Gradient Units)", Range(0, 5)) = 1.2
        _Mid1NoiseScale ("Mid 1 Noise Size (Local Units)", Float) = 2
        _Mid1NoiseStretch ("Mid 1 Noise Stretch (X Z)", Vector) = (5, 1, 0, 0)

        [Header(Mid 2 Color Boundary Noise)]
        _Mid2NoiseStrength ("Mid 2 Noise Displacement (Gradient Units)", Range(0, 5)) = 1.2
        _Mid2NoiseScale ("Mid 2 Noise Size (Local Units)", Float) = 2
        _Mid2NoiseStretch ("Mid 2 Noise Stretch (X Z)", Vector) = (5, 1, 0, 0)

        [Header(Far Color Boundary Noise)]
        _FarNoiseStrength ("Far Noise Displacement (Gradient Units)", Range(0, 5)) = 1.2
        _FarNoiseScale ("Far Noise Size (Local Units)", Float) = 2
        _FarNoiseStretch ("Far Noise Stretch (X Z)", Vector) = (5, 1, 0, 0)

        [Header(After Far Color Boundary Noise)]
        _AfterFarNoiseStrength ("After Far Noise Displacement (Gradient Units)", Range(0, 5)) = 1.2
        _AfterFarNoiseScale ("After Far Noise Size (Local Units)", Float) = 2
        _AfterFarNoiseStretch ("After Far Noise Stretch (X Z)", Vector) = (5, 1, 0, 0)

        [Header(Beyond Far Color Boundary Noise)]
        _BeyondFarNoiseStrength ("Beyond Far Noise Displacement (Gradient Units)", Range(0, 5)) = 1.2
        _BeyondFarNoiseScale ("Beyond Far Noise Size (Local Units)", Float) = 2
        _BeyondFarNoiseStretch ("Beyond Far Noise Stretch (X Z)", Vector) = (5, 1, 0, 0)

        [Header(Noise Movement)]
        _NoiseScroll ("Noise Scroll Speed Local XZ (Units per Second)", Vector) = (0, 0, 0, 0)

        _NoiseTime ("Set time for noise scroll", Float) = 20.0

        [Header(Painted Color Boundaries)]
        _ColorNoiseWarpStrength ("Color Noise Warp Strength (Local Units)", Range(0, 8)) = 2
        _ColorNoiseWarpSize ("Color Noise Warp Size (Local Units)", Float) = 3
        _ColorNoiseEvolution ("Color Noise Shape Evolution Speed", Range(0, 1)) = 0.08
        _ColorNoiseContrast ("Color Noise Contrast", Range(0.25, 4)) = 1.8
        _ColorEdgeDiffusion ("Color Edge Diffusion Variation", Range(0, 1)) = 0.5

        [Header(Independent Scrolling Normals)]
        _NormalNoiseStrength ("Procedural Normal Noise Strength", Range(0, 2)) = 0.22
        _NormalNoiseSize ("Normal Noise Size (World Units)", Float) = 1.2
        _NormalNoiseStretch ("Normal Noise Stretch XZ", Vector) = (2, 1, 0, 0)
        _NormalScrollA ("Normal A Sampling Velocity XZ", Vector) = (0.12, 0.04, 0, 0)
        _NormalScrollB ("Normal B Sampling Velocity XZ", Vector) = (-0.06, 0.09, 0, 0)
        _NormalDetailScale ("Normal B Relative Frequency", Range(0.25, 8)) = 2.17
        _NormalDetailWeight ("Procedural Normal B Weight", Range(0, 1)) = 0.45
        [Normal] [NoScaleOffset] _NormalMapA ("Optional Normal Map A", 2D) = "bump" {}
        [Normal] [NoScaleOffset] _NormalMapB ("Optional Normal Map B", 2D) = "bump" {}
        _NormalMapStrengthA ("Normal Map A Strength", Range(0, 2)) = 0.3
        _NormalMapStrengthB ("Normal Map B Strength", Range(0, 2)) = 0.18
        _NormalReflectionInfluence ("Normal Noise Influence On Reflections", Range(0, 2)) = 0.6

        [Header(Ripples)]
        [NoScaleOffset] _RippleTex ("Ripple Texture", 2D) = "black" {}
        _RippleCameraSize ("Ripple Camera Half Size", Float) = 0
        _RippleCameraPos ("Ripple Camera Position", Vector) = (0, 0, 0, 0)
        _RippleTextureSize ("Ripple Texture Resolution", Float) = 512
        _RippleStrength ("Ripple Normal Strength", Range(0, 100)) = 15
        _RippleShading ("Ripple Light-Dark Contrast", Range(0, 2)) = 0.5

        
        [Header(Ripple Peak Color)]
        [HDR] _RipplePeakColor ("Ripple Peak Color HDR", Color) = (0.25, 0.8, 1.0, 1)
        _RipplePeakStrength ("Ripple Peak Tint Strength", Range(0, 2)) = 0.15
        _RipplePeakSharpness ("Ripple Peak Sharpness", Range(1, 8)) = 2
        _RippleRestHeight ("Ripple Texture Rest Height", Float) = 0
        _RipplePeakHeight ("Ripple Height For Full Tint", Float) = 0.1

        [Header(Planar Reflections)]
        _ReflectionStrength ("Reflection Strength", Range(0, 1)) = 0.65
        _ReflectionDistortion ("Ripple and Normal Reflection Distortion", Range(0, 0.1)) = 0.012

        [Header(Surface Brightness and Specular)]
        _SurfaceBrightness ("Overall Water Brightness", Range(0, 4)) = 1
        _ShadowStrength ("Main Light Shadow Strength", Range(0, 1)) = 1
        [HDR] _ShadowColor ("Shadow Color", Color) = (0.01, 0.025, 0.06, 1)
        [HDR] _SpecularColor ("Specular Highlight Color", Color) = (1, 1, 1, 1)
        _SpecularStrength ("Specular Brightness", Range(0, 20)) = 2
        _SpecularPower ("Specular Sharpness", Range(1, 1024)) = 96
        _SpecularDirection ("Direction To Highlight Source (World)", Vector) = (0.3, 1, 0.2, 0)
        _SpecularRippleInfluence ("Ripple Influence On Specular", Range(0, 3)) = 1

        [Header(Dark Spots)]
        [HDR] _DarkSpotColor ("Dark Spot Color", Color) = (0.01, 0.02, 0.05, 1)
        _DarkSpotStrength ("Dark Spot Strength", Range(0, 20)) = 2
        _DarkSpotPower ("Dark Spot Sharpness", Range(1, 1024)) = 96
        _DarkSpotDirection ("Direction To Dark Spot Source (World)", Vector) = (-0.3, 1, -0.2, 0)

        [HDR] _SuperSpecularColor ("Super Specular Highlight Color", Color) = (1, 1, 1, 1)
        _SuperSpecularStrength ("Super Specular Brightness", Range(0, 20)) = 2
        _SuperSpecularPower ("Super Specular Sharpness", Range(1, 8000)) = 96
        _SuperSpecularDir ("Specular Direction", Vector) = (0.5, 0.8, 0.2, 0)

        _UseStencil ("Use Stencil Mask", Float) = 0
        [HideInInspector] _RippleCameraRight ("Ripple Camera Right", Vector) = (1, 0, 0, 0)
        [HideInInspector] _RippleCameraUp ("Ripple Camera Up", Vector) = (0, 0, 1, 0)
        [HideInInspector] _RippleCameraAspect ("Ripple Camera Aspect", Float) = 1.0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "DisableBatching" = "True"
        }

        Pass
        {
            Name "Forward"
            Tags { "LightMode" = "UniversalForward" }

            Cull Back
            ZWrite Off
            ZTest LEqual
            Blend SrcAlpha OneMinusSrcAlpha

            
            Stencil
            {
                Ref [_UseStencil]
                Comp Equal
                Pass Keep
            }


            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_SCREEN

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"

            TEXTURE2D(_NormalMapA); SAMPLER(sampler_NormalMapA);
            TEXTURE2D(_NormalMapB); SAMPLER(sampler_NormalMapB);

            TEXTURE2D(_RippleTex);
            SAMPLER(sampler_RippleTex);

            // Written by the project's existing Mobile SSPR renderer.
            // The texture alpha encodes which reflection pixels are valid.
            TEXTURE2D(_MobileSSPR_ColorRT);
            SAMPLER(sampler_MobileSSPR_ColorRT);

            CBUFFER_START(UnityPerMaterial)
                float _GradientZScale, _GradientZOffset;
                float4 _NearColor, _AfterNearColor, _Mid1Color, _Mid2Color;
                float4 _FarColor, _AfterFarColor, _BeyondFarColor;
                float _NearStartDistance, _NearEndDistance, _NearEdgeWidth;
                float _AfterNearStartDistance, _AfterNearEndDistance, _AfterNearEdgeWidth;
                float _Mid1StartDistance, _Mid1EndDistance, _Mid1EdgeWidth;
                float _Mid2StartDistance, _Mid2EndDistance, _Mid2EdgeWidth;
                float _FarStartDistance, _FarEndDistance, _FarEdgeWidth;
                float _AfterFarStartDistance, _AfterFarEndDistance, _AfterFarEdgeWidth;
                float _BeyondFarStartDistance, _BeyondFarEndDistance, _BeyondFarEdgeWidth;

                float _NearNoiseStrength, _NearNoiseScale;
                float4 _NearNoiseStretch;
                float _AfterNearNoiseStrength, _AfterNearNoiseScale;
                float4 _AfterNearNoiseStretch;
                float _Mid1NoiseStrength, _Mid1NoiseScale;
                float4 _Mid1NoiseStretch;
                float _Mid2NoiseStrength, _Mid2NoiseScale;
                float4 _Mid2NoiseStretch;
                float _FarNoiseStrength, _FarNoiseScale;
                float4 _FarNoiseStretch;
                float _AfterFarNoiseStrength, _AfterFarNoiseScale;
                float4 _AfterFarNoiseStretch;
                float _BeyondFarNoiseStrength, _BeyondFarNoiseScale;
                float4 _BeyondFarNoiseStretch;
                float4 _NoiseScroll;
                float _NoiseTime;

                float _ColorNoiseWarpStrength, _ColorNoiseWarpSize, _ColorNoiseEvolution;
                float _ColorNoiseContrast, _ColorEdgeDiffusion;
                float _NormalNoiseStrength, _NormalNoiseSize;
                float4 _NormalNoiseStretch, _NormalScrollA, _NormalScrollB;
                float _NormalDetailScale, _NormalDetailWeight;
                float _NormalMapStrengthA, _NormalMapStrengthB, _NormalReflectionInfluence;

                float _RippleCameraSize;
                float4 _RippleCameraPos;
                float _RippleTextureSize, _RippleStrength, _RippleShading;
                float4 _RipplePeakColor;
                float _RipplePeakStrength, _RipplePeakSharpness;
                float _RippleRestHeight, _RipplePeakHeight;
                float _ReflectionStrength, _ReflectionDistortion;

                float _SurfaceBrightness;
                float _ShadowStrength;
                float4 _ShadowColor;
                float4 _SpecularColor;
                float _SpecularStrength, _SpecularPower;
                float4 _SpecularDirection;
                float _SpecularRippleInfluence;
                float4 _SuperSpecularDir;
                float4 _SuperSpecularColor;
                float _SuperSpecularStrength, _SuperSpecularPower;

                float4 _DarkSpotColor;
                float _DarkSpotStrength, _DarkSpotPower;
                float4 _DarkSpotDirection;

                float4 _RippleCameraRight;
                float4 _RippleCameraUp;
                float _RippleCameraAspect;
            CBUFFER_END

            struct Attributes
            {
                float3 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float2 localXZ : TEXCOORD2;
                float4 shadowCoord : TEXCOORD3;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.localXZ = input.positionOS.xz;
                output.positionWS = TransformObjectToWorld(input.positionOS);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.shadowCoord = TransformWorldToShadowCoord(output.positionWS);
                return output;
            }

            // Smooth procedural value noise, returning approximately [-1, 1].

            float2 GetRippleUV(float3 worldPos)
            {
                float3 delta = worldPos - _RippleCameraPos.xyz;

                float3 camRight = normalize(_RippleCameraRight.xyz);
                float3 camUp = normalize(_RippleCameraUp.xyz);

                float halfHeight = max(_RippleCameraSize, 0.0001);
                float halfWidth = halfHeight * max(_RippleCameraAspect, 0.0001);

                float u = dot(delta, camRight) / (2.0 * halfWidth) + 0.5;
                float v = dot(delta, camUp) / (2.0 * halfHeight) + 0.5;

                return float2(u, v);
            }


            float Hash(float2 p)
            {
                return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
            }

            float ValueNoise(float2 p)
            {
                float2 cell = floor(p);
                float2 f = frac(p);
                f = f * f * (3.0 - 2.0 * f);

                float n00 = Hash(cell);
                float n10 = Hash(cell + float2(1, 0));
                float n01 = Hash(cell + float2(0, 1));
                float n11 = Hash(cell + float2(1, 1));

                float a = lerp(n00, n10, f.x);
                float b = lerp(n01, n11, f.x);
                return lerp(a, b, f.y) * 2.0 - 1.0;
            }

            float remap(float v, float minOld, float maxOld, float minNew, float maxNew) {
                return minNew + (v - minOld) * (maxNew - minNew) / (maxOld - minOld);
            }

            // Two scales give the border a broad shape with finer breakup.
            float OrganicNoise(float2 p)
            {
                return (ValueNoise(p) + 0.45 * ValueNoise(p * 2.17 + float2(17.2, -9.7))) / 1.45;
            }

            // Stretch > 1 makes features longer along that local axis.
            // Each color band has its own noise profile.
            float StopNoise(float2 localXZ, float size, float2 stretch, float2 seed)
            {
                float2 localSize = max(abs(stretch), float2(0.01, 0.01)) * max(abs(size), 0.01);
                float n = OrganicNoise(localXZ / localSize + seed);
                return clamp(n * _ColorNoiseContrast, -1.0, 1.0);
            }

            // One band with soft tails. Edge width and noise offsets use
            // the same mapped local-Z units as the band's start and end.
            float ColorBandWeight(
                float gradientZ,
                float startZ,
                float endZ,
                float edgeWidth,
                float noiseOffset,
                float diffusionNoise)
            {
                // Allow Start and End to be entered in either order.
                float bandStart = min(startZ, endZ);
                float bandEnd = max(startZ, endZ);

                float diffusion = saturate(diffusionNoise * 0.5 + 0.5);
                float diffusionMultiplier =
                    lerp(1.0, lerp(0.4, 1.8, diffusion), _ColorEdgeDiffusion);

                float softness = max(abs(edgeWidth) * diffusionMultiplier, 0.0001);

                // Using the same displacement for both boundaries preserves the band's
                // local thickness while still giving it an irregular painted outline.
                float displacedZ = gradientZ + noiseOffset;

                // Full strength from bandStart through bandEnd, with soft tails outside.
                float fadeIn = smoothstep(
                    bandStart - softness,
                    bandStart,
                    displacedZ);

                float fadeOut = 1.0 - smoothstep(
                    bandEnd,
                    bandEnd + softness,
                    displacedZ);

                return saturate(fadeIn * fadeOut);
            }

            // Alpha-composite a farther band over the bands already evaluated.
            // The returned RGB is straight-alpha, matching the pass blend mode.
            float4 CompositeColorBand(float4 underColor, float4 overColor, float coverage)
            {
                float overAlpha = saturate(overColor.a * coverage);
                float outAlpha = overAlpha + underColor.a * (1.0 - overAlpha);
                float3 outPremultiplied =
                      overColor.rgb * overAlpha
                    + underColor.rgb * underColor.a * (1.0 - overAlpha);

                return float4(
                    outPremultiplied / max(outAlpha, 0.0001),
                    outAlpha);
            }

            float4 EvaluateGradient(float gradientZ, float2 localXZ)
            {
                float2 noisePos = localXZ + _NoiseScroll.xy * _NoiseTime;

                // Shared animated domain warp.
                float2 warpUV =
                    noisePos / max(abs(_ColorNoiseWarpSize), 0.01);

                float evolution = _NoiseTime * _ColorNoiseEvolution;

                float2 warp = float2(
                    OrganicNoise(
                        warpUV
                        + float2(0.31, 0.19) * evolution
                        + float2(7.3, 19.8)),
                    OrganicNoise(
                        warpUV
                        + float2(-0.23, 0.27) * evolution
                        + float2(-23.4, 3.9))
                );

                noisePos += warp * _ColorNoiseWarpStrength;

                float n0 = StopNoise(
                    noisePos,
                    _NearNoiseScale,
                    _NearNoiseStretch.xy,
                    float2(13.1, 3.6));

                float n1 = StopNoise(
                    noisePos,
                    _AfterNearNoiseScale,
                    _AfterNearNoiseStretch.xy,
                    float2(18.0f, -8.2f));

                float n2 = StopNoise(
                    noisePos,
                    _Mid1NoiseScale,
                    _Mid1NoiseStretch.xy,
                    float2(-5.7, 29.4));

                float n3 = StopNoise(
                    noisePos,
                    _Mid2NoiseScale,
                    _Mid2NoiseStretch.xy,
                    float2(41.3, -10.8));

                float n4 = StopNoise(
                    noisePos,
                    _FarNoiseScale,
                    _FarNoiseStretch.xy,
                    float2(8.5, 52.1));

                float n5 = StopNoise(
                    noisePos,
                    _AfterFarNoiseScale,
                    _AfterFarNoiseStretch.xy,
                    float2(26.8, -37.1));

                float n6 = StopNoise(
                    noisePos,
                    _BeyondFarNoiseScale,
                    _BeyondFarNoiseStretch.xy,
                    float2(-31.7, 14.6));

                float w0 = ColorBandWeight(
                    gradientZ,
                    _NearStartDistance,
                    _NearEndDistance,
                    _NearEdgeWidth,
                    n0 * _NearNoiseStrength,
                    n0);

                float w1 = ColorBandWeight(
                    gradientZ,
                    _AfterNearStartDistance,
                    _AfterNearEndDistance,
                    _AfterNearEdgeWidth,
                    n1 * _AfterNearNoiseStrength,
                    n1);

                float w2 = ColorBandWeight(
                    gradientZ,
                    _Mid1StartDistance,
                    _Mid1EndDistance,
                    _Mid1EdgeWidth,
                    n2 * _Mid1NoiseStrength,
                    n2);

                float w3 = ColorBandWeight(
                    gradientZ,
                    _Mid2StartDistance,
                    _Mid2EndDistance,
                    _Mid2EdgeWidth,
                    n3 * _Mid2NoiseStrength,
                    n3);

                float w4 = ColorBandWeight(
                    gradientZ,
                    _FarStartDistance,
                    _FarEndDistance,
                    _FarEdgeWidth,
                    n4 * _FarNoiseStrength,
                    n4);

                float w5 = ColorBandWeight(
                    gradientZ,
                    _AfterFarStartDistance,
                    _AfterFarEndDistance,
                    _AfterFarEdgeWidth,
                    n5 * _AfterFarNoiseStrength,
                    n5);

                float w6 = ColorBandWeight(
                    gradientZ,
                    _BeyondFarStartDistance,
                    _BeyondFarEndDistance,
                    _BeyondFarEdgeWidth,
                    n6 * _BeyondFarNoiseStrength,
                    n6);

                // Process near to far. Each later band is composited on top,
                // so farther colors take priority in overlaps.
                float4 color = float4(0, 0, 0, 0);
                color = CompositeColorBand(color, _NearColor, w0);
                color = CompositeColorBand(color, _AfterNearColor, w1);
                color = CompositeColorBand(color, _Mid1Color, w2);
                color = CompositeColorBand(color, _Mid2Color, w3);
                color = CompositeColorBand(color, _FarColor, w4);
                color = CompositeColorBand(color, _AfterFarColor, w5);
                color = CompositeColorBand(color, _BeyondFarColor, w6);

                return color;
            }

            // Analytic derivative of ValueNoise; XY is the height-field slope.
            // Only the normal layer uses this function.
            float2 ValueNoiseGradient(float2 p)
            {
                float2 cell = floor(p);
                float2 f = frac(p);
                float2 u = f * f * (3.0 - 2.0 * f);
                float2 du = 6.0 * f * (1.0 - f);
                float a = Hash(cell);
                float b = Hash(cell + float2(1, 0));
                float c = Hash(cell + float2(0, 1));
                float d = Hash(cell + float2(1, 1));
                float mixed = a - b - c + d;
                return 2.0 * du * float2(b - a + mixed * u.y,
                                         c - a + mixed * u.x);
            }

            float ProceduralDetailVisibility(float2 uv)
            {
                float footprint = max(length(ddx(uv)), length(ddy(uv)));
                return 1.0 - smoothstep(0.15, 0.6, footprint);
            }

            float3 GetNormalNoiseTilt(float2 worldXZ)
            {
                float2 stretch = max(abs(_NormalNoiseStretch.xy), float2(0.01, 0.01));
                float size = max(abs(_NormalNoiseSize), 0.01);
                float frequencyB = max(_NormalDetailScale, 0.01);
                float2 uvA = (worldXZ + _NormalScrollA.xy * _Time.y) / (size * stretch);
                float2 uvB = (worldXZ + _NormalScrollB.xy * _Time.y)
                    / (size * stretch) * frequencyB + float2(17.2, -9.7);

                float2 slopeA = ValueNoiseGradient(uvA) * ProceduralDetailVisibility(uvA);
                float2 slopeB = ValueNoiseGradient(uvB) * ProceduralDetailVisibility(uvB);
                // Derivatives of a virtual height field. Height scales with tile size
                // so the strength remains an angular art control when size changes.
                float2 slope = (slopeA + slopeB * frequencyB * _NormalDetailWeight)
                    / ((1.0 + _NormalDetailWeight) * stretch);
                float2 tilt = -slope * _NormalNoiseStrength;

                // Decode Unity normal-map packing, then combine their tilts.
                // Flat default maps contribute zero; procedural noise needs no asset.
                float3 a = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMapA, sampler_NormalMapA, uvA));
                float3 b = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMapB, sampler_NormalMapB, uvB));
                tilt += a.xy / max(a.z, 0.2) * _NormalMapStrengthA;
                tilt -= b.xy / max(b.z, 0.2) * _NormalMapStrengthB;
                return float3(tilt.x, 0.0, tilt.y);
            }

            // Same ripple RT mapping as your existing handwritten water shader.
            float2 GetRippleSlope(float3 worldPos, out float peakMask)
            {
                peakMask = 0.0;
                if (_RippleCameraSize <= 0.00001)
                    return float2(0.0, 0.0);

                float2 uv = GetRippleUV(worldPos);

                float pixel = 1.0 / max(_RippleTextureSize, 1.0);
                float edge = min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y));

                if (edge <= pixel)
                    return float2(0.0, 0.0);

                float fade = smoothstep(pixel, pixel * 5.0, edge);

                float height = SAMPLE_TEXTURE2D(_RippleTex, sampler_RippleTex, uv).r;
                float crest = saturate((height - _RippleRestHeight)
                    / max(_RipplePeakHeight, 0.00001));
                peakMask = pow(crest, max(_RipplePeakSharpness, 1.0)) * fade;

                float right = SAMPLE_TEXTURE2D(_RippleTex, sampler_RippleTex,
                                               uv + float2(pixel, 0)).r;
                float left  = SAMPLE_TEXTURE2D(_RippleTex, sampler_RippleTex,
                                               uv - float2(pixel, 0)).r;
                float up    = SAMPLE_TEXTURE2D(_RippleTex, sampler_RippleTex,
                                               uv + float2(0, pixel)).r;
                float down  = SAMPLE_TEXTURE2D(_RippleTex, sampler_RippleTex,
                                               uv - float2(0, pixel)).r;
                return 0.5 * float2(right - left, up - down) * fade;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                // Signed mesh-local Z, independent of the camera and object transform.
                float gradientZ = input.localXZ.y * _GradientZScale + _GradientZOffset;
                float4 gradient = EvaluateGradient(gradientZ, input.localXZ);

                // Retain the original distance fade for specular and dark spots only.
                float cameraDistance = distance(GetCameraPositionWS(), input.positionWS);

                float3 normalNoiseTiltWS = GetNormalNoiseTilt(input.positionWS.xz);
                float ripplePeakMask;
                float2 slope = GetRippleSlope(input.positionWS, ripplePeakMask);
                float3 rippleTiltWS =
                    (
                        -normalize(_RippleCameraRight.xyz) * slope.x
                        -normalize(_RippleCameraUp.xyz) * slope.y
                    ) * _RippleStrength;

                // Preserve the existing ripple brightness/shading behavior.
                float lightDark = dot(rippleTiltWS.xz, normalize(float2(0.8, 0.6)));
                gradient.rgb *= max(0.0, 1.0 + lightDark * _RippleShading);
                gradient.rgb *= _SurfaceBrightness;

                // Keep the original Mobile SSPR reflection texture and blending.
                float2 screenUV = GetNormalizedScreenSpaceUV(input.positionCS);
                float3 reflectionTiltWS = rippleTiltWS
                    + normalNoiseTiltWS * _NormalReflectionInfluence;
                float2 rippleTiltVS = TransformWorldToViewDir(reflectionTiltWS, false).xy;
                float2 reflectionUV = saturate(screenUV + rippleTiltVS * _ReflectionDistortion);
                half4 reflection = SAMPLE_TEXTURE2D(
                    _MobileSSPR_ColorRT, sampler_MobileSSPR_ColorRT, reflectionUV);
                float reflectionBlend = saturate(reflection.a * _ReflectionStrength);
                gradient.rgb = lerp(gradient.rgb, reflection.rgb, reflectionBlend);

                // Simple Blinn-Phong highlight. Direction is art-directable and
                // does not require a particular main light or lighting setup.
                float3 normalWS = normalize(input.normalWS
                    + rippleTiltWS * _SpecularRippleInfluence + normalNoiseTiltWS);

                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                float3 lightDirWS = normalize(_SpecularDirection.xyz + float3(0.0, 0.00001, 0.0));
                float3 halfDirWS = normalize(lightDirWS + viewDirWS + float3(0.0, 0.00001, 0.0));
                float ndotl = saturate(dot(normalWS, lightDirWS));

                float restrictedLambert = ndotl * pow(1.0f - saturate(dot(normalWS, viewDirWS)), 3.0f); // optional Fresnel effect

                float highlight = pow(saturate(dot(normalWS, halfDirWS)), _SpecularPower) * restrictedLambert;
                highlight *= gradient.a; // fade highlight with water opacity
                gradient.rgb += _SpecularColor.rgb * (highlight * _SpecularStrength);

                // super specular highlight
                float superLambert = ndotl;

                // Camera-distance fade for surface highlights only
                float dist = cameraDistance; 
                dist = remap(dist, 0.0f, 20.0f, 0.0f, 1.0f);
                dist = clamp(dist, 0.0f, 1.0f);

                float3 superHalfVector = normalize(normalize(_SuperSpecularDir.xyz) + viewDirWS);

                superLambert *= pow(dist, 2.0f); // fade highlight with distance

                float superHighlight = pow(saturate(dot(normalWS, superHalfVector)), _SuperSpecularPower) * superLambert;
                superHighlight *= gradient.a; // fade highlight with water opacity
                gradient.rgb += _SuperSpecularColor.rgb * (superHighlight * _SuperSpecularStrength);

                // --- Dark Spots ---
                float3 darkLightDirWS = normalize(_DarkSpotDirection.xyz + float3(0.0, 0.00001, 0.0));
                float3 darkHalfDirWS = normalize(darkLightDirWS + viewDirWS + float3(0.0, 0.00001, 0.0));
                float darkNdotl = saturate(dot(normalWS, darkLightDirWS));
                darkNdotl *= pow(dist, 2.0f);

                float darkRestrictedLambert = darkNdotl * pow(1.0f - saturate(dot(normalWS, viewDirWS)), 3.0f);

                float darkSpot = pow(saturate(dot(normalWS, darkHalfDirWS)), _DarkSpotPower) * darkRestrictedLambert;
                darkSpot *= gradient.a; // fade with water opacity
                
                // Lerp towards the dark color based on the dark spot intensity and strength, mirroring the specular implementation.
                gradient.rgb = lerp(gradient.rgb, _DarkSpotColor.rgb * (darkSpot * _DarkSpotStrength), saturate(darkSpot * _DarkSpotStrength));


                gradient.rgb += _RipplePeakColor.rgb
                    * (_RipplePeakStrength * ripplePeakMask);

                // Main-light shadow attenuation and received shadow tint.
                // ShadowColor alpha controls how strongly the tint is applied.
                half mainLightShadow = MainLightRealtimeShadow(input.shadowCoord);
                half shadowDarkening = lerp(1.0h, mainLightShadow, saturate(_ShadowStrength));
                gradient.rgb *= shadowDarkening;

                half shadowAmount = (1.0h - mainLightShadow)
                    * saturate(_ShadowStrength)
                    * saturate(_ShadowColor.a);
                gradient.rgb = lerp(gradient.rgb, _ShadowColor.rgb, shadowAmount);

                return half4(gradient.rgb, saturate(gradient.a));
            }
            ENDHLSL
        }
    }
    FallBack Off
}

