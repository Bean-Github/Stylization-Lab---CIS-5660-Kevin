using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

public class StencilWriterFeature : ScriptableRendererFeature
{
    public Material stencilMaterial;
    public RenderPassEvent renderEvent = RenderPassEvent.BeforeRenderingOpaques;

    private StencilPass m_Pass;

    public override void Create()
    {
        if (stencilMaterial != null)
            m_Pass = new StencilPass(stencilMaterial) { renderPassEvent = renderEvent };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (stencilMaterial != null && m_Pass != null)
            renderer.EnqueuePass(m_Pass);
    }

    class StencilPass : ScriptableRenderPass
    {
        private Material m_Material;
        public StencilPass(Material material) { m_Material = material; }

        private class PassData { public Material material; }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var resourceData = frameData.Get<UniversalResourceData>();

            // Abort if camera hasn't initialized textures yet
            if (!resourceData.activeColorTexture.IsValid() || !resourceData.activeDepthTexture.IsValid())
                return;

            using (var builder = renderGraph.AddRasterRenderPass<PassData>("StencilWriterPass", out var passData))
            {
                passData.material = m_Material;

                // THE FIX: We explicitly bind BOTH the Color buffer and the Depth/Stencil buffer!
                builder.SetRenderAttachment(resourceData.activeColorTexture, 0, AccessFlags.Write);
                builder.SetRenderAttachmentDepth(resourceData.activeDepthTexture, AccessFlags.Write);

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    // Draw a full-screen triangle. 
                    // This perfectly matches the `Blit.hlsl` vertex shader you are using!
                    context.cmd.DrawProcedural(Matrix4x4.identity, data.material, 0, MeshTopology.Triangles, 3, 1);
                });
            }
        }
    }
}