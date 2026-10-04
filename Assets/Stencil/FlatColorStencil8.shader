Shader "Stylized/FrontCardBackground"
{
    Properties
    {
        _BaseColor ("Background Color", Color) = (1, 1, 1, 1)
    }
    
    SubShader
    {
        // Renders just before standard geometry so the inside objects draw after it
        Tags 
        { 
            "RenderType" = "Opaque" 
            "RenderPipeline" = "UniversalPipeline" 
            "Queue" = "Geometry-1" 
        }
        
        // 1. DON'T WRITE DEPTH: This is the magic that lets objects behind it show through
        ZWrite Off
        
        // 2. ONLY RENDER FRONT: Turns off when you walk behind it
        Cull Back

        // 3. STENCIL: Write the portal hole
        Stencil
        {
            Ref 8
            Comp Always
            Pass Replace
        }

        Pass
        {
            Name "Unlit"
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
            CBUFFER_END

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                // Now we actually output the color to the screen!
                return _BaseColor;
            }
            ENDHLSL
        }
    }
}