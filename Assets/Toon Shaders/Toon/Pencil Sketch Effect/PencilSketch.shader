Shader "Hidden/PencilSketch/Composite"
{
    Properties
    {
        _Hatch0 ("Hatch Texture 0 (Light)", 2D) = "white" {}
        _Hatch1 ("Hatch Texture 1 (Dark)", 2D) = "white" {}
        _Tiling ("Hatch Tiling Scale", Range(0.1, 50.0)) = 5.0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "PencilComposite"

            ZWrite Off
            ZTest Always
            Cull Off

            HLSLPROGRAM
            // Use standard Blit Vertex Shader
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // REQUIRED: Include Blit.hlsl for Blitter.BlitTexture compatibility
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // Note: _BlitTexture and sampler_LinearClamp are automatically defined by Blit.hlsl

            TEXTURE2D(_UVTexture);
            SAMPLER(sampler_UVTexture);

            TEXTURE2D(_Hatch0);
            SAMPLER(sampler_Hatch0);

            TEXTURE2D(_Hatch1);
            SAMPLER(sampler_Hatch1);

            float _Tiling;

            float3 Hatching(float2 _uv, float _intensity)
            {
                float3 hatch0 = SAMPLE_TEXTURE2D(_Hatch0, sampler_Hatch0, _uv).rgb;
                float3 hatch1 = SAMPLE_TEXTURE2D(_Hatch1, sampler_Hatch1, _uv).rgb;

                float3 overbright = max(0, _intensity - 1.0);

                float3 weightsA = saturate((_intensity * 6.0) + float3(-0, -1, -2));
                float3 weightsB = saturate((_intensity * 6.0) + float3(-3, -4, -5));

                weightsA.xy -= weightsA.yz;
                weightsA.z -= weightsB.x;
                weightsB.xy -= weightsB.yz;

                hatch0 = hatch0 * weightsA;
                hatch1 = hatch1 * weightsB;

                float3 hatching = overbright + hatch0.r +
    	            hatch0.g + hatch0.b +
    	            hatch1.r + hatch1.g +
    	            hatch1.b;

                return hatching;
            }


            // Blit.hlsl provides the 'Varyings' struct
            float4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                // Use input.texcoord provided by the Blit vertex shader
                float2 uv = input.texcoord;

                // Sample the main camera color using _BlitTexture (set up by C# Blitter)
                float3 col = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;

                // Sample custom UV texture
                float4 uvData = SAMPLE_TEXTURE2D(_UVTexture, sampler_UVTexture, uv);
                float2 objUV = uvData.xy;
                
                float intensity = dot(col, float3(0.2326, 0.7152, 0.0722));

                float3 hatch = Hatching(objUV * _Tiling, intensity);

                //return uvData;

                return float4(hatch, 1.0);

                // float2 uv = input.texcoord;

                // // 1. Get the base texture color
                // float4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);

                // // 2. Get URP Main Light Data
                // Light mainLight = GetMainLight();
                // half3 lightColor = mainLight.color;
                // half3 lightDir = normalize(mainLight.direction);
                // half3 normal = normalize(input.normalWS);

                // // 3. Calculate classic diffuse (N dot L)
                // // Using saturate to prevent negative lighting on the dark side of the object
                // half NdotL = saturate(dot(normal, lightDir));
                // half3 diffuse = color.rgb * lightColor * NdotL;

                // // 4. Calculate Grayscale Intensity
                // half intensity = dot(diffuse, half3(0.2326, 0.7152, 0.0722));

                // // 5. Apply Hatching using object UVs
                // half3 finalHatch = Hatching(input.uv * _Tiling, intensity);

                // return float4(finalHatch, color.a);


                // float3 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
                // float3 diffuse = color.rgb * _LightColor0.rgb * dot(_WorldSpaceLightPos0, normalize(i.nrm));

                // fixed intensity = dot(diffuse, fixed3(0.2326, 0.7152, 0.0722));

                // color.rgb =  Hatching(i.uv * 8, intensity);

                // return color;
            }

            ENDHLSL
        }
    }
}




