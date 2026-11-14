Shader "Custom/Sprite Unlit Transparent Stencil"
{
    Properties
    {
        [NoScaleOffset] _MainTex ("Main Texture", 2D) = "white" {}
        [HDR] _Color ("Color", Color) = (1, 1, 1, 1)
        [IntRange] _UseStencil ("Stencil Reference", Range(0, 10)) = 0
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
            Blend SrcAlpha OneMinusSrcAlpha, One OneMinusSrcAlpha
            ZTest LEqual
            ZWrite On

            Stencil
            {
                Ref [_UseStencil]
                Comp Equal
                Pass Keep
            }

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _Color;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv          : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float fogFactor   : TEXCOORD1;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;

                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                output.fogFactor = ComputeFogFactor(output.positionCS.z);

                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                color *= _Color;
                color.rgb = MixFog(color.rgb, input.fogFactor);
                return color;
            }
            ENDHLSL
        }
    }
}