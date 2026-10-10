using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RendererUtils;
using UnityEngine.Rendering.Universal;

/// <summary>
/// OPTIONAL. Use this feature ONLY when water is drawn via a custom URP pass.
/// For normally-rendered transparent water, just use the stencil water shader.
///
/// Setup:
/// - Put water renderers on a dedicated WaterStencil layer.
/// - Exclude that layer from the Universal Renderer Transparent Layer Mask
///   so URP does not draw the water a second time.
/// - Set waterLayerMask here to include WaterStencil.
/// - Keep your stencil writer running before this pass.
/// - Enable Opaque Texture + Depth Texture in URP.
/// - Use the material with Custom/ThickRefractiveWaterCurvedStencil.
/// </summary>
public class StencilWaterRenderFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public LayerMask waterLayerMask;
        public RenderPassEvent renderPassEvent = RenderPassEvent.BeforeRenderingTransparents;
    }

    public Settings settings = new Settings();

    private WaterPass waterPass;

    public override void Create()
    {
        waterPass = new WaterPass();
        waterPass.renderPassEvent = settings.renderPassEvent;
        // Ensure the camera provides the opaque color/depth copies sampled
        // by SampleSceneColor and SampleSceneDepth in the water material.
        waterPass.ConfigureInput(
            ScriptableRenderPassInput.Color | ScriptableRenderPassInput.Depth);
    }

    public override void AddRenderPasses(
        ScriptableRenderer renderer,
        ref RenderingData renderingData)
    {
        if (settings.waterLayerMask.value == 0)
            return;

        waterPass.layerMask = settings.waterLayerMask;
        waterPass.renderPassEvent = settings.renderPassEvent;
        renderer.EnqueuePass(waterPass);
    }

    private sealed class WaterPass : ScriptableRenderPass
    {
        public LayerMask layerMask;

        private sealed class PassData
        {
            public RendererListHandle rendererList;
        }

        public override void RecordRenderGraph(
            RenderGraph renderGraph,
            ContextContainer frameData)
        {
            UniversalResourceData resources =
                frameData.Get<UniversalResourceData>();
            UniversalRenderingData renderingData =
                frameData.Get<UniversalRenderingData>();
            UniversalCameraData cameraData =
                frameData.Get<UniversalCameraData>();
            UniversalLightData lightData =
                frameData.Get<UniversalLightData>();

            // The water material uses a transparent URP forward pass.
            FilteringSettings filtering = new FilteringSettings(
                RenderQueueRange.transparent, layerMask);

            DrawingSettings drawing = RenderingUtils.CreateDrawingSettings(
                new ShaderTagId("UniversalForward"),
                renderingData,
                cameraData,
                lightData,
                SortingCriteria.CommonTransparent);

            RendererListParams rendererListParams = new RendererListParams(
                renderingData.cullResults, drawing, filtering);

            RendererListHandle rendererList =
                renderGraph.CreateRendererList(rendererListParams);

            using (var builder = renderGraph.AddRasterRenderPass<PassData>(
                "Water - Draw Through Camera Stencil", out var data))
            {
                data.rendererList = rendererList;
                builder.UseRendererList(data.rendererList);

                // Declare the sample inputs used by the water shader.
                // These are NOT the active hardware depth/stencil attachment.
                if (resources.cameraOpaqueTexture.IsValid())
                    builder.UseTexture(resources.cameraOpaqueTexture, AccessFlags.Read);
                if (resources.cameraDepthTexture.IsValid())
                    builder.UseTexture(resources.cameraDepthTexture, AccessFlags.Read);

                // Preserve the current camera image outside the water geometry.
                builder.SetRenderAttachment(
                    resources.activeColorTexture, 0, AccessFlags.ReadWrite);

                // STENCIL TEST IS PERFORMED AGAINST THIS ATTACHMENT.
                // The material has ZWrite Off, and all stencil ops are Keep.
                builder.SetRenderAttachmentDepth(
                    resources.activeDepthTexture, AccessFlags.Read);

                builder.SetRenderFunc(static (PassData passData,
                    RasterGraphContext context) =>
                {
                    context.cmd.DrawRendererList(passData.rendererList);
                });
            }
        }
    }
}
