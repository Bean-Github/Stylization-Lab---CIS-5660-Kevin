using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RendererUtils;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class PencilSketchFeature : ScriptableRendererFeature
{
    public Material compositeMat;
    public Material uvMat; // 1. Added the UV Material slot

    PencilSketchPass pass;

    public override void Create()
    {
        pass = new PencilSketchPass
        {
            compositeMat = compositeMat,
            uvMat = uvMat,
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // Don't run if either material is missing
        if (compositeMat == null || uvMat == null) return;
        renderer.EnqueuePass(pass);
    }

    class PencilSketchPass : ScriptableRenderPass
    {
        public Material compositeMat;
        public Material uvMat;

        // Data containers for our 3 passes
        class UVPassData { public RendererListHandle rendererList; }
        class CompositePassData { public TextureHandle src; public TextureHandle uvTex; public Material material; }
        class CopyPassData { public TextureHandle src; }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var resourceData = frameData.Get<UniversalResourceData>();
            var cameraData = frameData.Get<UniversalCameraData>();
            var renderingData = frameData.Get<UniversalRenderingData>();

            TextureHandle cameraColor = resourceData.activeColorTexture;
            if (!cameraColor.IsValid()) return;

            // --- 1. SETUP TEXTURES ---
            var desc = cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0; // Color textures don't need depth

            // Create Temp Camera Texture
            TextureHandle tempTex = renderGraph.CreateTexture(new TextureDesc(desc.width, desc.height)
            {
                colorFormat = desc.graphicsFormat,
                name = "TempBlitTexture"
            });

            // Create UV Texture (Using floating point format so negative UVs or high values don't get clamped)
            TextureHandle uvTex = renderGraph.CreateTexture(new TextureDesc(desc.width, desc.height)
            {
                colorFormat = UnityEngine.Experimental.Rendering.GraphicsFormat.R32G32B32A32_SFloat,
                name = "UVTexture",
                clearBuffer = true,
                clearColor = Color.clear
            });

            // --- 2. PASS 1: DRAW UVs ---
            // Tell Unity to grab all normal 3D objects and draw them using our UV Material
            var shaderTags = new ShaderTagId[] {
                new ShaderTagId("UniversalForward"),
                new ShaderTagId("UniversalForwardOnly"),
                new ShaderTagId("LightweightForward"),
                new ShaderTagId("SRPDefaultUnlit") // <-- Crucial for unlit/standard objects!
            };
            var rendererListDesc = new RendererListDesc(shaderTags, renderingData.cullResults, cameraData.camera)
            {
                overrideMaterial = uvMat,
                overrideMaterialPassIndex = 0,     // CRITICAL: Explicitly use the first pass of our UV Material
                renderQueueRange = RenderQueueRange.opaque,
                layerMask = -1                     // CRITICAL: -1 means "Look at ALL Layers". 
            };
            RendererListHandle rendererList = renderGraph.CreateRendererList(rendererListDesc);

            using (var builder = renderGraph.AddRasterRenderPass<UVPassData>("Draw UVs", out var passData))
            {
                passData.rendererList = rendererList;
                builder.UseRendererList(rendererList);

                builder.SetRenderAttachment(uvTex, 0); // Paint the colors to our UV texture

                // CRITICAL: Use the scene's depth buffer so objects properly hide behind each other
               // builder.SetRenderAttachmentDepth(resourceData.activeDepthTexture, AccessFlags.Read);

                builder.SetRenderFunc((UVPassData data, RasterGraphContext ctx) => {
                    ctx.cmd.DrawRendererList(data.rendererList);
                });
            }

            // --- 3. PASS 2: COMPOSITE ---
            using (var builder = renderGraph.AddRasterRenderPass<CompositePassData>("Pencil Composite", out var passData))
            {
                passData.src = cameraColor;
                passData.uvTex = uvTex;
                passData.material = compositeMat;

                builder.UseTexture(passData.src, AccessFlags.Read);
                builder.UseTexture(passData.uvTex, AccessFlags.Read); // Ensure RenderGraph knows we are reading this!
                builder.SetRenderAttachment(tempTex, 0);

                builder.AllowGlobalStateModification(true);

                builder.SetRenderFunc((CompositePassData data, RasterGraphContext ctx) => {
                    // 1. Give the texture to the Command Buffer, NOT the material!
                    ctx.cmd.SetGlobalTexture("_UVTexture", data.uvTex);

                    // 2. Blit the screen
                    Blitter.BlitTexture(ctx.cmd, data.src, Vector4.one, data.material, 0);
                });
            }

            // --- 4. PASS 3: COPY BACK TO CAMERA ---
            using (var builder = renderGraph.AddRasterRenderPass<CopyPassData>("Copy Back", out var passData))
            {
                passData.src = tempTex;

                builder.UseTexture(passData.src, AccessFlags.Read);
                builder.SetRenderAttachment(cameraColor, 0);

                builder.SetRenderFunc((CopyPassData data, RasterGraphContext ctx) => {
                    // Scale = 1, Offset = 0
                    Vector4 scaleBias = new Vector4(1f, 1f, 0f, 0f);
                    Blitter.BlitTexture(ctx.cmd, data.src, scaleBias, 0.0f, false);
                });
            }
        }
    }
}





