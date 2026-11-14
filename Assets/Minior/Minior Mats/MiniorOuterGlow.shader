Shader "Custom/MiniorOuterGlow"
{
    Properties
    {
        [Enum(UnityEngine.Rendering.CullMode)] _Cull("Face Rendering", Float) = 2

        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [HDR] _Glow("Glow", Color) = (1, 1, 1, 1)

        _Power("Fresnel Power", Range(0, 15)) = 0.5

        [IntRange] _UseStencil ("Stencil Reference", Range(0, 10)) = 0
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
            Cull [_Cull]
            Blend SrcAlpha OneMinusSrcAlpha

            Stencil
            {
                Ref [_UseStencil]
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
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                float4 _Glow;
                float _Power;
            CBUFFER_END

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


            float SceneEyeDepth(float rawDepth)
            {
                if (unity_OrthoParams.w > 0.5)
                {
                    #if UNITY_REVERSED_Z
                    rawDepth = 1.0 - rawDepth;
                    #endif
                    return lerp(_ProjectionParams.y, _ProjectionParams.z, rawDepth);
                }
                return LinearEyeDepth(rawDepth, _ZBufferParams);
            }

            half4 Frag(Varyings IN) : SV_Target
            {
                float2 screenUV = GetNormalizedScreenSpaceUV(IN.positionCS);
                float rawDepth = SampleSceneDepth(screenUV);
                float sceneEyeDepth = SceneEyeDepth(rawDepth);
                float fragmentEyeDepth = -TransformWorldToView(IN.positionWS).z;

                // The depth buffer's clear value represents the far plane.
                #if UNITY_REVERSED_Z
                    bool hasSceneDepth = rawDepth > 1e-6;
                #else
                    bool hasSceneDepth = rawDepth < (1.0 - 1e-6);
                #endif

                if (hasSceneDepth && sceneEyeDepth > fragmentEyeDepth + 1e-3)
                {
                    return half4(SampleSceneColor(screenUV).rgb, 1.0);
                }

                float3 N = normalize(IN.normalWS);
                float3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));
                float NdotV = saturate(dot(N, V));
                float alpha = pow(NdotV, _Power);

                return half4(_Glow.rgb, alpha);
            }
            ENDHLSL
        }
    }
}
