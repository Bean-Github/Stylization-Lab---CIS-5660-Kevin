Shader "Custom/Mewtwo/Stylized Outline"
{
    Properties
    {
        [Header(Outline)]
        _Outline_Color("Outline Color", Color) = (1, 1, 1, 1)
        _Outline_ColorScrollTex("Scrolling Color Texture", 2D) = "white" {}
        _Outline_Thinkeness("Outline Thickness", Float) = 0.1
        _Outline_Brightness("Outline Brightness", Float) = 1
        _Outline_ColorTexScrollSpeed("Color Scroll Speed (XY)", Vector) = (1, 1, 0, 0)

        [Header(Scene Depth Rejection)]
        [Toggle] _UseSceneDepth("Enable Scene Depth Comparison", Float) = 1
        _DepthTolerance("Depth Tolerance (World Units)", Float) = 0.001
        _DepthBias("Depth Bias (Positive Hides More)", Float) = 0

        [Header(Noise)]
        _Noise1_Intencity("Noise 1 Intensity", Float) = 1
        _Noise2_Intencity("Noise 2 Intensity", Float) = 1
        _Noise1_Tile("Noise 1 Tiling (XY)", Vector) = (1, 1, 0, 0)
        _Noise2_Tile("Noise 2 Tiling (XY)", Vector) = (1, 1, 0, 0)
        _Noise1_Scale("Noise 1 Scale", Float) = 50
        _Noise2_Scale("Noise 2 Scale", Float) = 10
        _Noise1_Speed("Noise 1 Speed (XY)", Vector) = (0, 1, 0, 0)
        _Noise2_Speed("Noise 2 Speed (XY)", Vector) = (0, 1, 0, 0)

        // Retain the source's render-state property names and defaults.
        [HideInInspector] _SrcBlend("Source Blend", Float) = 1
        [HideInInspector] _DstBlend("Destination Blend", Float) = 0
        [HideInInspector] _ZTest("Depth Test", Float) = 4
        [HideInInspector] _Cull("Cull Mode", Float) = 1
        [HideInInspector] _AlphaToMask("Alpha To Coverage", Float) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "UniversalMaterialType" = "Unlit"
            "Queue" = "Transparent"
            // Displacement uses object-space positions and object scale.
            "DisableBatching" = "True"
        }

        Stencil
        {
            Ref 9
            ReadMask 9
            Comp NotEqual
            Pass Keep
        }

        Cull [_Cull]
        ZTest [_ZTest]

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Hashes.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _Outline_Color;
            float4 _Outline_ColorScrollTex_ST;
            float4 _Outline_ColorTexScrollSpeed;
            float4 _Noise1_Tile;
            float4 _Noise2_Tile;
            float4 _Noise1_Speed;
            float4 _Noise2_Speed;
            float _Outline_Thinkeness;
            float _Outline_Brightness;
            float _Noise1_Intencity;
            float _Noise2_Intencity;
            float _Noise1_Scale;
            float _Noise2_Scale;
            float _UseSceneDepth;
            float _DepthTolerance;
            float _DepthBias;
        CBUFFER_END

        TEXTURE2D(_Outline_ColorScrollTex);
        SAMPLER(sampler_Outline_ColorScrollTex);

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

        // Keep Shader Graph's deterministic hash so the noise pattern matches.
        float ValueNoise(float2 uv)
        {
            float2 cell = floor(uv);
            float2 blend = frac(uv);
            blend = blend * blend * (3.0 - 2.0 * blend);

            float bottomLeft, bottomRight, topLeft, topRight;
            Hash_Tchou_2_1_float(cell, bottomLeft);
            Hash_Tchou_2_1_float(cell + float2(1, 0), bottomRight);
            Hash_Tchou_2_1_float(cell + float2(0, 1), topLeft);
            Hash_Tchou_2_1_float(cell + float2(1, 1), topRight);
            return lerp(lerp(bottomLeft, bottomRight, blend.x),
                        lerp(topLeft, topRight, blend.x), blend.y);
        }

        float SimpleNoise(float2 uv, float scale)
        {
            // Shader Graph Simple Noise: three octaves, without normalization.
            return ValueNoise(uv * scale)        * 0.125
                 + ValueNoise(uv * scale * 0.5)  * 0.25
                 + ValueNoise(uv * scale * 0.25) * 0.5;
        }

        float3 ExpandOutline(float3 positionOS, float3 normalOS)
        {
            float2 worldXY = TransformObjectToWorld(positionOS).xy;
            float time = _TimeParameters.x;

            // Layer A: Tile1 + Speed2 + Scale2 + Intensity1.
            // Layer B: Tile2 + Speed1 + Scale1 + Intensity2.
            float2 uvA = worldXY * _Noise1_Tile.xy - time * _Noise2_Speed.xy;
            float2 uvB = worldXY * _Noise2_Tile.xy - time * _Noise1_Speed.xy;
            float noiseA = smoothstep(0.5, 1.0, SimpleNoise(uvA, _Noise2_Scale));
            float noiseB = smoothstep(0.0, 1.0, SimpleNoise(uvB, _Noise1_Scale));
            float noiseAmount = noiseA * _Noise1_Intencity
                              * noiseB * _Noise2_Intencity;

            float3 objectScale = float3(
                length(float3(UNITY_MATRIX_M[0].x, UNITY_MATRIX_M[1].x, UNITY_MATRIX_M[2].x)),
                length(float3(UNITY_MATRIX_M[0].y, UNITY_MATRIX_M[1].y, UNITY_MATRIX_M[2].y)),
                length(float3(UNITY_MATRIX_M[0].z, UNITY_MATRIX_M[1].z, UNITY_MATRIX_M[2].z)));

            // Only the base shell width is scale compensated in the source.
            // The epsilon prevents division by zero for collapsed transforms.
            float3 baseOffset = normalize(normalOS) * _Outline_Thinkeness
                              / max(objectScale, float3(0.00001, 0.00001, 0.00001));
            float3 noiseOffset = normalOS * noiseAmount * _Outline_Thinkeness;
            return positionOS + baseOffset + noiseOffset;
        }

        Varyings OutlineVertex(Attributes input)
        {
            Varyings output = (Varyings)0;
            UNITY_SETUP_INSTANCE_ID(input);
            UNITY_TRANSFER_INSTANCE_ID(input, output);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

            float3 expandedOS = ExpandOutline(input.positionOS, input.normalOS);
            output.positionWS = TransformObjectToWorld(expandedOS);
            output.positionCS = TransformWorldToHClip(output.positionWS);
            // The graph keeps the original normal after displacement.
            output.normalWS = TransformObjectToWorldNormal(input.normalOS);
            return output;
        }

        void ClipFrontFace(FRONT_FACE_TYPE face)
        {
            // Graph Alpha = front face ? 0 : 1; threshold = 0.5.
            // Texture alpha and Outline Color alpha are intentionally unused.
            clip(IS_FRONT_VFACE(face, -1.0, 1.0));
        }

        // Convert hardware depth to positive camera-space Z distance.
        // LinearEyeDepth handles reversed Z for perspective cameras.
        // Orthographic cameras need a linear near/far interpolation instead.
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
            if (_UseSceneDepth < 0.5)
                return;

            // In a fragment shader SV_POSITION.xy is in pixel coordinates.
            // SampleSceneDepth performs URP's stereo texture handling.
            float2 screenUV = GetNormalizedScreenSpaceUV(pixelPosition.xy);
            float rawSceneDepth = SampleSceneDepth(screenUV);

            // An untouched far-plane/sky pixel has no occluder.
            #if UNITY_REVERSED_Z
                if (rawSceneDepth <= 0.0) return;
            #else
                if (rawSceneDepth >= 1.0) return;
            #endif

            float sceneEyeDepth = SceneEyeDepth(rawSceneDepth);
            float tolerance = max(_DepthTolerance, 0.0);

            // Bias = 0: discard if scene depth < fragment depth - tolerance.
            // Positive bias virtually pushes the outline deeper for this test,
            // rejecting even a shell slightly in front of the original surface.
            // This changes only the rejection test, not the vertex or depth output.
            clip(sceneEyeDepth + tolerance - (fragmentEyeDepth + _DepthBias));
        }

        half4 OutlineFragment(Varyings input, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
        {
            UNITY_SETUP_INSTANCE_ID(input);
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            ClipFrontFace(face);

            // Camera/view-space XY projection, not mesh UVs or screen UVs.
            float3 positionVS = TransformWorldToView(input.positionWS);
            RejectBySceneDepth(input.positionCS, -positionVS.z);
            float2 uv = positionVS.xy - _TimeParameters.x * _Outline_ColorTexScrollSpeed.xy;
            uv = uv * _Outline_ColorScrollTex_ST.xy + _Outline_ColorScrollTex_ST.zw;
            half3 color = SAMPLE_TEXTURE2D(_Outline_ColorScrollTex,
                sampler_Outline_ColorScrollTex, uv).rgb;
            color *= _Outline_Color.rgb * _Outline_Brightness;

            // Fragment fog, based on view-space depth, as in the generated pass.
            float fogFactor = ComputeFogFactorZ0ToFar(max(-positionVS.z - _ProjectionParams.y, 0.0));
            return half4(MixFog(color, fogFactor), _Outline_Color.a);
        }

        float4 _SelectionID;
        int _ObjectId;
        int _PassValue;

        float4 SelectionFragment(Varyings input, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
        {
            ClipFrontFace(face);
            return float4(_ObjectId, _PassValue, 1, 1);
        }

        float4 PickingFragment(Varyings input, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
        {
            ClipFrontFace(face);
            return _SelectionID;
        }
        ENDHLSL

        Pass
        {
            Name "Outline"
            Tags { "LightMode" = "UniversalForwardOnly" }
            Blend [_SrcBlend] [_DstBlend]
            // Do not contaminate scene depth or prevent later surfaces drawing.
            ZWrite Off
            AlphaToMask [_AlphaToMask]
            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex OutlineVertex
            #pragma fragment OutlineFragment
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            ENDHLSL
        }

        Pass
        {
            Name "SceneSelectionPass"
            Tags { "LightMode" = "SceneSelectionPass" }
            Cull Off
            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex OutlineVertex
            #pragma fragment SelectionFragment
            #pragma multi_compile_instancing
            ENDHLSL
        }

        Pass
        {
            Name "ScenePickingPass"
            Tags { "LightMode" = "Picking" }
            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex OutlineVertex
            #pragma fragment PickingFragment
            #pragma multi_compile_instancing
            ENDHLSL
        }
    }
    Fallback Off
}
