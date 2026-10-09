Shader "Custom/RealtimeCausticsVolume"
{
    Properties
    {
        [NoScaleOffset] _CausticsTexture ("Caustics Texture (grayscale)", 2D) = "white" {}
        [HDR] _CausticsTint ("Caustics Tint (HDR)", Color) = (1, 1, 1, 1)

        _CausticsSpeed ("Animation Speed", Float) = 0.35
        _CausticsScale ("World Units per Tile", Float) = 3.0
        _CausticsStrength ("Caustics Strength", Range(0, 10)) = 2.0
        _CausticsSplit ("Chromatic Split (UV)", Range(0, 0.05)) = 0.004

        _CausticsEdgeFade ("Box Edge Fade (object units)", Range(0, 0.5)) = 0.08
        _CausticsShadowStrength ("Main Light Shadow Mask", Range(0, 1)) = 1.0
        _CausticsLuminanceMaskStrength ("Scene Luminance Mask", Range(0, 1)) = 0.0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
        }

        Pass
        {
            Name "CausticsVolume"
            Tags { "LightMode" = "SRPDefaultUnlit" }

            Cull Front                 // Draw the inside/back faces of the cube.
            ZWrite Off                  // Never overwrite scene depth.
            ZTest Always                // A surface can be behind the volume mesh.
            Blend One One               // Add light to the already drawn scene.
            ColorMask RGB               // Do not modify camera alpha.

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing

            // Main light shadow variants, including cascades and screen-space shadows.
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            TEXTURE2D(_CausticsTexture);
            SAMPLER(sampler_CausticsTexture);

            CBUFFER_START(UnityPerMaterial)
                float4 _CausticsTint;
                float _CausticsSpeed;
                float _CausticsScale;
                float _CausticsStrength;
                float _CausticsSplit;
                float _CausticsEdgeFade;
                float _CausticsShadowStrength;
                float _CausticsLuminanceMaskStrength;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings Vert(Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                return OUT;
            }

            // Project in a plane perpendicular to the incoming light rays.
            // These coordinates are in world units and do not swim with the camera.
            float2 GetLightProjectedUV(float3 positionWS, float3 directionToLight)
            {
                float3 lightDir = normalize(directionToLight);
                float3 reference = (abs(lightDir.z) < 0.98)
                    ? float3(0.0, 0.0, 1.0)
                    : float3(0.0, 1.0, 0.0);

                float3 axisU = normalize(cross(reference, lightDir));
                float3 axisV = cross(lightDir, axisU);

                return float2(dot(positionWS, axisU), dot(positionWS, axisV));
            }

            // 3 texture reads make a subtle color separation at the edges.
            half3 SampleChromaticCaustics(float2 uv, float split)
            {
                float2 offsetR = float2( split,  split);
                float2 offsetG = float2(0.0,   0.0);
                float2 offsetB = float2(-split, -split);

                half r = SAMPLE_TEXTURE2D(_CausticsTexture, sampler_CausticsTexture, uv + offsetR).r;
                half g = SAMPLE_TEXTURE2D(_CausticsTexture, sampler_CausticsTexture, uv + offsetG).r;
                half b = SAMPLE_TEXTURE2D(_CausticsTexture, sampler_CausticsTexture, uv + offsetB).r;

                return half3(r, g, b);
            }

            half4 Frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                // SV_POSITION.xy is in screen pixels in the fragment stage.
                float2 screenUV = IN.positionCS.xy / _ScaledScreenParams.xy;
                float rawDepth = SampleSceneDepth(screenUV);

                // Ignore background/sky pixels without valid scene geometry.
                #if UNITY_REVERSED_Z
                    if (rawDepth <= 0.0001)
                        return half4(0, 0, 0, 0);
                    float depthNDC = rawDepth;
                #else
                    if (rawDepth >= 0.9999)
                        return half4(0, 0, 0, 0);
                    float depthNDC = lerp(UNITY_NEAR_CLIP_VALUE, 1.0, rawDepth);
                #endif

                // Reconstruct the opaque surface under this volume pixel.
                float3 positionWS = ComputeWorldSpacePosition(screenUV, depthNDC, UNITY_MATRIX_I_VP);

                // Built-in Unity Cube mesh is [-0.5, 0.5] in object space.
                // Reject pixels outside the cube, then fade near its six faces.
                float3 positionOS = TransformWorldToObject(positionWS);
                float3 distanceToFace = 0.5 - abs(positionOS);
                float nearestFace = min(distanceToFace.x, min(distanceToFace.y, distanceToFace.z));
                clip(nearestFace);

                float edgeMask = smoothstep(0.0, max(_CausticsEdgeFade, 0.00001), nearestFace);

                // No custom C# light matrix required; URP supplies this.
                Light mainLight = GetMainLight();
                float2 projectedUV = GetLightProjectedUV(positionWS, mainLight.direction);

                float inverseScale = rcp(max(abs(_CausticsScale), 0.001));
                float t = _Time.y * _CausticsSpeed;

                // Two differently moving layers, as in the tutorial.
                float2 uv1 = projectedUV * inverseScale + t * float2( 0.75,  0.22);
                float2 uv2 = projectedUV * inverseScale * -1.17 + t * float2(-0.46,  0.83);

                half3 tex1 = SampleChromaticCaustics(uv1, _CausticsSplit);
                half3 tex2 = SampleChromaticCaustics(uv2, _CausticsSplit);
                half3 caustics = min(tex1, tex2);

                // Optional: attenuate caustics in real shadows from main light.
                float shadowMask = 1.0;
                if (_CausticsShadowStrength > 0.0001)
                {
                    float4 shadowCoord;
                    #if defined(_MAIN_LIGHT_SHADOWS_SCREEN)
                        shadowCoord = ComputeScreenPos(TransformWorldToHClip(positionWS));
                    #else
                        shadowCoord = TransformWorldToShadowCoord(positionWS);
                    #endif

                    Light shadowedMainLight = GetMainLight(shadowCoord);
                    shadowMask = lerp(1.0, shadowedMainLight.shadowAttenuation,
                                      _CausticsShadowStrength);
                }

                // Optional: approximate suppression on dark scene areas.
                // Requires Opaque Texture enabled when strength > 0.
                float luminanceMask = 1.0;
                if (_CausticsLuminanceMaskStrength > 0.0001)
                {
                    half3 sceneColor = SampleSceneColor(screenUV);
                    float sceneLuminance = dot(sceneColor, half3(0.2126, 0.7152, 0.0722));
                    luminanceMask = lerp(1.0, saturate(sceneLuminance),
                                         _CausticsLuminanceMaskStrength);
                }

                half3 finalColor = caustics
                    * _CausticsTint.rgb
                    * mainLight.color
                    * _CausticsStrength
                    * edgeMask
                    * shadowMask
                    * luminanceMask;

                // Alpha is ignored by Blend One One.
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }

    Fallback Off
}
