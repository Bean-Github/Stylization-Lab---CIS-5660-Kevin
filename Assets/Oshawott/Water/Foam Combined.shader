Shader "Custom/Foam/Foam Combined"
{
    Properties
    {
        [Header(Shape and Deformation)]
        [Enum(XY,0,XZ,1)] _SourcePlane ("Source Mesh Plane", Float) = 1
        _Amplitude ("Y Displacement (Local Units)", Range(0, 5)) = 0.35
        _CurveAmount ("Base Curve Amount", Float) = 0
        _Frequency ("Shape Frequency (Per Local X Unit)", Range(0.01, 5)) = 0.6
        _EvolutionSpeed ("Evolution Speed", Range(0, 1.0)) = 0.025
        _Seed ("Shape Noise Seed", Float) = 0
        _WidthScale ("Base Width Multiplier", Range(0.01, 2)) = 0.1
        _WidthVariation ("Width Variation", Range(0, 0.95)) = 0.65
        _WidthFrequency ("Width Frequency (Per Local X Unit)", Range(0.01, 5)) = 0.45
        _OverallSizeMult ("Overall Size Multiplier (Script Control)", Range(0.01, 2)) = 1.0

        [Header(Color and Flow)]
        [HDR] _FoamColor ("Foam Color (Alpha = Max Opacity)", Color) = (0.96, 0.99, 1.0, 1.0)
        [HDR] _ShadeColor ("Foam Shade Color (RGB)", Color) = (0.55, 0.77, 0.82, 1.0)
        _ColorVariation ("Color Variation", Range(0, 1)) = 0.25
        _EdgeSoftness ("Edge Softness", Range(0.001, 1.0)) = 0.1
        _OverallAlpha ("Overall Alpha (Script Control)", Range(0, 1)) = 1.0

        [Header(Animation and Distortion)]
        _TimeScale ("Time Scale", Float) = 1.0
        _FlowDirection ("Flow Direction (U, V)", Vector) = (0.05, 0.02, 0, 0)
        _DistortionAmount ("Distortion Amount", Range(0, 1)) = 0.2

        [Header(Noise Settings)]
        _GrainTiling ("Grain Tiling (X = U, Y = V)", Vector) = (512, 64, 0, 0)
        _NoiseSeed ("Texture Noise Seed", Float) = 0
        _PerlinMix ("Perlin / FBM Mix", Range(0, 1)) = 0.65

        [Header(Coverage Gradient)]
        [Enum(U,0,V,1)] _FadeAxis ("Gradient UV Axis", Float) = 1
        [Toggle] _FlipFade ("Flip Gradient", Float) = 0
        _FadeStart ("Fade Start", Range(0, 1)) = 0
        _FadeEnd ("Fade End (Fully Dense From Here)", Range(0, 1)) = 0.9
        _FadePower ("Fade Curve", Range(0.2, 5)) = 1.5
        _SparseCoverage ("Faded Edge Coverage", Range(0, 1)) = 0.04
        _DenseCoverage ("Solid Edge Coverage", Range(0, 1)) = 1

        _PatchTiling ("Soft Noise Tiling (U, V)", Vector) = (12, 3, 0, 0)
        _DensityBreakup ("Patchy Coverage Variation", Range(0, 0.5)) = 0.15
    
        [Header(Shadows)]
        _ReceiveShadowStrength ("Receive Shadow Strength", Range(0, 1)) = 1
        _ShadowCutoff ("Shadow Cast Cutoff", Range(0, 1)) = 0.5

        [Header(Stencil)]
        [IntRange] _UseStencil ("Stencil Reference", Range(0, 255)) = 0

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

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"

        float _Seed;
        float _OverallAlpha;
        float _NoiseSeed;
        float _OverallSizeMult;
        
        CBUFFER_START(UnityPerMaterial)
            // Shape
            float _SourcePlane;
            float _Amplitude;
            float _CurveAmount;
            float _Frequency;
            float _EvolutionSpeed;
            float _WidthScale;
            float _WidthVariation;
            float _WidthFrequency;

            // Flow & Color
            float4 _FoamColor;
            float4 _ShadeColor;
            float4 _GrainTiling;
            float4 _PatchTiling;
            float4 _FlowDirection;
            float _ColorVariation;
            float _EdgeSoftness;
            float _PerlinMix;
            float _FadeAxis;
            float _FlipFade;
            float _FadeStart;
            float _FadeEnd;
            float _FadePower;
            float _SparseCoverage;
            float _DenseCoverage;
            float _DensityBreakup;
            float _TimeScale;
            float _DistortionAmount;
            float _ReceiveShadowStrength;
            float _ShadowCutoff;
        CBUFFER_END

        // ==========================================
        // 1D NOISE & VERTEX DEFORMATION FUNCTIONS
        // ==========================================
        float FoamSmooth(float x) {
            return x * x * x * (x * (x * 6.0 - 15.0) + 10.0);
        }

        float FoamHash(float n) {
            n = frac(n * 0.1031);
            n *= n + 33.33;
            n *= n + n;
            return frac(n) * 2.0 - 1.0;
        }

        float FoamNoise1D(float x, float seed) {
            float cell = floor(x);
            float blend = FoamSmooth(frac(x));
            float a = FoamHash(cell + seed);
            float b = FoamHash(cell + 1.0 + seed);
            return lerp(a, b, blend);
        }

        float FoamEvolvingNoise1D(float x, float time, float seed) {
            float frame = floor(time);
            float blend = FoamSmooth(frac(time));
            float a = FoamNoise1D(x, seed + frame * 71.713);
            float b = FoamNoise1D(x, seed + (frame + 1.0) * 71.713);
            return lerp(a, b, blend);
        }

        float FoamFBM1D(float x, float time, float seed) {
            float sum = 0.0;
            float weight = 0.5;
            float totalWeight = 0.0;
            [unroll]
            for (int octave = 0; octave < 4; ++octave) {
                float octaveTime = time * (1.0 + 0.17 * octave) + 0.37 * octave;
                sum += weight * FoamEvolvingNoise1D(x, octaveTime, seed);
                totalWeight += weight;
                x = x * 2.03 + 13.71;
                seed += 31.91;
                weight *= 0.5;
            }
            return sum / totalWeight;
        }

        float3 DeformFoam(float3 positionOS, float timeSeconds) {
            if (_SourcePlane > 0.5)
                positionOS = float3(positionOS.x, positionOS.z, -positionOS.y);

            float restX = positionOS.x;
            float restY = positionOS.y;
            float time = timeSeconds * max(_EvolutionSpeed, 0.0);

            // Build a downward-opening parabola whose highest point is at local X = 0.
            // Positive values make the foam fall away from the center. The existing
            // noise displacement is then applied outward from this curved baseline.
            float curveY = -_CurveAmount * restX * restX;
            float centerY = curveY
                + _Amplitude * FoamFBM1D(restX * _Frequency, time, _Seed);

            float widthNoise = FoamFBM1D(
                restX * _WidthFrequency + 47.23,
                time * 0.83 + 0.61,
                _Seed + 113.17);

            float widthMultiplier = max(_WidthScale, 0.001)
                * (1.0 + clamp(_WidthVariation, 0.0, 0.95) * widthNoise);

            widthMultiplier *= _OverallSizeMult;

            positionOS.y = centerY + restY * widthMultiplier;
            return positionOS;
        }

        // ==========================================
        // 2D NOISE & FRAGMENT COVERAGE FUNCTIONS
        // ==========================================
        float FoamHash21(float2 p) {
            float3 p3 = frac(float3(p.x, p.y, p.x) * 0.1031);
            p3 += dot(p3, p3.yzx + 33.33);
            return frac((p3.x + p3.y) * p3.z);
        }

        float2 FoamHash22(float2 p) {
            p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
            return -1.0 + 2.0 * frac(sin(p) * 43758.5453123);
        }

        float FoamValueNoise(float2 p) {
            float2 cell = floor(p);
            float2 f = frac(p);
            float2 blend = f * f * (3.0 - 2.0 * f);
            float a = FoamHash21(cell);
            float b = FoamHash21(cell + float2(1, 0));
            float c = FoamHash21(cell + float2(0, 1));
            float d = FoamHash21(cell + float2(1, 1));
            return lerp(lerp(a, b, blend.x), lerp(c, d, blend.x), blend.y);
        }

        float FoamPerlin(float2 p) {
            float2 pi = floor(p);
            float2 pf = frac(p);
            float2 w = pf * pf * pf * (pf * (pf * 6.0 - 15.0) + 10.0);
            float a = dot(FoamHash22(pi + float2(0.0, 0.0)), pf - float2(0.0, 0.0));
            float b = dot(FoamHash22(pi + float2(1.0, 0.0)), pf - float2(1.0, 0.0));
            float c = dot(FoamHash22(pi + float2(0.0, 1.0)), pf - float2(0.0, 1.0));
            float d = dot(FoamHash22(pi + float2(1.0, 1.0)), pf - float2(1.0, 1.0));
            return lerp(lerp(a, b, w.x), lerp(c, d, w.x), w.y) * 0.5 + 0.5;
        }

        float FoamFBM(float2 p) {
            float sum = 0.0;
            float weight = 0.5;
            float totalWeight = 0.0;
            [unroll]
            for (int octave = 0; octave < 4; ++octave) {
                sum += FoamValueNoise(p) * weight;
                totalWeight += weight;
                p = float2(0.8 * p.x - 0.6 * p.y, 0.6 * p.x + 0.8 * p.y) * 2.03 + float2(17.13, 9.71);
                weight *= 0.5;
            }
            return sum / totalWeight;
        }

        float FoamCoverage(float2 uv, float time) {
            float across = lerp(uv.x, uv.y, saturate(_FadeAxis));
            across = lerp(across, 1.0 - across, saturate(_FlipFade));
            float span = max(_FadeEnd - _FadeStart, 0.0001);
            float t = saturate((across - _FadeStart) / span);
            t = pow(t, max(_FadePower, 0.01));

            float2 patchUV = uv * max(_PatchTiling.xy, float2(0.01, 0.01));
            float patch = FoamValueNoise(patchUV + _NoiseSeed + 19.37 + time * 0.2);
            float coverage = lerp(_SparseCoverage, _DenseCoverage, t);

            coverage += (patch * 2.0 - 1.0) * _DensityBreakup * (4.0 * t * (1.0 - t));
            return saturate(coverage);
        }
        ENDHLSL

        Pass
        {
            Name "FoamColor"
            Tags { "LightMode" = "UniversalForward" }
            
            Cull Off
            ZWrite On
            ZTest LEqual
            Blend SrcAlpha OneMinusSrcAlpha

            Stencil
            {
                Ref [_UseStencil]
                ReadMask 255
                Comp Equal
                Pass Keep
            }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _SHADOWS_SOFT

            struct Attributes {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD1;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes IN) {
                Varyings OUT = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);
                
                float3 positionOS = DeformFoam(IN.positionOS.xyz, _Time.y);

                OUT.positionCS = TransformObjectToHClip(positionOS);
                OUT.positionWS = TransformObjectToWorld(positionOS);
                OUT.uv = IN.uv;
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target {
                float time = _Time.y * _TimeScale;
                
                float2 distortUV = IN.uv * max(_PatchTiling.xy, float2(0.01, 0.01)) - time * 0.5;
                float2 distortion = float2(
                    FoamValueNoise(distortUV + 15.2),
                    FoamValueNoise(distortUV + 42.8)
                ) * 2.0 - 1.0;

                float2 tiling = max(_GrainTiling.xy, float2(1, 1));
                float2 p = IN.uv * tiling + float2(37.17, 91.73) + _NoiseSeed;
                p += _FlowDirection.xy * time * tiling; 
                p += distortion * _DistortionAmount * tiling; 

                float fbm = FoamFBM(p);
                float perlin = FoamPerlin(p);
                
                float fbm2 = FoamFBM(p * 0.75 - _FlowDirection.xy * time * tiling * 0.5);
                float perlinFBM = perlin * fbm2 * 1.5; 
                float noise = lerp(fbm, perlinFBM, saturate(_PerlinMix));

                noise = saturate((noise - 0.5) * 1.5 + 0.5);
                float rank = lerp(0.0001, 0.9999, noise);
                float coverage = FoamCoverage(IN.uv, time);
                
                // MULTIPLY FINAL ALPHA BY OVERALL ALPHA
                float alpha = smoothstep(0.0, _EdgeSoftness, coverage - rank) * saturate(_FoamColor.a) * _OverallAlpha;

                float2 colorUV = IN.uv * max(_PatchTiling.xy, float2(0.01, 0.01));
                float shade = FoamValueNoise(colorUV + _NoiseSeed + 73.19 + time * 0.1);

                float3 color = lerp(
                    _FoamColor.rgb,
                    _ShadeColor.rgb,
                    shade * saturate(_ColorVariation)
                );

                float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);                
                Light mainLight = GetMainLight(shadowCoord);
                float shadowFactor = lerp(1.0, mainLight.shadowAttenuation, saturate(_ReceiveShadowStrength));

                color *= shadowFactor;

                alpha *= _FoamColor.a;

                if (alpha < 0.001)
                    discard;

                float2 screenUV = GetNormalizedScreenSpaceUV(IN.positionCS);

                float3 sceneColor = SampleSceneColor(screenUV).rgb;

                float3 finalColor = lerp(color, sceneColor, 1.0 - alpha);
                return half4(finalColor, 1.0f);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off

            Stencil
            {
                Ref [_UseStencil]
                ReadMask 255
                Comp Equal
                Pass Keep
            }


            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            struct Attributes {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            // Screen-space ordered dithering turns the shadow caster's alpha into
            // partial shadow coverage. This is necessary because a shadow map is
            // effectively binary at each sample.
            float ShadowDither4x4(float2 pixelPosition) {
                int2 p = int2(floor(pixelPosition)) & 3;
                const float4 row0 = float4(0.0, 8.0, 2.0, 10.0);
                const float4 row1 = float4(12.0, 4.0, 14.0, 6.0);
                const float4 row2 = float4(3.0, 11.0, 1.0, 9.0);
                const float4 row3 = float4(15.0, 7.0, 13.0, 5.0);
                float value = p.y == 0 ? row0[p.x]
                    : p.y == 1 ? row1[p.x]
                    : p.y == 2 ? row2[p.x]
                    : row3[p.x];
                return (value + 0.5) / 16.0;
            }

            Varyings ShadowVert(Attributes IN) {
                Varyings OUT;
                float3 positionOS = DeformFoam(IN.positionOS.xyz, _Time.y);
                OUT.positionCS = TransformObjectToHClip(positionOS);
                OUT.uv = IN.uv;
                return OUT;
            }

            half4 ShadowFrag(Varyings IN) : SV_Target {
                float time = _Time.y * _TimeScale;
                float coverage = FoamCoverage(IN.uv, time);

                // Convert foam alpha into dithered shadow coverage. At 50% alpha,
                // approximately half of the shadow-map samples are discarded,
                // making the cast shadow visibly lighter/fainter.
                float foamAlpha = coverage * saturate(_FoamColor.a)
                    * saturate(_OverallAlpha);
                float ditherThreshold = ShadowDither4x4(IN.positionCS.xy);
                clip(foamAlpha - max(saturate(_ShadowCutoff), ditherThreshold));
                return 0;
            }
            ENDHLSL
        }
    }
    FallBack Off
}
