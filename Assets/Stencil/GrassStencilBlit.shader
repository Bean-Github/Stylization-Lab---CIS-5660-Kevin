Shader "Hidden/GrassStencilComposite"
{
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }


        // ============================================================
        // PASS 0
        //
        // COLOR COMPOSITE
        // ============================================================

        Pass
        {
            Name "GrassStencilColorComposite"

            Cull Off
            ZWrite Off
            ZTest Always

            Stencil
            {
                Ref 8
                ReadMask 8

                Comp Equal

                Pass Keep
                Fail Keep
                ZFail Keep
            }

            Blend SrcAlpha OneMinusSrcAlpha


            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment FragColor

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"


            half4 FragColor(Varyings input) : SV_Target
            {
                half4 grass =
                    SAMPLE_TEXTURE2D_X(
                        _BlitTexture,
                        sampler_LinearClamp,
                        input.texcoord);

                // Temp color was cleared transparent.
                clip(grass.a - 0.01h);

                return grass;
            }

            ENDHLSL
        }


        // ============================================================
        // PASS 1
        //
        // DEPTH COMPOSITE
        // ============================================================

        Pass
        {
            Name "GrassStencilDepthComposite"

            Cull Off

            // We ARE writing camera depth here.
            ZWrite On

            // We're directly supplying the desired raw depth.
            ZTest Always

            // No color output from this pass.
            ColorMask 0


            // Same stencil mask as color.
            Stencil
            {
                Ref 8
                ReadMask 8

                Comp Equal

                Pass Keep
                Fail Keep
                ZFail Keep
            }


            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment FragDepth

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"


            float FragDepth(Varyings input) : SV_Depth
            {
                // TempDepth contains raw hardware depth.
                //
                // We return that directly as SV_Depth.
                //
                // No Linear01 conversion.
                // No eye depth conversion.
                // This also preserves reversed-Z correctly.
                float depth =
                    SAMPLE_TEXTURE2D_X(
                        _BlitTexture,
                        sampler_PointClamp,
                        input.texcoord).r;

                return depth;
            }

            ENDHLSL
        }
    }
}