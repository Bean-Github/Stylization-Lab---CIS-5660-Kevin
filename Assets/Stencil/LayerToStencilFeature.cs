using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

public class LayerToStencilFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        // FIX 1: Changed default to AFTER opaques so the walls exist in the depth buffer
        [Tooltip("When should this stencil be written?")]
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingOpaques;

        [Tooltip("Which layers should be drawn to the stencil?")]
        public LayerMask layerMask = -1;

        [Tooltip("The integer to write to the stencil buffer (0-255).")]
        [Range(0, 255)] public int stencilValue = 1;
    }

    public Settings settings = new Settings();
    private LayerToStencilPass m_Pass;

    public override void Create()
    {
        m_Pass = new LayerToStencilPass(settings);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (settings.layerMask == 0) return;
        renderer.EnqueuePass(m_Pass);
    }

    class LayerToStencilPass : ScriptableRenderPass
    {
        private Settings m_Settings;
        private List<ShaderTagId> m_ShaderTagIds = new List<ShaderTagId>();

        public LayerToStencilPass(Settings settings)
        {
            m_Settings = settings;
            renderPassEvent = settings.renderPassEvent;

            // Include all standard URP shader passes so we catch Lit, Unlit, and Custom materials
            m_ShaderTagIds.Add(new ShaderTagId("UniversalForward"));
            m_ShaderTagIds.Add(new ShaderTagId("UniversalForwardOnly"));
            m_ShaderTagIds.Add(new ShaderTagId("LightweightForward"));
            m_ShaderTagIds.Add(new ShaderTagId("SRPDefaultUnlit"));
        }

        private class PassData
        {
            public RendererListHandle rendererList;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var resourceData = frameData.Get<UniversalResourceData>();
            var renderingData = frameData.Get<UniversalRenderingData>();
            var cameraData = frameData.Get<UniversalCameraData>();

            if (!resourceData.activeColorTexture.IsValid() || !resourceData.activeDepthTexture.IsValid())
                return;

            using (var builder = renderGraph.AddRasterRenderPass<PassData>("LayerToStencilPass", out var passData))
            {
                RenderStateBlock stateBlock = new RenderStateBlock(RenderStateMask.Stencil | RenderStateMask.Depth | RenderStateMask.Blend);

                // Disable Colors
                BlendState blendState = BlendState.defaultValue;
                RenderTargetBlendState rtBlendState = blendState.blendState0;
                rtBlendState.writeMask = (ColorWriteMask)0;
                blendState.blendState0 = rtBlendState;
                stateBlock.blendState = blendState;

                // FIX 2: Explicitly enforce depth checking so walls block the stencil
                DepthState depthState = DepthState.defaultValue;
                depthState.writeEnabled = false;
                depthState.compareFunction = CompareFunction.LessEqual;
                stateBlock.depthState = depthState;

                // Force Stencil Write 
                StencilState stencilState = StencilState.defaultValue;
                stencilState.enabled = true;
                stencilState.SetCompareFunction(CompareFunction.Always);
                stencilState.SetPassOperation(StencilOp.Replace);
                stateBlock.stencilState = stencilState;
                stateBlock.stencilReference = m_Settings.stencilValue;

                var renderListDesc = new UnityEngine.Rendering.RendererUtils.RendererListDesc(m_ShaderTagIds.ToArray(), renderingData.cullResults, cameraData.camera)
                {
                    sortingCriteria = cameraData.defaultOpaqueSortFlags,
                    renderQueueRange = RenderQueueRange.all,
                    layerMask = m_Settings.layerMask.value,
                    stateBlock = stateBlock
                };

                passData.rendererList = renderGraph.CreateRendererList(renderListDesc);
                builder.UseRendererList(passData.rendererList);

                // Bind the active camera textures
                builder.SetRenderAttachment(resourceData.activeColorTexture, 0, AccessFlags.Write);
                builder.SetRenderAttachmentDepth(resourceData.activeDepthTexture, AccessFlags.Write);

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    context.cmd.DrawRendererList(data.rendererList);
                });
            }
        }
    }
}