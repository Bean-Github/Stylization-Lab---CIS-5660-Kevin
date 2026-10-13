Shader "Custom/StylizedTranslucentSlime"
{
    Properties
    {
        [Header(Rendering)]
        [Enum(UnityEngine.Rendering.CullMode)] _Cull("Face Rendering", Float) = 2


        [Header(Transmission)]
        [HDR] _BodyColor("Scattered Body Color", Color) = (0.12, 0.8, 0.24, 1)
        _Absorption("Beer Lambert Absorption (RGB)", Vector) = (2.5, 0.25, 1.8, 0)
        _Thickness("Approximate Blob Thickness", Range(0.01, 5)) = 1.5
        _Refraction("Refraction Distortion", Range(0, 0.1)) = 0.015

        [Header(Toon Lighting)]
        [HDR] _ShadowColor("Shadow Band", Color) = (0.2, 0.35, 0.28, 1)
        [HDR] _MidColor("Midtone Band", Color) = (0.65, 0.95, 0.65, 1)
        [HDR] _LitColor("Light Band", Color) = (1.15, 1.1, 0.8, 1)
        _ShadowEdge("Shadow Band Threshold", Range(0, 1)) = 0.25
        _LightEdge("Light Band Threshold", Range(0, 1)) = 0.7
        _BandSoftness("Band Softness", Range(0.001, 0.25)) = 0.035
        
        _ToonWrapPower("Toon Wrap Power", Range(0, 10)) = 2
        _ToonWrapAmount("Toon Wrap Amount", Range(0, 1)) = 0.2

        [Header(Gloss)]
        [Normal] _NormalMap("Scrolling Normal Map", 2D) = "bump" {}
        _NormalStrength("Normal Strength", Range(0, 2)) = 0.5
        _NormalTiling("Normal Tiling", Float) = 3
        _FlowA("Normal Scroll A (XY)", Vector) = (0.06, 0.02, 0, 0)
        _FlowB("Normal Scroll B (XY)", Vector) = (-0.04, 0.05, 0, 0)
        [HDR] _SpecColor("Specular HDR Color", Color) = (3, 3, 2, 1)
        _SpecPower("Specular Tightness", Range(4, 256)) = 72
        _SpecThreshold("Toon Specular Threshold", Range(0, 1)) = 0.45
        _SpecSoftness("Toon Specular Softness", Range(0.001, 0.3)) = 0.08
        _SpecDirection("Specular Direction", Vector) = (0, 1, 0)

        [Header(Rim and Glow)]
        [HDR] _RimColor("Fresnel Rim HDR", Color) = (0.05, 1.4, 0.35, 1)
        _FresnelPower("Fresnel Power", Range(0.5, 10)) = 3
        _RimStrength("Rim Emission Strength", Range(0, 5)) = 0.7
        [HDR] _EmissionColor("Interior Emission HDR", Color) = (0, 0, 0, 1)
        _EmissionStrength("Emission Strength", Range(0, 10)) = 0

        [Header(Back Lighting)]
        [HDR] _ScatterLightColor("Backlit Scatter HDR", Color) = (0.5, 1.5, 0.35, 1)
        _BackScatterStrength("Backlit Strength", Range(0, 5)) = 0.5
        _BackScatterPower("Backlit Directionality", Range(1, 8)) = 2

        [Header(Optional Environment Reflection)]
        _ReflectionCube("Environment Cubemap", Cube) = "" {}
        _ReflectionStrength("Fresnel Reflection Strength", Range(0, 1)) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Transparent"
            "Queue"="Transparent"
        }

        Pass
        {
            Name "SlimeForward"
            Tags { "LightMode"="UniversalForward" }

            Cull [_Cull]
            ZWrite Off
            ZTest LEqual
            // This shader explicitly composites SampleSceneColor in the fragment.
            // Do not alpha-blend that scene color over the background again.
            Blend One Zero
            ColorMask RGB

            Stencil
            {
                Ref 8
                Comp Equal
                Pass Keep
            }


            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);
            TEXTURECUBE(_ReflectionCube);
            SAMPLER(sampler_ReflectionCube);

            CBUFFER_START(UnityPerMaterial)
                float4 _BodyColor;
                float4 _Absorption;
                float _Thickness;
                float _Refraction;

                float4 _ShadowColor;
                float4 _MidColor;
                float4 _LitColor;
                float _ShadowEdge;
                float _LightEdge;
                float _BandSoftness;
                float _ToonWrapPower;
                float _ToonWrapAmount;

                float _NormalStrength;
                float _NormalTiling;
                float4 _FlowA;
                float4 _FlowB;
                float4 _SpecColor;
                float _SpecPower;
                float _SpecThreshold;
                float _SpecSoftness;
                float3 _SpecDirection;

                float4 _RimColor;
                float _FresnelPower;
                float _RimStrength;
                float4 _EmissionColor;
                float _EmissionStrength;

                float4 _ScatterLightColor;
                float _BackScatterStrength;
                float _BackScatterPower;
                float _ReflectionStrength;
            CBUFFER_END

            struct Attributes
            {
                float3 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float4 tangentWS : TEXCOORD2;
                float2 uv : TEXCOORD3;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings Vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                VertexPositionInputs vp = GetVertexPositionInputs(IN.positionOS);
                OUT.positionWS = vp.positionWS;
                OUT.positionCS = vp.positionCS;
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.tangentWS = float4(
                    TransformObjectToWorldDir(IN.tangentOS.xyz),
                    IN.tangentOS.w * GetOddNegativeScale());
                OUT.uv = IN.uv;
                return OUT;
            }

            float3 ScrollingNormalWS(Varyings IN, float3 geomN)
            {
                float3 T = normalize(IN.tangentWS.xyz);
                T = normalize(T - geomN * dot(geomN, T));
                float3 B = normalize(cross(geomN, T) * IN.tangentWS.w);

                float2 uv1 = IN.uv * _NormalTiling + _Time.y * _FlowA.xy;
                float2 uv2 = IN.uv * _NormalTiling * 1.37 + _Time.y * _FlowB.xy;
                float3 a = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv1));
                float3 b = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv2));
                float2 xy = (a.xy + b.xy) * _NormalStrength;
                float3 nTS = normalize(float3(xy, 1.0));
                return normalize(T * nTS.x + B * nTS.y + geomN * nTS.z);
            }

            float3 ToonLighting(float illumination)
            {
                float shadowToMid = smoothstep(
                    _ShadowEdge - _BandSoftness,
                    _ShadowEdge + _BandSoftness,
                    illumination);
                float midToLit = smoothstep(
                    _LightEdge - _BandSoftness,
                    _LightEdge + _BandSoftness,
                    illumination);
                float3 bands = lerp(_ShadowColor.rgb, _MidColor.rgb, shadowToMid);
                return lerp(bands, _LitColor.rgb, midToLit);
            }

            float SceneEyeDepth(float rawDepth)
            {
                // Support both perspective and orthographic cameras.
                if (unity_OrthoParams.w > 0.5)
                {
                    #if UNITY_REVERSED_Z
                    rawDepth = 1.0 - rawDepth;
                    #endif
                    return lerp(_ProjectionParams.y, _ProjectionParams.z, rawDepth);
                }
                return LinearEyeDepth(rawDepth, _ZBufferParams);
            }

            float3 Frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                float3 geomN = normalize(IN.normalWS);
                float3 N = ScrollingNormalWS(IN, geomN);
                float3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));

                float2 screenUV = GetNormalizedScreenSpaceUV(IN.positionCS);

                // Refract with the perturbed normal, relative to the geometric normal.
                float3 normalOffsetVS = TransformWorldToViewDir(N - geomN);
                float2 refractedUV = saturate(screenUV + normalOffsetVS.xy * _Refraction);

                // Reject refraction rays that sample an opaque foreground object.
                float frontEye = -TransformWorldToView(IN.positionWS).z;
                float warpedEye = SceneEyeDepth(SampleSceneDepth(refractedUV));
                if (warpedEye < frontEye)
                    refractedUV = screenUV;

                float3 background = SampleSceneColor(refractedUV).rgb;
                float opaqueEye = SceneEyeDepth(SampleSceneDepth(screenUV));
                float sceneGap = max(0.0, opaqueEye - frontEye); // difference between eye depth and frag depth

                // Cheap approximation for a roughly convex blob:
                // thick when looking straight into the surface, thin near its edge.
                // Scene depth only CLAMPS the approximation at opaque intersections.
                // For accurate arbitrary shapes, render slime backfaces to a depth RT.
                float facing = saturate(dot(geomN, V));
                float thickness = min(_Thickness * facing, sceneGap);

                // Beer-Lambert RGB transmission and stylized internal scattering.
                float3 T = exp(-max(_Absorption.rgb, 0.0) * thickness);
                float3 transmitted = background * T;

                Light mainLight = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                float3 L = normalize(mainLight.direction);
                float ndl = saturate(dot(N, L));
                
                float rimWrap = pow(1.0 - saturate(dot(N, V)), _ToonWrapPower) * _ToonWrapAmount;
                
                float illumination = (ndl + rimWrap) * mainLight.shadowAttenuation;

                float3 toon = ToonLighting(illumination);
                float3 body = transmitted + (1.0 - T) * _BodyColor.rgb * toon;

                // Backlit scattering
                float backlight = pow(saturate(dot(-geomN, L)), _BackScatterPower);
                float scatterOpacity = 1.0 - (T.r + T.g + T.b) / 3.0;  // how much light is getting through the blob
                float3 backscatter = _ScatterLightColor.rgb * _BackScatterStrength
                    * backlight * scatterOpacity * mainLight.color;

                // Toon-shaped Blinn-Phong gloss (surface reflection, independent of transmission).
                float3 H = normalize(_SpecDirection + V);
                float specRaw = pow(saturate(dot(N, H)), _SpecPower);
                float specMask = smoothstep(
                    _SpecThreshold - _SpecSoftness,
                    _SpecThreshold + _SpecSoftness,
                    specRaw) * mainLight.shadowAttenuation;
                float3 specular = _SpecColor.rgb * specMask * mainLight.color;

                // Grazing angle Fresnel layer and optional cubemap reflection.
                float fresnel = pow(1.0 - saturate(dot(N, V)), _FresnelPower);
                float3 R = reflect(-V, N);
                float3 environment = SAMPLE_TEXTURECUBE(
                    _ReflectionCube, sampler_ReflectionCube, R).rgb;
                body = lerp(body, environment, saturate(fresnel * _ReflectionStrength));

                float3 rimEmission = _RimColor.rgb * fresnel * _RimStrength;
                float3 glow = _EmissionColor.rgb * _EmissionStrength;

                // HDR values intentionally remain unclamped for Bloom/post-processing.
                return body + backscatter + specular + rimEmission + glow;
            }
            ENDHLSL
        }
    }
    Fallback Off
}
