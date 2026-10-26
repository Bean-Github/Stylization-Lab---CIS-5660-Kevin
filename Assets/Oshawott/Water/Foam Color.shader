Shader "Custom/Foam/FBM Perlin Transparent Flow"
{
    Properties
    {
        [HDR] _FoamColor ("Foam Color (Alpha = Max Opacity)", Color) = (0.96, 0.99, 1.0, 1.0)
        [HDR] _ShadeColor ("Foam Shade Color (RGB)", Color) = (0.55, 0.77, 0.82, 1.0)
        _ColorVariation ("Color Variation", Range(0, 1)) = 0.25
        _EdgeSoftness ("Edge Softness", Range(0.001, 1.0)) = 0.1

        [Header(Animation and Distortion)]
        _TimeScale ("Time Scale", Float) = 1.0
        _FlowDirection ("Flow Direction (U, V)", Vector) = (0.05, 0.02, 0, 0)
        _DistortionAmount ("Distortion Amount", Range(0, 1)) = 0.2

        [Header(Noise Settings)]
        // X:Y should roughly match the strip's visible length:width ratio.
        _GrainTiling ("Grain Tiling (X = U, Y = V)", Vector) = (512, 64, 0, 0)
        _NoiseSeed ("Noise Seed", Float) = 0
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
        _ShadowCutoff ("Shadow Cutoff", Range(0, 1)) = 0.5
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
        }

        Pass
        {
            Name "FoamColor"
            Tags { "LightMode" = "UniversalForward" }
            
            Cull Off
            ZWrite Off
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _FoamColor;
                float4 _ShadeColor;
                float4 _GrainTiling;
                float4 _PatchTiling;
                float4 _FlowDirection;
                float _ColorVariation;
                float _EdgeSoftness;
                float _NoiseSeed;
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

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD1;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = IN.uv;
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                return OUT;
            }

            // Stable, texture-free random value in [0, 1) for value noise
            float FoamHash21(float2 p)
            {
                float3 p3 = frac(float3(p.x, p.y, p.x) * 0.1031);
                p3 += dot(p3, p3.yzx + 33.33);
                return frac((p3.x + p3.y) * p3.z);
            }

            // Random gradient vector for Perlin noise
            float2 FoamHash22(float2 p)
            {
                p = float2(dot(p, float2(127.1, 311.7)),
                           dot(p, float2(269.5, 183.3)));
                return -1.0 + 2.0 * frac(sin(p) * 43758.5453123);
            }

            float FoamValueNoise(float2 p)
            {
                float2 cell = floor(p);
                float2 f = frac(p);
                float2 blend = f * f * (3.0 - 2.0 * f);

                float a = FoamHash21(cell);
                float b = FoamHash21(cell + float2(1, 0));
                float c = FoamHash21(cell + float2(0, 1));
                float d = FoamHash21(cell + float2(1, 1));
                return lerp(lerp(a, b, blend.x), lerp(c, d, blend.x), blend.y);
            }

            // Classic 2D Perlin Noise mapped to [0, 1]
            float FoamPerlin(float2 p)
            {
                float2 pi = floor(p);
                float2 pf = frac(p);

                // Quintic smoothstep for better derivatives
                float2 w = pf * pf * pf * (pf * (pf * 6.0 - 15.0) + 10.0);

                float a = dot(FoamHash22(pi + float2(0.0, 0.0)), pf - float2(0.0, 0.0));
                float b = dot(FoamHash22(pi + float2(1.0, 0.0)), pf - float2(1.0, 0.0));
                float c = dot(FoamHash22(pi + float2(0.0, 1.0)), pf - float2(0.0, 1.0));
                float d = dot(FoamHash22(pi + float2(1.0, 1.0)), pf - float2(1.0, 1.0));

                float noise = lerp(lerp(a, b, w.x), lerp(c, d, w.x), w.y);
                
                // Remap from roughly [-1, 1] to [0, 1]
                return noise * 0.5 + 0.5;
            }

            // Four continuous octaves of Value Noise
            float FoamFBM(float2 p)
            {
                float sum = 0.0;
                float weight = 0.5;
                float totalWeight = 0.0;

                [unroll]
                for (int octave = 0; octave < 4; ++octave)
                {
                    sum += FoamValueNoise(p) * weight;
                    totalWeight += weight;
                    p = float2(0.8 * p.x - 0.6 * p.y,
                               0.6 * p.x + 0.8 * p.y) * 2.03
                        + float2(17.13, 9.71);
                    weight *= 0.5;
                }
                return sum / totalWeight;
            }

            float FoamCoverage(float2 uv, float time)
            {
                float across = lerp(uv.x, uv.y, saturate(_FadeAxis));
                across = lerp(across, 1.0 - across, saturate(_FlipFade));

                // Keep Fade End greater than Fade Start in the material.
                float span = max(_FadeEnd - _FadeStart, 0.0001);
                float t = saturate((across - _FadeStart) / span);
                t = pow(t, max(_FadePower, 0.01));

                // Low-frequency noise perturbs the cutoff without changing noise scale
                float2 patchUV = uv * max(_PatchTiling.xy, float2(0.01, 0.01));
                float patch = FoamValueNoise(patchUV + _NoiseSeed + 19.37 + time * 0.2);
                float coverage = lerp(_SparseCoverage, _DenseCoverage, t);

                // Preserve the requested coverage at both ends of the gradient.
                coverage += (patch * 2.0 - 1.0) * _DensityBreakup
                          * (4.0 * t * (1.0 - t));
                return saturate(coverage);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float time = _Time.y * _TimeScale;
                
                // 1. Calculate domain distortion (warping the UVs before noise generation)
                float2 distortUV = IN.uv * max(_PatchTiling.xy, float2(0.01, 0.01)) - time * 0.5;
                float2 distortion = float2(
                    FoamValueNoise(distortUV + 15.2),
                    FoamValueNoise(distortUV + 42.8)
                ) * 2.0 - 1.0;

                // 2. Setup base coordinates with tiling, flow, and distortion
                float2 tiling = max(_GrainTiling.xy, float2(1, 1));
                float2 p = IN.uv * tiling + float2(37.17, 91.73) + _NoiseSeed;
                p += _FlowDirection.xy * time * tiling; 
                p += distortion * _DistortionAmount * tiling; 

                // 3. Generate noises
                float fbm = FoamFBM(p);
                float perlin = FoamPerlin(p);
                
                // Secondary FBM that pans slightly differently
                float fbm2 = FoamFBM(p * 0.75 - _FlowDirection.xy * time * tiling * 0.5);
                
                // Multiply Perlin with the secondary FBM
                float perlinFBM = perlin * fbm2 * 1.5; 
                
                // Mix standard FBM and the FBM-multiplied Perlin
                float noise = lerp(fbm, perlinFBM, saturate(_PerlinMix));

                // Spread the useful cutoff range across more of the gradient.
                noise = saturate((noise - 0.5) * 1.5 + 0.5);
                float rank = lerp(0.0001, 0.9999, noise);

                // Continuous UVs: no square-cell quantization of the gradient.
                float coverage = FoamCoverage(IN.uv, time);
                
                // Calculate soft alpha
                float alpha = smoothstep(0.0, _EdgeSoftness, coverage - rank) * saturate(_FoamColor.a);

                // Keep the original soft color variation
                // Keep the original soft color variation
                float2 colorUV = IN.uv * max(_PatchTiling.xy, float2(0.01, 0.01));
                float shade = FoamValueNoise(
                    colorUV + _NoiseSeed + 73.19 + time * 0.1
                );

                float3 color = lerp(
                    _FoamColor.rgb,
                    _ShadeColor.rgb,
                    shade * saturate(_ColorVariation)
                );

                // Receive main-light shadows
                float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);                
                Light mainLight = GetMainLight(shadowCoord);

                float shadowFactor = lerp(
                    1.0,
                    mainLight.shadowAttenuation,
                    saturate(_ReceiveShadowStrength)
                );

                color *= shadowFactor;

                return half4(color, alpha);
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

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float _ShadowCutoff;
            float _FadeAxis;
            float _FlipFade;
            float _FadeStart;
            float _FadeEnd;
            float _FadePower;
            float _SparseCoverage;
            float _DenseCoverage;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings ShadowVert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = IN.uv;
                return OUT;
            }

            half4 ShadowFrag(Varyings IN) : SV_Target
            {
                float across = lerp(IN.uv.x, IN.uv.y, saturate(_FadeAxis));
                across = lerp(across, 1.0 - across, saturate(_FlipFade));

                float span = max(_FadeEnd - _FadeStart, 0.0001);
                float t = saturate((across - _FadeStart) / span);
                t = pow(t, max(_FadePower, 0.01));

                float coverage = lerp(_SparseCoverage, _DenseCoverage, t);

                clip(coverage - _ShadowCutoff);

                return 0;
            }
            ENDHLSL
        }

    }
    FallBack Off
}



