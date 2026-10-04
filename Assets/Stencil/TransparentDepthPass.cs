using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class TransparentDepthFeature : ScriptableRendererFeature
{
    class TransparentDepthPass : ScriptableRenderPass
    {
        // A struct to hold the resources our pass needs to read and write
        private class PassData
        {
            public TextureHandle sourceDepth;
            public TextureHandle destDepth;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            // Retrieve the resource data which holds all the active textures for this frame
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();

            TextureHandle srcDepth = resourceData.activeDepthTexture;
            TextureHandle dstDepth = resourceData.cameraDepthTexture;

            // Ensure both textures actually exist this frame before scheduling the pass
            if (!srcDepth.IsValid() || !dstDepth.IsValid())
                return;

            // Schedule an UnsafePass since cmd.CopyTexture is a low-level graphics operation
            using (var builder = renderGraph.AddUnsafePass<PassData>("Update Camera Depth", out var passData))
            {
                passData.sourceDepth = srcDepth;
                passData.destDepth = dstDepth;

                // Declare our dependencies to the Render Graph for automatic optimization
                builder.UseTexture(passData.sourceDepth, AccessFlags.Read);
                builder.UseTexture(passData.destDepth, AccessFlags.Write);

                builder.SetRenderFunc((PassData data, UnsafeGraphContext context) =>
                {
                    // Retrieve the underlying native CommandBuffer
                    CommandBuffer cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);

                    // Copy the hardware depth buffer (which now contains transparents) into the global URP texture
                    cmd.CopyTexture(data.sourceDepth, data.destDepth);
                });
            }
        }
    }

    TransparentDepthPass m_Pass;

    public override void Create()
    {
        m_Pass = new TransparentDepthPass();

        // Ensure this executes after all transparent objects are drawn
        m_Pass.renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_Pass);
    }
}