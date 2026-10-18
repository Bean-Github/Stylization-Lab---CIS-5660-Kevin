
Shader "Custom/Gengar/Stylized Outline Pulse HDR"
{
    Properties
    {
        [Header(Outline)]
        [HDR] _Outline_Color("Color (HDR RGBA)", Color) = (1, 1, 1, 1)
        _Outline_Thinkeness("Outset (World Units)", Float) = 0.1
        _Outline_Brightness("Brightness", Float) = 1
        _Opacity("Opacity", Range(0, 1)) = 1

        [Header(Out And Back Pulse)]
        [Toggle] _PulseEnabled("Enable Pulse", Float) = 1
        _PulseDistance("Pulse Travel (World Units)", Float) = 0.2
        _PulseSpeed("Pulses Per Second", Float) = 1
        _PulsePhase("Phase Offset (Cycles)", Range(0, 1)) = 0
        _PulseStartOpacity("Start Opacity", Range(0, 1)) = 0.35
        _PulseEndOpacity("End Opacity", Range(0, 1)) = 0.35
        _PulseFadeIn("Fade In (Fraction Of Cycle)", Range(0, 0.5)) = 0.08
        _PulseFadeOut("Fade Out (Fraction Of Cycle)", Range(0.01, 1)) = 0.35

        [Header(Optional Gap Approximation)]
        _RimLimit("Rim Limit (1 = No Inner Clipping)", Range(0, 1)) = 1
        _RimSoftness("Inner Rim Softness", Range(0, 2.0)) = 0.05
        _OuterSoftness("Outer Edge Softness", Range(0, 2.0)) = 0

        [Header(Smooth Noise)]
        _NoiseStrength("Thickness Variation", Range(0, 1)) = 0.15
        _NoiseOpacity("Opacity Variation", Range(0, 1)) = 0
        _NoiseFrequency("Frequency (Lower = Broader)", Float) = 2
        _NoiseSpeed("Scroll Speed (XY)", Vector) = (0.05, 0.15, 0, 0)
        _NoiseDetail("Fine Detail", Range(0, 1)) = 0.1
        [Enum(WorldXY,0,ObjectXY,1)] _NoiseSpace("Noise Coordinates", Float) = 0

        [Header(Scene Depth Rejection)]
        [Toggle] _UseSceneDepth("Enable Depth Comparison", Float) = 1
        _DepthTolerance("Depth Tolerance (World Units)", Float) = 0.001
        _DepthBias("Depth Bias (Positive Hides More)", Float) = 0
        [HideInInspector] _ZTest("Depth Test", Float) = 4
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "UniversalMaterialType" = "Unlit"
            "Queue" = "Transparent"
            "DisableBatching" = "True"
        }

        Cull Front
        ZTest [_ZTest]
        ZWrite Off
        Blend One OneMinusSrcAlpha

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Hashes.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _Outline_Color;
            float4 _NoiseSpeed;
            float _Outline_Thinkeness;
            float _Outline_Brightness;
            float _Opacity;
            float _PulseEnabled;
            float _PulseDistance;
            float _PulseSpeed;
            float _PulsePhase;
            float _PulseStartOpacity;
            float _PulseEndOpacity;
            float _PulseFadeIn;
            float _PulseFadeOut;
            float _RimLimit;
            float _RimSoftness;
            float _OuterSoftness;
            float _NoiseStrength;
            float _NoiseOpacity;
            float _NoiseFrequency;
            float _NoiseDetail;
            float _NoiseSpace;
            float _UseSceneDepth;
            float _DepthTolerance;
            float _DepthBias;
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
            float noise : TEXCOORD2;
            float pulseOpacity : TEXCOORD3;
            UNITY_VERTEX_INPUT_INSTANCE_ID
            UNITY_VERTEX_OUTPUT_STEREO
        };

        float ValueNoise(float2 uv)
        {
            float2 cell = floor(uv);
            float2 f = frac(uv);
            // Quintic interpolation softens transitions between noise cells.
            f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
            float a, b, c, d;
            Hash_Tchou_2_1_float(cell, a);
            Hash_Tchou_2_1_float(cell + float2(1, 0), b);
            Hash_Tchou_2_1_float(cell + float2(0, 1), c);
            Hash_Tchou_2_1_float(cell + float2(1, 1), d);
            return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
        }

        float SmoothNoise(float3 positionOS, float3 positionWS)
        {
            float2 uv = _NoiseSpace > 0.5 ? positionOS.xy : positionWS.xy;
            uv = (uv - _TimeParameters.x * _NoiseSpeed.xy) * max(_NoiseFrequency, 0.0001);
            float broad = ValueNoise(uv);
            float detail = ValueNoise(uv * 2.0 + float2(19.1, 7.7));
            return lerp(broad, (broad + 0.5 * detail) / 1.5, saturate(_NoiseDetail));
        }

        // x: extra world-space expansion; y: fade envelope.
        // One cycle: base outset -> maximum expansion -> base outset.
        // Cosine gives zero travel velocity at both ends and at maximum expansion.
        float2 EvaluatePulse()
        {
            if (_PulseEnabled < 0.5 || _PulseSpeed <= 0.0)
                return float2(0.0, 1.0);

            float phase = frac(_TimeParameters.x * _PulseSpeed + _PulsePhase);
            float travel = 0.5 - 0.5 * cos(phase * 6.28318530718);
            // Normalize overlapping fade durations so the endpoints stay exact.
            float fadeInDuration = saturate(_PulseFadeIn);
            float fadeOutDuration = max(saturate(_PulseFadeOut), 0.0001);
            float durationScale = max(1.0, fadeInDuration + fadeOutDuration);
            fadeInDuration /= durationScale;
            fadeOutDuration /= durationScale;

            float opacity = 1.0;
            if (fadeInDuration > 0.0 && phase < fadeInDuration)
            {
                float t = smoothstep(0.0, fadeInDuration, phase);
                opacity = lerp(saturate(_PulseStartOpacity), 1.0, t);
            }
            else
            {
                float t = smoothstep(1.0 - fadeOutDuration, 1.0, phase);
                opacity = lerp(1.0, saturate(_PulseEndOpacity), t);
            }
            // A zero Fade In skips the start stage and begins at full opacity.
            return float2(max(_PulseDistance, 0.0) * travel, opacity);
        }

        Varyings OutlineVertex(Attributes input)
        {
            Varyings output = (Varyings)0;
            UNITY_SETUP_INSTANCE_ID(input);
            UNITY_TRANSFER_INSTANCE_ID(input, output);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

            float3 positionWS = TransformObjectToWorld(input.positionOS);
            float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
            output.noise = SmoothNoise(input.positionOS, positionWS);
            float variation = max(0.05, 1.0 + (output.noise * 2.0 - 1.0) * saturate(_NoiseStrength));
            float2 pulse = EvaluatePulse();
            float outset = max(_Outline_Thinkeness, 0.0) * variation + pulse.x;
            output.positionWS = positionWS + normalWS * outset;
            output.pulseOpacity = pulse.y;
            output.normalWS = normalWS;
            output.positionCS = TransformWorldToHClip(output.positionWS);
            return output;
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

        void RejectBySceneDepth(float4 pixelPosition, float fragmentEyeDepth)
        {
            if (_UseSceneDepth < 0.5) return;
            float2 uv = GetNormalizedScreenSpaceUV(pixelPosition.xy);
            float rawDepth = SampleSceneDepth(uv);
            #if UNITY_REVERSED_Z
                if (rawDepth <= 0.0) return;
            #else
                if (rawDepth >= 1.0) return;
            #endif
            clip(SceneEyeDepth(rawDepth) + max(_DepthTolerance, 0.0)
                 - (fragmentEyeDepth + _DepthBias));
        }

        float RimCoverage(float3 normalWS, float3 positionWS)
        {
            // 0 at a grazing silhouette; 1 when a normal points along the view.
            // Uses a view direction suitable for perspective and orthographic cameras.
            float facing = saturate(abs(dot(normalize(normalWS), GetWorldSpaceNormalizeViewDir(positionWS))));
            if (_RimLimit <= 0.0) return 0.0;
            float coverage = 1.0;
            if (_RimLimit < 1.0)
            {
                float aa = max(fwidth(facing), 0.0001);
                float softness = max(_RimSoftness, aa);
                float edgeStart = max(0.0, _RimLimit - softness);
                coverage = 1.0 - smoothstep(edgeStart, _RimLimit, facing);
            }
            if (_OuterSoftness > 0.0)
                coverage *= smoothstep(0.0, _OuterSoftness, facing);
            return coverage;
        }

        half4 OutlineFragment(Varyings input) : SV_Target
        {
            UNITY_SETUP_INSTANCE_ID(input);
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            // Compute derivatives before any depth-dependent fragment discard.
            float rim = RimCoverage(input.normalWS, input.positionWS);
            float3 positionVS = TransformWorldToView(input.positionWS);
            RejectBySceneDepth(input.positionCS, -positionVS.z);
            float opacityNoise = lerp(1.0, saturate(input.noise), saturate(_NoiseOpacity));
            half alpha = saturate(_Outline_Color.a) * saturate(_Opacity)
                       * rim * opacityNoise * input.pulseOpacity;
            half3 color = _Outline_Color.rgb * _Outline_Brightness;
            return half4(color * alpha, alpha);
        }
        ENDHLSL

        Pass
        {
            Name "Outline"
            Tags { "LightMode" = "UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex OutlineVertex
            #pragma fragment OutlineFragment
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            ENDHLSL
        }
    }
    Fallback Off
}
