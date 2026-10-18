// Single-color HDR glow for frozen character poses. Universal Render Pipeline.
// _TrailFade is set per snapshot by CharacterAfterimageTrail via property blocks.
// Defaults to additive rendering; it needs HDR + Bloom for a visible glow halo.
Shader "Custom/Mewtwo/Character Trail Glow URP"
{
    Properties
    {
        [HDR] _BaseColor("Trail Color (HDR RGBA)", Color) = (0.1, 2, 4, 1)
        _Brightness("Brightness", Float) = 1
        _Opacity("Opacity", Range(0, 1)) = 0.7
        _Fill("Body Fill", Range(0, 1)) = 0.15
        _RimStrength("Rim Strength", Range(0, 3)) = 1
        _RimPower("Rim Power", Range(0.1, 8)) = 2
        [HideInInspector] _TrailFade("Snapshot Fade", Float) = 1

        [Header(Optional Card Stencil)]
        _StencilRef("Stencil Reference", Range(0, 255)) = 8
        _StencilReadMask("Stencil Read Mask", Range(0, 255)) = 8
        [Enum(UnityEngine.Rendering.CompareFunction)] _StencilComp("Stencil Comparison", Float) = 8
        // Always (8) = no stencil restriction. Equal (3), Ref/ReadMask 8 = inside card.
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "UniversalMaterialType" = "Unlit"
            "Queue" = "Transparent"
        }
        Pass
        {
            Name "TrailGlow"
            Tags { "LightMode" = "UniversalForwardOnly" }
            // Additive RGB glow, preserving the existing render target alpha.
            Blend SrcAlpha One, Zero One
            ZWrite Off
            ZTest LEqual
            Cull Back
            Stencil
            {
                Ref [_StencilRef]
                ReadMask [_StencilReadMask]
                WriteMask 0
                Comp [_StencilComp]
                Pass Keep
            }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex TrailVertex
            #pragma fragment TrailFragment
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float _Brightness;
                float _Opacity;
                float _Fill;
                float _RimStrength;
                float _RimPower;
                float _TrailFade;
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
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings TrailVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.positionWS = TransformObjectToWorld(input.positionOS);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return output;
            }

            half4 TrailFragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float3 normalWS = normalize(input.normalWS);
                float3 viewWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                float rim = pow(1.0 - saturate(dot(normalWS, viewWS)), max(_RimPower, 0.1));
                half3 color = _BaseColor.rgb * max(_Brightness, 0.0)
                            * (saturate(_Fill) + rim * max(_RimStrength, 0.0));
                half alpha = saturate(_BaseColor.a) * saturate(_Opacity) * saturate(_TrailFade);
                float eyeDepth = -TransformWorldToView(input.positionWS).z;
                float fog = ComputeFogFactorZ0ToFar(max(eyeDepth - _ProjectionParams.y, 0.0));
                // Additive effects fade to black in fog, not to the scene fog color.
                color = MixFogColor(color, half3(0, 0, 0), fog);
                return half4(color, alpha);
            }
            ENDHLSL
        }
    }
    Fallback Off
}
