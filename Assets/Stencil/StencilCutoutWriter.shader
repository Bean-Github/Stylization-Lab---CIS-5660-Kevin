Shader "Hidden/Custom/StencilCutoutWriter"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        
        ZWrite Off Cull Off ZTest Always 
        
        ColorMask 0 

        Stencil
        {
            Ref 8
            Comp Always
            Pass Replace
        }

        Pass
        {
            Name "StencilCutoutWriter"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            float4 _CutoutPos;
            float _CutoutSize;

            half4 frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                
                // FIX 2: Synchronize URP's top-to-bottom UVs with C#'s bottom-to-top Viewport Points
                #if UNITY_UV_STARTS_AT_TOP
                uv.y = 1.0 - uv.y;
                #endif
                
                // Match the C# aspect ratio correction exactly
                float aspect = _ScreenParams.x / _ScreenParams.y;
                uv.y /= aspect;

                // Calculate distance
                float dist = length(uv);

                // 4. Sample the Depth Buffer
                float rawDepth = SampleSceneDepth(uv);
                
                // Convert raw 0-1 depth to linear eye depth (actual distance in meters from camera)
                float sceneDepthMeters = LinearEyeDepth(rawDepth, _ZBufferParams);


                // check if we should NOT stencil (meaning we should NOT write a 8)
                if (_CutoutSize <= 0.0001 || sceneDepthMeters >= _CutoutPos.z - 0.1 || _CutoutPos.w == 1.0f) 
                {
                    discard;
                }
                
                return 0;
            }
            ENDHLSL
        }
    }
}