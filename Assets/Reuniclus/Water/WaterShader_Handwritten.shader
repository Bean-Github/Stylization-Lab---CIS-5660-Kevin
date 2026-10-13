Shader "Custom/Water/CameraDistanceRippleSSPR_4ColorNoiseSpecular"
{
    Properties
    {
        [Header(Four Color Gradient)]
        // Alpha of each HDR color controls its opacity.
        [HDR] _NearColor ("Near Color + Opacity (Alpha)", Color) = (0.12, 0.70, 0.80, 1)
        [HDR] _Mid1Color ("Mid 1 Color + Opacity (Alpha)", Color) = (0.06, 0.51, 0.68, 1)
        [HDR] _Mid2Color ("Mid 2 Color + Opacity (Alpha)", Color) = (0.03, 0.35, 0.55, 1)
        [HDR] _FarColor ("Far Color + Opacity (Alpha)", Color) = (0.01, 0.07, 0.20, 1)

        _NearDistance ("Near Distance (World Units)", Float) = 0
        _Mid1Distance ("Mid 1 Distance (World Units)", Float) = 4
        _Mid2Distance ("Mid 2 Distance (World Units)", Float) = 9
        _FarDistance ("Far Distance (World Units)", Float) = 16

        [Header(Transition Widths)]
        // 1 = smooth over the full distance interval; smaller = narrow noisy borders.
        _NearMidBlendWidth ("Near to Mid 1 Blend Width", Range(0.01, 1)) = 0.30
        _MidMidBlendWidth ("Mid 1 to Mid 2 Blend Width", Range(0.01, 1)) = 0.30
        _MidFarBlendWidth ("Mid 2 to Far Blend Width", Range(0.01, 1)) = 0.30

        [Header(Near Color Boundary Noise)]
        _NearNoiseStrength ("Near Noise Displacement (World Units)", Range(0, 5)) = 1.2
        _NearNoiseScale ("Near Noise Size (World Units)", Float) = 2
        _NearNoiseStretch ("Near Noise Stretch (X Z)", Vector) = (5, 1, 0, 0)

        [Header(Mid 1 Color Boundary Noise)]
        _Mid1NoiseStrength ("Mid 1 Noise Displacement (World Units)", Range(0, 5)) = 1.2
        _Mid1NoiseScale ("Mid 1 Noise Size (World Units)", Float) = 2
        _Mid1NoiseStretch ("Mid 1 Noise Stretch (X Z)", Vector) = (5, 1, 0, 0)

        [Header(Mid 2 Color Boundary Noise)]
        _Mid2NoiseStrength ("Mid 2 Noise Displacement (World Units)", Range(0, 5)) = 1.2
        _Mid2NoiseScale ("Mid 2 Noise Size (World Units)", Float) = 2
        _Mid2NoiseStretch ("Mid 2 Noise Stretch (X Z)", Vector) = (5, 1, 0, 0)

        [Header(Far Color Boundary Noise)]
        _FarNoiseStrength ("Far Noise Displacement (World Units)", Range(0, 5)) = 1.2
        _FarNoiseScale ("Far Noise Size (World Units)", Float) = 2
        _FarNoiseStretch ("Far Noise Stretch (X Z)", Vector) = (5, 1, 0, 0)

        [Header(Noise Movement)]
        _NoiseScroll ("Noise Scroll Speed XZ (Units per Second)", Vector) = (0, 0, 0, 0)

        [Header(Ripples)]
        [NoScaleOffset] _RippleTex ("Ripple Texture", 2D) = "black" {}
        _RippleCameraSize ("Ripple Camera Half Size", Float) = 0
        _RippleCameraPos ("Ripple Camera Position", Vector) = (0, 0, 0, 0)
        _RippleTextureSize ("Ripple Texture Resolution", Float) = 512
        _RippleStrength ("Ripple Normal Strength", Range(0, 100)) = 15
        _RippleShading ("Ripple Light-Dark Contrast", Range(0, 2)) = 0.5

        [Header(Planar Reflections)]
        _ReflectionStrength ("Reflection Strength", Range(0, 1)) = 0.65
        _ReflectionDistortion ("Ripple Reflection Distortion", Range(0, 0.1)) = 0.012

        [Header(Surface Brightness and Specular)]
        _SurfaceBrightness ("Overall Water Brightness", Range(0, 4)) = 1
        [HDR] _SpecularColor ("Specular Highlight Color", Color) = (1, 1, 1, 1)
        _SpecularStrength ("Specular Brightness", Range(0, 20)) = 2
        _SpecularPower ("Specular Sharpness", Range(1, 512)) = 96
        _SpecularDirection ("Direction To Highlight Source (World)", Vector) = (0.3, 1, 0.2, 0)
        _SpecularRippleInfluence ("Ripple Influence On Specular", Range(0, 3)) = 1
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
            Name "Forward"
            Tags { "LightMode" = "UniversalForward" }

            Cull Back
            ZWrite Off
            ZTest LEqual
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_RippleTex);
            SAMPLER(sampler_RippleTex);

            // Written by the project's existing Mobile SSPR renderer.
            // The texture alpha encodes which reflection pixels are valid.
            TEXTURE2D(_MobileSSPR_ColorRT);
            SAMPLER(sampler_MobileSSPR_ColorRT);

            CBUFFER_START(UnityPerMaterial)
                float4 _NearColor, _Mid1Color, _Mid2Color, _FarColor;
                float _NearDistance, _Mid1Distance, _Mid2Distance, _FarDistance;
                float _NearMidBlendWidth, _MidMidBlendWidth, _MidFarBlendWidth;

                float _NearNoiseStrength, _NearNoiseScale;
                float4 _NearNoiseStretch;
                float _Mid1NoiseStrength, _Mid1NoiseScale;
                float4 _Mid1NoiseStretch;
                float _Mid2NoiseStrength, _Mid2NoiseScale;
                float4 _Mid2NoiseStretch;
                float _FarNoiseStrength, _FarNoiseScale;
                float4 _FarNoiseStretch;
                float4 _NoiseScroll;

                float _RippleCameraSize;
                float4 _RippleCameraPos;
                float _RippleTextureSize, _RippleStrength, _RippleShading;
                float _ReflectionStrength, _ReflectionDistortion;

                float _SurfaceBrightness;
                float4 _SpecularColor;
                float _SpecularStrength, _SpecularPower;
                float4 _SpecularDirection;
                float _SpecularRippleInfluence;
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

            Varyings Vert(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.positionWS = TransformObjectToWorld(input.positionOS);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return output;
            }

            // Smooth procedural value noise, returning approximately [-1, 1].
            float Hash(float2 p)
            {
                return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
            }

            float ValueNoise(float2 p)
            {
                float2 cell = floor(p);
                float2 f = frac(p);
                f = f * f * (3.0 - 2.0 * f);

                float n00 = Hash(cell);
                float n10 = Hash(cell + float2(1, 0));
                float n01 = Hash(cell + float2(0, 1));
                float n11 = Hash(cell + float2(1, 1));

                float a = lerp(n00, n10, f.x);
                float b = lerp(n01, n11, f.x);
                return lerp(a, b, f.y) * 2.0 - 1.0;
            }

            // Two scales give the border a broad shape with finer breakup.
            float OrganicNoise(float2 p)
            {
                return (ValueNoise(p) + 0.45 * ValueNoise(p * 2.17 + float2(17.2, -9.7))) / 1.45;
            }

            // Stretch > 1 makes features longer along that world axis.
            // Each color owns a unique noise profile; neighboring profiles
            // contribute equally to their shared transition boundary.
            float StopNoise(float2 worldXZ, float size, float2 stretch, float2 seed)
            {
                float2 worldSize = max(abs(stretch), float2(0.01, 0.01)) * max(abs(size), 0.01);
                return OrganicNoise(worldXZ / worldSize + seed);
            }

            // One transition between two color stops. Width is a fraction of
            // their distance separation; noise offsets the border in world units.
            float Transition(float distanceToCamera, float startDist, float endDist,
                             float relativeWidth, float noiseOffset)
            {
                float interval = max(endDist - startDist, 0.0001);
                float center = 0.5 * (startDist + endDist);
                float halfWidth = 0.5 * interval * max(relativeWidth, 0.01);
                // Prevent extremely high noise values from displacing borders
                // beyond the neighboring stop distances.
                float displacement = clamp(noiseOffset, -interval * 0.49, interval * 0.49);
                return smoothstep(center - halfWidth, center + halfWidth,
                                  distanceToCamera + displacement);
            }

            float4 EvaluateGradient(float cameraDistance, float2 worldXZ)
            {
                // Ensure ordered stops even if sliders are set inconsistently.
                float d0 = max(0.0, _NearDistance);
                float d1 = max(d0 + 0.0001, _Mid1Distance);
                float d2 = max(d1 + 0.0001, _Mid2Distance);
                float d3 = max(d2 + 0.0001, _FarDistance);

                float2 noisePos = worldXZ + _NoiseScroll.xy * _Time.y;
                float n0 = StopNoise(noisePos, _NearNoiseScale, _NearNoiseStretch.xy, float2(13.1, 3.6));
                float n1 = StopNoise(noisePos, _Mid1NoiseScale, _Mid1NoiseStretch.xy, float2(-5.7, 29.4));
                float n2 = StopNoise(noisePos, _Mid2NoiseScale, _Mid2NoiseStretch.xy, float2(41.3, -10.8));
                float n3 = StopNoise(noisePos, _FarNoiseScale, _FarNoiseStretch.xy, float2(8.5, 52.1));

                // Each color controls the two boundaries touching that color.
                float warp01 = 0.5 * (n0 * _NearNoiseStrength + n1 * _Mid1NoiseStrength);
                float warp12 = 0.5 * (n1 * _Mid1NoiseStrength + n2 * _Mid2NoiseStrength);
                float warp23 = 0.5 * (n2 * _Mid2NoiseStrength + n3 * _FarNoiseStrength);

                float t01 = Transition(cameraDistance, d0, d1, _NearMidBlendWidth, warp01);
                float t12 = Transition(cameraDistance, d1, d2, _MidMidBlendWidth, warp12);
                float t23 = Transition(cameraDistance, d2, d3, _MidFarBlendWidth, warp23);

                // RGBA is interpolated together: each stop's alpha = its opacity.
                float4 color = lerp(_NearColor, _Mid1Color, t01);
                color = lerp(color, _Mid2Color, t12);
                color = lerp(color, _FarColor, t23);
                return color;
            }

            // Same ripple RT mapping as your existing handwritten water shader.
            float2 GetRippleSlope(float3 worldPos) // calculates the gradient
            {
                if (_RippleCameraSize <= 0.00001)
                    return float2(0.0, 0.0);

                float2 uv = (worldPos.xz - _RippleCameraPos.xz) /
                            max(2.0 * abs(_RippleCameraSize), 0.00001) + 0.5;

                float pixel = 1.0 / max(_RippleTextureSize, 1.0);
                float edge = min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y));

                if (edge <= pixel)
                    return float2(0.0, 0.0);

                float fade = smoothstep(pixel, pixel * 5.0, edge);

                float right = SAMPLE_TEXTURE2D(_RippleTex, sampler_RippleTex,
                                               uv + float2(pixel, 0)).r;
                float left  = SAMPLE_TEXTURE2D(_RippleTex, sampler_RippleTex,
                                               uv - float2(pixel, 0)).r;
                float up    = SAMPLE_TEXTURE2D(_RippleTex, sampler_RippleTex,
                                               uv + float2(0, pixel)).r;
                float down  = SAMPLE_TEXTURE2D(_RippleTex, sampler_RippleTex,
                                               uv - float2(0, pixel)).r;
                return 0.5 * float2(right - left, up - down) * fade;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                float cameraDistance = distance(GetCameraPositionWS(), input.positionWS);
                float4 gradient = EvaluateGradient(cameraDistance, input.positionWS.xz);

                float2 slope = GetRippleSlope(input.positionWS);
                float3 rippleTiltWS = float3(-slope.x, 0.0, -slope.y) * _RippleStrength;

                // Preserve the existing ripple brightness/shading behavior.
                float lightDark = dot(rippleTiltWS.xz, normalize(float2(0.8, 0.6)));
                gradient.rgb *= max(0.0, 1.0 + lightDark * _RippleShading);
                gradient.rgb *= _SurfaceBrightness;

                // Keep the original Mobile SSPR reflection texture and blending.
                float2 screenUV = GetNormalizedScreenSpaceUV(input.positionCS);
                float2 rippleTiltVS = TransformWorldToViewDir(rippleTiltWS).xy;
                float2 reflectionUV = saturate(screenUV + rippleTiltVS * _ReflectionDistortion);
                half4 reflection = SAMPLE_TEXTURE2D(
                    _MobileSSPR_ColorRT, sampler_MobileSSPR_ColorRT, reflectionUV);
                float reflectionBlend = saturate(reflection.a * _ReflectionStrength);
                gradient.rgb = lerp(gradient.rgb, reflection.rgb, reflectionBlend);

                // Simple Blinn-Phong highlight. Direction is art-directable and
                // does not require a particular main light or lighting setup.
                float3 normalWS = normalize(input.normalWS + rippleTiltWS * _SpecularRippleInfluence);
                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                float3 lightDirWS = normalize(_SpecularDirection.xyz + float3(0.0, 0.00001, 0.0));
                float3 halfDirWS = normalize(lightDirWS + viewDirWS + float3(0.0, 0.00001, 0.0));
                float ndotl = saturate(dot(normalWS, lightDirWS));
                float highlight = pow(saturate(dot(normalWS, halfDirWS)), _SpecularPower) * ndotl;
                gradient.rgb += _SpecularColor.rgb * (highlight * _SpecularStrength);

                return half4(gradient.rgb, saturate(gradient.a));
            }
            ENDHLSL
        }
    }
    FallBack Off
}
