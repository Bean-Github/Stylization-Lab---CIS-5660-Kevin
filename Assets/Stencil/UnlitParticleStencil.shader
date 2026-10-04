Shader "Universal Render Pipeline/Particles/Unlit Stencil"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (1,1,1,1)

        _EmissionMap("Emission Map", 2D) = "white" {}
        [HDR] _EmissionColor("Emission Color", Color) = (0,0,0,0)

        [IntRange] _StencilRef("Stencil Ref", Range(0, 255)) = 8
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "IgnoreProjector" = "True"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "UnlitStencil"

            Tags
            {
                "LightMode" = "UniversalForward"
            }

            Stencil
            {
                Ref [_StencilRef]
                Comp Equal
                Pass Keep
            }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            ZTest LEqual
            Cull Off

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_instancing
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"


            // ========================================================
            // TEXTURES
            // ========================================================

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_EmissionMap);
            SAMPLER(sampler_EmissionMap);


            // ========================================================
            // MATERIAL PROPERTIES
            // ========================================================

            CBUFFER_START(UnityPerMaterial)

                float4 _BaseMap_ST;
                half4 _BaseColor;

                float4 _EmissionMap_ST;
                half4 _EmissionColor;

                float _StencilRef;

            CBUFFER_END


            // ========================================================
            // VERTEX INPUT
            // ========================================================

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                half4 color       : COLOR;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };


            // ========================================================
            // VERTEX -> FRAGMENT
            // ========================================================

            struct Varyings
            {
                float4 positionCS : SV_POSITION;

                float2 uv         : TEXCOORD0;
                float2 emissionUV : TEXCOORD1;

                half4 color       : COLOR;

                float fogFactor   : TEXCOORD2;

                UNITY_VERTEX_OUTPUT_STEREO
            };


            // ========================================================
            // VERTEX
            // ========================================================

            Varyings vert(Attributes input)
            {
                Varyings output;

                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                VertexPositionInputs positionInputs =
                    GetVertexPositionInputs(input.positionOS.xyz);

                output.positionCS =
                    positionInputs.positionCS;


                output.uv =
                    TRANSFORM_TEX(
                        input.uv,
                        _BaseMap);


                output.emissionUV =
                    TRANSFORM_TEX(
                        input.uv,
                        _EmissionMap);


                // Particle System vertex color:
                // Start Color
                // Color Over Lifetime
                // etc.
                output.color =
                    input.color * _BaseColor;


                output.fogFactor =
                    ComputeFogFactor(
                        positionInputs.positionCS.z);


                return output;
            }


            // ========================================================
            // FRAGMENT
            // ========================================================

            half4 frag(Varyings input) : SV_Target
            {
                // ----------------------------------------------------
                // BASE PARTICLE COLOR
                // ----------------------------------------------------

                half4 baseSample =
                    SAMPLE_TEXTURE2D(
                        _BaseMap,
                        sampler_BaseMap,
                        input.uv);


                half4 color =
                    baseSample * input.color;


                // ----------------------------------------------------
                // EMISSION
                // ----------------------------------------------------

                half3 emissionSample =
                    SAMPLE_TEXTURE2D(
                        _EmissionMap,
                        sampler_EmissionMap,
                        input.emissionUV).rgb;


                half3 emission =
                    emissionSample *
                    _EmissionColor.rgb;


                // Add emission to particle RGB.
                color.rgb += emission;


                // ----------------------------------------------------
                // FOG
                // ----------------------------------------------------

                color.rgb =
                    MixFog(
                        color.rgb,
                        input.fogFactor);


                return color;
            }

            ENDHLSL
        }
    }

    FallBack Off
}