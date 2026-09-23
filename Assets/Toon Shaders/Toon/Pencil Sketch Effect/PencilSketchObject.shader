Shader "Custom/URP_PencilSketch"
{
    Properties
    {
        _MainTex ("Base Texture", 2D) = "white" {}
        _Hatch0 ("Hatch Texture 0 (Light)", 2D) = "white" {}
        _Hatch1 ("Hatch Texture 1 (Dark)", 2D) = "white" {}
        _Tiling ("Hatch Tiling", Range(1, 20)) = 8.0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        // --------------------------------------------------
        // DEPTH ONLY PASS (For Shadows and Depth Outlines)
        // --------------------------------------------------
        Pass
        {
            Name "DepthOnly"
            Tags{"LightMode" = "DepthOnly"}

            ZWrite On
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS   : POSITION;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
            };

            Varyings DepthOnlyVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half4 DepthOnlyFragment(Varyings input) : SV_TARGET
            {
                return 0;
            }
            ENDHLSL
        }

        // --------------------------------------------------
        // DEPTH NORMALS PASS (For Normal-based Outlines)
        // --------------------------------------------------
        Pass
        {
            Name "DepthNormals"
            Tags{"LightMode" = "DepthNormals"}

            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float3 normalWS     : TEXCOORD0;
            };

            Varyings DepthNormalsVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return output;
            }

            half4 DepthNormalsFragment(Varyings input) : SV_TARGET
            {
                // Writes the normal to the screen so post-processing outlines can see it
                return half4(NormalizeNormalPerPixel(input.normalWS), 0.0);
            }
            ENDHLSL
        }
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // URP specific libraries
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // URP Texture declarations
            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            TEXTURE2D(_Hatch0);  SAMPLER(sampler_Hatch0);
            TEXTURE2D(_Hatch1);  SAMPLER(sampler_Hatch1);

            CBUFFER_START(UnityPerMaterial)
                float _Tiling;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
            };

            // Exactly your Hatching function, using URP texture sampling
            half3 Hatching(float2 _uv, half _intensity)
            {
                half3 hatch0 = SAMPLE_TEXTURE2D(_Hatch0, sampler_Hatch0, _uv).rgb;
                half3 hatch1 = SAMPLE_TEXTURE2D(_Hatch1, sampler_Hatch1, _uv).rgb;

                half3 overbright = max(0, _intensity - 1.0);

                half3 weightsA = saturate((_intensity * 6.0) + half3(0, -1, -2));
                half3 weightsB = saturate((_intensity * 6.0) + half3(-3, -4, -5));

                weightsA.xy -= weightsA.yz;
                weightsA.z -= weightsB.x;
                weightsB.xy -= weightsB.yz;

                hatch0 = hatch0 * weightsA;
                hatch1 = hatch1 * weightsB;

                half3 hatching = overbright + hatch0.r + hatch0.g + hatch0.b + hatch1.r + hatch1.g + hatch1.b;

                return hatching;
            }

            Varyings vert(Attributes input)
            {
                Varyings output;
                // Convert Object space to Clip space for rendering
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                // Convert Object normal to World normal for lighting
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return output;
            }

            // Exactly your frag function, adapted for URP's GetMainLight()
            half4 frag(Varyings input) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);

                // Fetch URP Main Light data
                Light mainLight = GetMainLight();
                half3 lightColor = mainLight.color;
                half3 lightDir = normalize(mainLight.direction);
                half3 normal = normalize(input.normalWS);

                // I added saturate() here so the dark side of your objects doesn't generate negative light values!
                half NdotL = saturate(dot(normal, lightDir));
                
                half3 diffuse = color.rgb * lightColor * NdotL;

                half intensity = dot(diffuse, half3(0.2326, 0.7152, 0.0722));

                color.rgb = Hatching(input.uv * _Tiling, (1.0f - intensity));

                return float4(color.rgb, 1.0f);
            }
            ENDHLSL
        }
    }
}