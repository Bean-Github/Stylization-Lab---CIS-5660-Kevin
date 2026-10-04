Shader "Custom/ColoredVolumetricBox"
{
    Properties
    {
        // New: Color Property
        _Color ("Volume Color", Color) = (0, 0, 0, 1)
        _Density ("Density", Range(0, 100)) = 1.0
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline" = "UniversalPipeline" }
        
        Blend SrcAlpha OneMinusSrcAlpha 
        ZWrite Off 
        Cull Off 

        Pass
        {
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
                float4 positionCS : SV_POSITION;
                float3 positionOS : TEXCOORD0;
                float3 cameraPosOS : TEXCOORD1;
            };

            // Declare the variables
            float _Density;
            float4 _Color;

            Varyings vert (Attributes input)
            {
                Varyings output;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexInput.positionCS;
                output.positionOS = input.positionOS.xyz;

                float3 worldCameraPos = GetCameraPositionWS();
                output.cameraPosOS = TransformWorldToObject(worldCameraPos);

                return output;
            }

            float2 RayBoxIntersection(float3 rayOrigin, float3 rayDir, float3 boxMin, float3 boxMax)
            {
                float3 t0 = (boxMin - rayOrigin) / rayDir;
                float3 t1 = (boxMax - rayOrigin) / rayDir;
                float3 tmin = min(t0, t1);
                float3 tmax = max(t0, t1);
                float dstA = max(max(tmin.x, tmin.y), tmin.z);
                float dstB = min(min(tmax.x, tmax.y), tmax.z);
                return float2(dstA, dstB);
            }

            half4 frag (Varyings input) : SV_Target
            {
                float3 rayOrigin = input.cameraPosOS;
                float3 currentPixelPos = input.positionOS;
                float3 rayDir = normalize(currentPixelPos - rayOrigin);

                float3 boxMin = float3(-0.5, -0.5, -0.5);
                float3 boxMax = float3( 0.5,  0.5,  0.5);

                float2 intersection = RayBoxIntersection(rayOrigin, rayDir, boxMin, boxMax);
                
                float dstToBox = intersection.x;     
                float dstInsideBox = intersection.y; 

                // 1. INSIDE CHECK
                // If we are inside, return the Solid Color (Alpha 1)
                if (dstToBox < 0)
                {
                    return half4(_Color.rgb, 1);
                }

                // 2. VOLUME CALCULATION
                float dstTravelled = max(0, dstInsideBox - max(0, dstToBox));
                
                // Beer's Law for opacity
                float alpha = 1.0 - exp(-dstTravelled * _Density);

                // Return the chosen color with the calculated transparency
                return half4(_Color.rgb, alpha);
            }
            ENDHLSL
        }
    }
}