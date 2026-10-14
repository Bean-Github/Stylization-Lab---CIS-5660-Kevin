// URP fullscreen port of the Kino/Streak shader supplied in the conversation.
// Original: https://github.com/keijiro/KinoStreak
// Copyright (c) 2017 Keijiro Takahashi
//
// INTEGRATION: use the supplied StreakPass Render Graph pyramid.
// Pass indices: 0 Prefilter, 1 Downsample, 2 Upsample, 3 Composite.
// A stock Full Screen Pass Renderer Feature executes one selected pass only;
// it does not run this entire pyramid or supply _HighTex automatically.
//
// PostProcessingGraph.Draw must bind its primary input to _BlitTexture and
// set _BlitTexture_TexelSize=(1/width,1/height,width,height) for THAT input.
// Use URP's Blitter/fullscreen triangle, not legacy Graphics.Blit/vert_img.
// _BlitScaleBias is the primary source UV transform (normally 1,1,0,0).
// Bind the second input as _HighTex for passes 2 and 3 at execution time.
// Declare BOTH inputs as Render Graph reads and the destination as a write.
// All graph passes need their own captured texture bindings; do not overwrite
// a shared material's texture bindings while merely recording the graph.
//
// _HighTexScaleBias defaults to full-texture UVs (1,1,0,0). If _HighTex is a
// padded/scaled RTHandle, the draw helper must supply its own viewport mapping.
// XR texture dimensions/slices must be preserved when creating the pyramid.
// This shader uses XR texture macros but the caller still owns XR allocation.
//
// Intended for HDR camera color before post-processing/tonemapping.
// _Threshold and _Intensity are shader-space values: there is no implicit
// gamma conversion here. Any UI conversion belongs to ConfigureParameters.
// RGB equations match the pasted shader; all passes retain its alpha=1.
// No separate Streak.cginc is required. Unity compilation is not verified here.
//
// MIT License
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

Shader "Hidden/PostProcessing/Streak"
{
    Properties
    {
        _Threshold ("Threshold", Float) = 1
        _Stretch ("Stretch", Range(0, 1)) = 0.5
        _Intensity ("Intensity", Float) = 0.1
        _Color ("Tint", Color) = (1, 1, 1, 1)
        [HideInInspector] _HighTexScaleBias ("High Texture UV Scale Bias", Vector) = (1, 1, 0, 0)
        // Textures are deliberately not material Properties: the draw helper
        // supplies them per pass, including global/property-block bindings.
    }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        Cull Off
        ZWrite Off
        ZTest Always
        Blend Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

        // Blit.hlsl declares _BlitTexture, its texel size, and LinearClamp sampler.
        TEXTURE2D_X(_HighTex);

        CBUFFER_START(UnityPerMaterial)
            float4 _Color;
            float4 _HighTexScaleBias;
            float _Threshold;
            float _Stretch;
            float _Intensity;
        CBUFFER_END

        struct StreakVaryings
        {
            float4 positionCS : SV_POSITION;
            float2 sourceUV : TEXCOORD0;
            float2 highUV : TEXCOORD1;
            UNITY_VERTEX_OUTPUT_STEREO
        };

        StreakVaryings VertStreak(Attributes input)
        {
            UNITY_SETUP_INSTANCE_ID(input);
            StreakVaryings output;
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
            Varyings blit = Vert(input);
            output.positionCS = blit.positionCS;
            output.sourceUV = blit.texcoord;
            // The two inputs may have different RTHandle viewport transforms.
            float2 fullUV = GetFullScreenTriangleTexCoord(input.vertexID);
            output.highUV = fullUV * _HighTexScaleBias.xy + _HighTexScaleBias.zw;
            return output;
        }

        float3 SampleSource(float2 uv)
        {
            return SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv, 0).rgb;
        }

        float3 SampleHigh(float2 uv)
        {
            return SAMPLE_TEXTURE2D_X_LOD(_HighTex, sampler_LinearClamp, uv, 0).rgb;
        }

        float4 FragPrefilter(StreakVaryings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            // The caller halves HEIGHT here; the original horizontal comment
            // was misleading. Horizontal shrinking happens in subsequent passes.
            float dy = abs(_BlitTexture_TexelSize.y) * 0.75;
            float3 color = 0.5 * (
                SampleSource(input.sourceUV - float2(0, dy)) +
                SampleSource(input.sourceUV + float2(0, dy)));
            float brightness = max(color.r, max(color.g, color.b));
            color *= max(0.0, brightness - _Threshold) / max(brightness, 1e-5);
            return float4(color, 1.0);
        }

        float4 FragDownsample(StreakVaryings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 stepUV = float2(abs(_BlitTexture_TexelSize.x) * 1.25, 0);
            float2 uv = input.sourceUV;
            float3 color = SampleSource(uv - stepUV * 5.0)
                         + SampleSource(uv - stepUV * 3.0)
                         + SampleSource(uv - stepUV)
                         + SampleSource(uv + stepUV)
                         + SampleSource(uv + stepUV * 3.0)
                         + SampleSource(uv + stepUV * 5.0);
            return float4(color / 6.0, 1.0);
        }

        float4 FragUpsample(StreakVaryings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            // Original weights 1/4 + 1/2 + 1/4 sample the SAME coordinate.
            // A single bilinear sample therefore preserves the pasted equation.
            float3 low = SampleSource(input.sourceUV);
            float3 high = SampleHigh(input.highUV);
            return float4(lerp(high, low, _Stretch), 1.0);
        }

        float4 FragComposite(StreakVaryings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float3 streak = SampleSource(input.sourceUV);
            float3 scene = SampleHigh(input.highUV);
            return float4(scene + streak * _Color.rgb * (_Intensity * 5.0), 1.0);
        }
        ENDHLSL

        Pass
        {
            Name "Prefilter"
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex VertStreak
            #pragma fragment FragPrefilter
            #pragma multi_compile_instancing
            ENDHLSL
        }
        Pass
        {
            Name "Downsample"
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex VertStreak
            #pragma fragment FragDownsample
            #pragma multi_compile_instancing
            ENDHLSL
        }
        Pass
        {
            Name "Upsample"
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex VertStreak
            #pragma fragment FragUpsample
            #pragma multi_compile_instancing
            ENDHLSL
        }
        Pass
        {
            Name "Composite"
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex VertStreak
            #pragma fragment FragComposite
            #pragma multi_compile_instancing
            ENDHLSL
        }
    }
    FallBack Off
}
