Shader "Custom/Water/Handwritten SSPR Water"
{
    Properties
    {
        // Original Shader Graph reference names are intentionally retained.
        // This lets existing materials keep their serialized property values.
        [Header(Water Colors)]
        Color_d925d3df582c44fb8fb4a7e86c5840e4("Shallow Color", Color) = (1, 1, 1, 0)
        Color_785d28f280074f10b0a03ab445e73eb8("Deep Color", Color) = (1, 1, 1, 0)
        _Posterize_Color("Posterize Color", Color) = (1, 1, 1, 0)
        _Posterize_Depth("Posterize Depth", Float) = 3

        [Header(Moving Normals)]
        [NoScaleOffset] Texture2D_b48b460153d34709884b6438bc6a151e("Normal Map", 2D) = "white" {}
        Vector4_0531145fc8bd4885a11bbfd5e06d8bde("UV1", Vector) = (6, 6, 0.5, 0.5)
        Vector4_30ff1b7c168246afafa779c6e55a1329("UV2", Vector) = (5, 5, 0, 0)
        Vector2_1b3bf3e86673452d81551df6f152c93e("Water Speed 1", Vector) = (0, 0, 0, 0)
        Vector2_fd67f1a4adff4db694b79e9cecae58f7("Water Speed 2", Vector) = (0, 0, 0, 0)
        Vector1_e2719c30786a4d4b804af8152444e446("Water Lerp", Range(0, 1)) = 0
        Vector1_2d7e3b4bd51c4910bf99fc7c167bc81b("Normal Strength", Float) = 0

        [Header(Refraction and Depth)]
        Vector1_1d85cf92e649419d9e2d1a0471f15134("Refraction", Float) = 0
        Vector1_4404b753c5fd4ca894e8635bff65f1dc("Depth", Float) = 0
        Vector1_9f41615fbe6f47388e5b8b045a045e31("Depth Fade", Float) = 0

        [Header(SSPR Reflection)]
        Vector1_8d990c6cef894c63b678f21eaddce9a4("Reflection Refraction", Float) = 0
        _Reflection_Fresnel_Power("Reflection Fresnel Power", Float) = 1.5
        _Reflection_Strength("Reflection Strength", Float) = 0.8

        [Header(Foam)]
        Vector1_a47f0c5c6ecf4348843d0e0c51ff2354("Foam", Float) = 0
        [NoScaleOffset] Texture2D_908207b6acde40cab3f667a34eeb0e92("Foam Texture", 2D) = "white" {}
        Vector1_f43f3972eb7941169f3013ad2ece79a8("Foam Scale", Float) = 1
        Color_2e1b98459f464ea7b1383c9594fd91d0("Foam Color", Color) = (1, 1, 1, 0)

        [Header(Waves and Ripples)]
        Vector1_6823ce837c7b4e3ba7b8e737fb6cd88d("Wave", Float) = 0
        [NoScaleOffset] _RippleTex("RippleTex", 2D) = "white" {}
        Vector1_2ba5a5c1bbba4b5b9c9aff9f70921a70("Ripple Strength", Float) = 1
        Vector1_4e38f3f045584407ae90461eb6101756("Ripple Refraction", Float) = 1
        _RippleCameraSize("RippleCameraSize", Float) = 0
        _RippleCameraPos("RippleCameraPos", Vector) = (0, 0, 0, 0)

        [Header(Fog)]
        [ToggleUI] _Use_Fog("Use Fog", Float) = 0

        // The original generated shader declares these properties but the
        // visible forward color graph does not use them. Kept for migration.
        [HideInInspector] Vector1_b4651e1c4a334bef8c36a54b0b6c423c("Smoothness", Range(0, 1)) = 0
        [HideInInspector] Vector1_093ef56d25ee49c1b50e0a3920b868f6("Metallic", Range(0, 1)) = 0
        [HideInInspector] Vector1_cb57562c85b847b0b3fc69d44ea9d8f7("Water Noise", Float) = 1
        [HideInInspector] Vector1_f8914effb3024a26994c7d3939d6cc23("Water Noise Size", Float) = 500
        [HideInInspector] Vector1_20df93eada1f4070943c50f03f150e81("Voronoi Speed", Float) = 1
        [HideInInspector] Texture2D_f774defee3a5406a9ceb622cbe7213c0("Ripple RT", 2D) = "white" {}
        // Unity/Shader Graph generated bookkeeping (migration only).
        [HideInInspector] _QueueOffset("_QueueOffset", Float) = 0
        [HideInInspector] _QueueControl("_QueueControl", Float) = -1
        [HideInInspector][NoScaleOffset] unity_Lightmaps("unity_Lightmaps", 2DArray) = "" {}
        [HideInInspector][NoScaleOffset] unity_LightmapsInd("unity_LightmapsInd", 2DArray) = "" {}
        [HideInInspector][NoScaleOffset] unity_ShadowMasks("unity_ShadowMasks", 2DArray) = "" {}
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "UniversalMaterialType" = "Unlit"
        }

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode" = "UniversalForward" }

            Cull Off
            ZWrite Off
            ZTest LEqual
            Blend SrcAlpha OneMinusSrcAlpha, One OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Hashes.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            // Existing project-dependent fog source used by your Shader Graph.
            // Remove this include AND the fog block below if you do not have it.
            #include_with_pragmas "Assets/Toon Shaders/Fog/GlobalFogData.hlsl"

            // Short aliases for the original long material property IDs.
            #define _ShallowColor        Color_d925d3df582c44fb8fb4a7e86c5840e4
            #define _DeepColor           Color_785d28f280074f10b0a03ab445e73eb8
            #define _NormalMap           Texture2D_b48b460153d34709884b6438bc6a151e
            #define _NormalUV1           Vector4_0531145fc8bd4885a11bbfd5e06d8bde
            #define _NormalUV2           Vector4_30ff1b7c168246afafa779c6e55a1329
            #define _NormalSpeed1        Vector2_1b3bf3e86673452d81551df6f152c93e
            #define _NormalSpeed2        Vector2_fd67f1a4adff4db694b79e9cecae58f7
            #define _NormalLerp          Vector1_e2719c30786a4d4b804af8152444e446
            #define _NormalStrength      Vector1_2d7e3b4bd51c4910bf99fc7c167bc81b
            #define _Refraction          Vector1_1d85cf92e649419d9e2d1a0471f15134
            #define _ReflectionDistort   Vector1_8d990c6cef894c63b678f21eaddce9a4
            #define _Depth               Vector1_4404b753c5fd4ca894e8635bff65f1dc
            #define _DepthFade           Vector1_9f41615fbe6f47388e5b8b045a045e31
            #define _FoamDistance        Vector1_a47f0c5c6ecf4348843d0e0c51ff2354
            #define _FoamTexture         Texture2D_908207b6acde40cab3f667a34eeb0e92
            #define _FoamScale           Vector1_f43f3972eb7941169f3013ad2ece79a8
            #define _FoamColor           Color_2e1b98459f464ea7b1383c9594fd91d0
            #define _Wave                Vector1_6823ce837c7b4e3ba7b8e737fb6cd88d
            #define _RippleStrength      Vector1_2ba5a5c1bbba4b5b9c9aff9f70921a70
            #define _RippleRefraction    Vector1_4e38f3f045584407ae90461eb6101756

            CBUFFER_START(UnityPerMaterial)
                float4 _ShallowColor;
                float4 _DeepColor;
                float4 _Posterize_Color;
                float _Posterize_Depth;
                float4 _NormalUV1;
                float4 _NormalUV2;
                float2 _NormalSpeed1;
                float2 _NormalSpeed2;
                float _NormalLerp;
                float _NormalStrength;
                float _Refraction;
                float _ReflectionDistort;
                float _Depth;
                float _DepthFade;
                float _Reflection_Fresnel_Power;
                float _Reflection_Strength;
                float _FoamDistance;
                float _FoamScale;
                float4 _FoamColor;
                float _Wave;
                float _RippleStrength;
                float _RippleRefraction;
                float _RippleCameraSize;
                float4 _RippleCameraPos;
                float _Use_Fog;
            CBUFFER_END

            TEXTURE2D(_NormalMap);
            SAMPLER(samplerTexture2D_b48b460153d34709884b6438bc6a151e);
            TEXTURE2D(_FoamTexture);
            SAMPLER(samplerTexture2D_908207b6acde40cab3f667a34eeb0e92);
            TEXTURE2D(_RippleTex);
            SAMPLER(sampler_RippleTex);

            // Provided externally by the existing Mobile SSPR / reflection renderer.
            // Its alpha channel encodes reflection validity / coverage.
            TEXTURE2D(_MobileSSPR_ColorRT);
            SAMPLER(sampler_MobileSSPR_ColorRT);

            struct Attributes
            {
                float3 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float2 uv         : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings Vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                // Graph: positionOS.y += sin(worldPos.x + time) * Wave.
                float3 originalWS = TransformObjectToWorld(v.positionOS);
                float3 positionOS = v.positionOS;
                positionOS.y += sin(originalWS.x + _TimeParameters.x) * _Wave;

                o.positionCS = TransformObjectToHClip(positionOS);
                o.positionWS = TransformObjectToWorld(positionOS);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.uv = v.uv;
                return o;
            }

            // Exact deterministic gradient-noise basis used by Shader Graph.
            float2 NoiseDirection(float2 p)
            {
                float h;
                Hash_Tchou_2_1_float(p, h);
                return normalize(float2(h - floor(h + 0.5), abs(h) - 0.5));
            }

            float GradientNoise(float2 uv)
            {
                float2 p = uv * 10.0;
                float2 cell = floor(p);
                float2 f = frac(p);
                float d00 = dot(NoiseDirection(cell), f);
                float d01 = dot(NoiseDirection(cell + float2(0, 1)), f - float2(0, 1));
                float d10 = dot(NoiseDirection(cell + float2(1, 0)), f - float2(1, 0));
                float d11 = dot(NoiseDirection(cell + float2(1, 1)), f - 1.0);
                f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
                return lerp(lerp(d00, d01, f.y), lerp(d10, d11, f.y), f.x) + 0.5;
            }

            float3 WorldPositionFromDepth(float2 uv, float rawDepth)
            {
                #if !UNITY_REVERSED_Z
                    rawDepth = lerp(UNITY_NEAR_CLIP_VALUE, 1.0, rawDepth);
                #endif
                return ComputeWorldSpacePosition(uv, rawDepth, UNITY_MATRIX_I_VP);
            }

            float EyeDepthAtUV(float2 uv)
            {
                float rawDepth = SampleSceneDepth(uv);
                if (unity_OrthoParams.w == 1.0)
                    return LinearEyeDepth(WorldPositionFromDepth(uv, rawDepth), UNITY_MATRIX_V);
                return LinearEyeDepth(rawDepth, _ZBufferParams);
            }

            // The original graph samples four neighboring height pixels at
            // a fixed 512x512 resolution. Share these samples between the
            // refraction and reflection ripple normals (instead of 8 reads).
            float2 RippleHeightSlope(float2 uv)
            {
                const float texel = 1.0 / 512.0;
                float xPlus  = SAMPLE_TEXTURE2D(_RippleTex, sampler_RippleTex, uv + float2(texel, 0)).r;
                float xMinus = SAMPLE_TEXTURE2D(_RippleTex, sampler_RippleTex, uv - float2(texel, 0)).r;
                float yPlus  = SAMPLE_TEXTURE2D(_RippleTex, sampler_RippleTex, uv + float2(0, texel)).r;
                float yMinus = SAMPLE_TEXTURE2D(_RippleTex, sampler_RippleTex, uv - float2(0, texel)).r;
                return float2(xPlus - xMinus, yPlus - yMinus) * 0.5;
            }

            float3 RippleSlopeNormal(float2 slope, float strength)
            {
                float stepSize = abs(strength) > 1e-5 ? strength / 512.0 : 1e-7;
                float3 tx = float3(stepSize, 0, slope.x);
                float3 ty = float3(0, stepSize, slope.y);
                return normalize(cross(tx, ty));
            }

            // The world-positioned ripple RT covers the square centered on
            // _RippleCameraPos, with half-extent _RippleCameraSize in X and Z.
            float2 RippleUV(float3 worldPos)
            {
                return (worldPos.xz - _RippleCameraPos.xz) /
                       max(2.0 * abs(_RippleCameraSize), 1e-5) + 0.5;
            }

            float RippleHeight(float2 uv)
            {
                if (_RippleCameraSize <= 0.0 ||
                    uv.x <= 0.0 || uv.x >= 1.0 ||
                    uv.y <= 0.0 || uv.y >= 1.0)
                    return 0.0;
                return SAMPLE_TEXTURE2D(_RippleTex, sampler_RippleTex, uv).r;
            }

            // Original refraction subgraph: screen-space gradient-noise shift,
            // rejected when the offset would sample geometry above water.
            float2 RefractedScreenUV(float2 screenUV, float2 meshUV,
                                     float3 positionWS)
            {
                float2 noiseUV = meshUV * 10.0 + _TimeParameters.x * 0.3;
                float noise = GradientNoise(noiseUV) * 2.0 - 1.0;
                float2 proposedUV = screenUV + noise * 0.003;

                float rawDepth = SampleSceneDepth(proposedUV);
                float3 behindWS = WorldPositionFromDepth(proposedUV, rawDepth);
                return positionWS.y >= behindWS.y ? proposedUV : screenUV;
            }

            half4 Frag(Varyings i, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                float3 normalWS = normalize(i.normalWS);
                float3 viewWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);
                float waterEyeDepth = -TransformWorldToView(i.positionWS).z;

                // 1. Refraction subgraph selects the base screen UV.
                float2 baseUV = RefractedScreenUV(screenUV, i.uv, i.positionWS);

                // 2. Two independently scrolling normal-map samples.
                float2 uv1 = i.uv * _NormalUV1.xy + _NormalUV1.zw +
                             _TimeParameters.x * _NormalSpeed1;
                float2 uv2 = i.uv * _NormalUV2.xy + _NormalUV2.zw +
                             _TimeParameters.x * _NormalSpeed2;
                float3 n1 = UnpackNormal(SAMPLE_TEXTURE2D(
                    _NormalMap, samplerTexture2D_b48b460153d34709884b6438bc6a151e, uv1));
                float3 n2 = UnpackNormal(SAMPLE_TEXTURE2D(
                    _NormalMap, samplerTexture2D_b48b460153d34709884b6438bc6a151e, uv2));
                float3 animatedNormal = lerp(n1, n2, _NormalLerp);
                animatedNormal = float3(animatedNormal.xy * _NormalStrength,
                    lerp(1.0, animatedNormal.z, saturate(_NormalStrength)));

                // 3. Height-map ripple normals take over inside the ripple RT.
                float2 rippleUV = RippleUV(i.positionWS);
                float ripple = RippleHeight(rippleUV);
                float3 refractNormal = animatedNormal;
                float3 reflectNormal = animatedNormal;
                if (ripple > 0.0)
                {
                    float2 slope = RippleHeightSlope(rippleUV);
                    refractNormal = lerp(animatedNormal,
                        RippleSlopeNormal(slope, _RippleRefraction), ripple);
                    reflectNormal = lerp(animatedNormal,
                        RippleSlopeNormal(slope, _RippleStrength), ripple);
                }

                // 4. Distortion is disabled at depth discontinuities.
                float2 warpedUV = baseUV + refractNormal.xy * _Refraction;
                float warpedEyeDepth = EyeDepthAtUV(warpedUV);
                float validDistortion = step(waterEyeDepth, warpedEyeDepth);
                float2 sceneUV = baseUV + refractNormal.xy * (_Refraction * validDistortion);

                float3 sceneColor = SampleSceneColor(sceneUV);
                float sceneEyeDepth = EyeDepthAtUV(sceneUV);
                float thickness = sceneEyeDepth - waterEyeDepth;

                // 5. Shallow = tinted scene color; deep = uniform deep color.
                float3 shallow = _ShallowColor.rgb * sceneColor;
                float depthFactor = saturate(thickness / max(_Depth, 1e-5));
                float3 water = lerp(shallow, _DeepColor.rgb, 1.0f - depthFactor);

                // 6. External _MobileSSPR_ColorRT screen-space planar reflections.
                float2 reflectionUV = baseUV + reflectNormal.xy * _ReflectionDistort;
                float4 reflection = SAMPLE_TEXTURE2D(
                    _MobileSSPR_ColorRT, sampler_MobileSSPR_ColorRT, reflectionUV);
                float fresnel = pow(1.0 - saturate(dot(normalWS, viewWS)),
                                    max(_Reflection_Fresnel_Power, 1e-5));
                float reflectAmount = saturate(reflection.a * _Reflection_Strength * fresnel);
                water = lerp(water, reflection.rgb, reflectAmount);

                // 7. Shallow posterized shoreline color, using world-space
                //    depth along the geometric surface normal.
                float3 belowWaterWS = WorldPositionFromDepth(
                    baseUV, SampleSceneDepth(baseUV));
                float depthAlongNormal = dot(i.positionWS - belowWaterWS, normalWS);
                if (depthAlongNormal < _Posterize_Depth)
                {
                    float band = saturate(depthAlongNormal / max(_Posterize_Depth, 1e-5));
                    band = floor(band * 4.0) * 0.25;
                    water = lerp(_Posterize_Color.rgb, water, band);
                }

                // 8. Ripple foam + shoreline depth foam.
                float rippleFoam = step(0.16, saturate(ripple));
                float edgeFoam = 1.0 - saturate(thickness / max(_FoamDistance, 1e-5));
                float3 shorePattern = SAMPLE_TEXTURE2D(
                    _FoamTexture, samplerTexture2D_908207b6acde40cab3f667a34eeb0e92,
                    i.uv * _FoamScale).rgb;
                float3 foamBlend = rippleFoam + edgeFoam * (shorePattern + 0.2);
                water = lerp(water, _FoamColor.rgb, foamBlend);

                // 9. Original double-sided branch: back faces are only the
                //    shallow tinted scene, without reflection/deep/foam.
                if (!IS_FRONT_VFACE(face, true, false))
                    water = shallow;

                // 10. Optional project-specific depth fog.
                if (_Use_Fog > 0.5)
                {
                    float minDistance, maxDistance;
                    float4 fogColor;
                    float skyFactor = saturate(viewWS.y * 0.5 + 0.5);
                    GetGlobalFogValues_float(skyFactor, minDistance, maxDistance, fogColor);
                    float fog = saturate((EyeDepthAtUV(screenUV) - minDistance) /
                                         max(maxDistance - minDistance, 1e-5));
                    water = lerp(water, fogColor.rgb, fog);
                }

                // The Shader Graph's Alpha output is entirely depth-driven.
                float alpha = saturate((EyeDepthAtUV(screenUV) - waterEyeDepth) /
                                       max(_DepthFade, 1e-5));
                return half4(water, alpha);
            }
            ENDHLSL
        }
    }

    FallBack Off
}
