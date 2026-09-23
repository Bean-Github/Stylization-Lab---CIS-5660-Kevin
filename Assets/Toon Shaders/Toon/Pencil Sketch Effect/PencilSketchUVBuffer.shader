Shader "Hidden/PencilSketch/UV"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "UVPass"

            ZTest LEqual  // Only draw if the object is closer to the camera than what's already there
            ZWrite On     // Write to the depth buffer so objects behind this one get blocked

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // REQUIRED: Core URP functions and macros
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

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

            Varyings vert(Attributes v)
            {
                Varyings o;
                // Now TransformObjectToHClip will correctly compile
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = v.uv;
                return o;
            }

            float4 frag(Varyings i) : SV_Target
            {
                // Store UV in RG channels. Output 1 for Alpha to distinguish objects from the background.
                return float4(i.uv, 0.0, 1.0); 
            }

            ENDHLSL
        }
    }
}