using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

// Unity 6 / URP 17 RenderGraph.
// Prepares the LIVE camera depth attachment; it does not update _CameraDepthTexture.
// Put AFTER the pass that writes stencil bit 8, and BEFORE the Inside Card color pass.
public class InsideCardStencilDepthFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public LayerMask insideCardLayer;
        public Material depthOnlyMaterial;
        public RenderPassEvent passEvent = RenderPassEvent.BeforeRenderingSkybox;
    }

    public Settings settings = new Settings();
    private StencilDepthPass pass;

    private class StencilDepthPass : ScriptableRenderPass
    {
        public LayerMask layerMask;
        public Material depthMaterial;

        private class PassData
        {
            public RendererListHandle rendererList;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            if (depthMaterial == null || layerMask.value == 0)
                return;

            var resources = frameData.Get<UniversalResourceData>();
            if (!resources.activeDepthTexture.IsValid() ||
                !resources.activeColorTexture.IsValid())
                return;

            var renderingData = frameData.Get<UniversalRenderingData>();
            var cameraData = frameData.Get<UniversalCameraData>();
            var lightData = frameData.Get<UniversalLightData>();

            // Draw only opaque renderers on the Inside Card layer.
            var filter = new FilteringSettings(
                RenderQueueRange.opaque, layerMask.value);

            var draw = RenderingUtils.CreateDrawingSettings(
                new ShaderTagId("UniversalForward"),
                renderingData,
                cameraData,
                lightData,
                cameraData.defaultOpaqueSortFlags);

            // Include common URP shader pass names, including Shader Graph.
            draw.SetShaderPassName(1, new ShaderTagId("UniversalForwardOnly"));
            draw.SetShaderPassName(2, new ShaderTagId("SRPDefaultUnlit"));
            draw.SetShaderPassName(3, new ShaderTagId("LightweightForward"));
            draw.SetShaderPassName(4, new ShaderTagId("UniversalGBuffer"));

            // Force the dedicated shader that has:
            // ColorMask 0, ZWrite On, ZTest LEqual, Stencil Equal 8.
            draw.overrideMaterial = depthMaterial;
            draw.overrideMaterialPassIndex = 0;

            var listParams = new RendererListParams(
                renderingData.cullResults, draw, filter);

            using (var builder = renderGraph.AddRasterRenderPass<PassData>(
                "Inside Card - Stencil Masked Camera Depth", out var passData))
            {
                passData.rendererList = renderGraph.CreateRendererList(listParams);
                builder.UseRendererList(passData.rendererList);

                // Bind the live camera depth/stencil texture, NOT a temporary depth copy.
                // Preserve the existing depth AND stencil; modify only passing pixels.
                builder.SetRenderAttachmentDepth(
                    resources.activeDepthTexture, AccessFlags.ReadWrite);

                // Bind current camera color to use the same attachment configuration;
                // ColorMask 0 in the override shader prevents color modifications.
                builder.SetRenderAttachment(
                    resources.activeColorTexture, 0, AccessFlags.ReadWrite);

                // Keep the debugging pass even when RenderGraph cannot infer a consumer.
                builder.AllowPassCulling(false);

                builder.SetRenderFunc(static (PassData data, RasterGraphContext ctx) =>
                {
                    // Do NOT clear either attachment here.
                    ctx.cmd.DrawRendererList(data.rendererList);
                });
            }
        }
    }

    public override void Create()
    {
        pass = new StencilDepthPass();
        pass.renderPassEvent = settings.passEvent;
        pass.depthMaterial = settings.depthOnlyMaterial;
        pass.layerMask = settings.insideCardLayer;
    }

    public override void AddRenderPasses(
        ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (pass == null || settings.depthOnlyMaterial == null)
            return;

        pass.renderPassEvent = settings.passEvent;
        pass.depthMaterial = settings.depthOnlyMaterial;
        pass.layerMask = settings.insideCardLayer;
        renderer.EnqueuePass(pass);
    }
}
