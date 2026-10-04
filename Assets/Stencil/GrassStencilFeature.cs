using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;
using GrassTool;

public class GrassStencilFeature : ScriptableRendererFeature
{
    private class GrassPass : ScriptableRenderPass
    {
        private Material compositeMaterial;
        private LayerMask grassLayerMask;

        // ============================================================
        // PASS DATA
        // ============================================================

        private class DepthCopyData
        {
            public TextureHandle source;
            public TextureHandle destination;
        }

        private class GrassDrawData
        {
        }

        private class GrassBlitData
        {
            public Material compositeMaterial;
            public TextureHandle srcTexture;
            public int materialPass;
        }

        // ============================================================
        // SETUP
        // ============================================================

        public GrassPass(
            Material compositeMaterial,
            LayerMask grassLayerMask)
        {
            this.compositeMaterial = compositeMaterial;
            this.grassLayerMask = grassLayerMask;
        }

        public void Setup(
            Material material,
            LayerMask layerMask)
        {
            compositeMaterial = material;
            grassLayerMask = layerMask;
        }

        // ============================================================
        // HELPERS
        // ============================================================

        private bool HasGrassToRender()
        {
            foreach (GrassInstancer instancer
                     in GrassInstancer.ActiveInstancers)
            {
                if (instancer == null)
                    continue;

                if (!instancer.HasRenderableInstances)
                    continue;

                if (!instancer.IsInLayerMask(grassLayerMask))
                    continue;

                return true;
            }

            return false;
        }

        // ============================================================
        // RENDER GRAPH
        // ============================================================

        public override void RecordRenderGraph(
            RenderGraph renderGraph,
            ContextContainer frameData)
        {
            if (compositeMaterial == null)
                return;

            if (!HasGrassToRender())
                return;

            UniversalResourceData resourceData =
                frameData.Get<UniversalResourceData>();

            UniversalCameraData cameraData =
                frameData.Get<UniversalCameraData>();


            // ========================================================
            // CREATE TEMP COLOR
            // ========================================================

            RenderTextureDescriptor colorDescriptor =
                cameraData.cameraTargetDescriptor;

            colorDescriptor.depthBufferBits = 0;

            // Must contain alpha because alpha == 0 means
            // "no grass rendered here."
            colorDescriptor.graphicsFormat =
                GraphicsFormat.R16G16B16A16_SFloat;

            colorDescriptor.bindMS = false;
            colorDescriptor.useMipMap = false;
            colorDescriptor.autoGenerateMips = false;

            TextureHandle tempColorTarget =
                UniversalRenderer.CreateRenderGraphTexture(
                    renderGraph,
                    colorDescriptor,
                    "_GrassTempColor",
                    false);


            // ========================================================
            // CREATE TEMP DEPTH
            //
            // IMPORTANT:
            // Clone the ACTUAL active camera depth target.
            //
            // This gives us matching:
            // - width / height
            // - depth format
            // - MSAA
            // - XR dimensions
            // ========================================================

            TextureDesc depthDescriptor =
                resourceData.activeDepthTexture.GetDescriptor(renderGraph);

            depthDescriptor.name = "_GrassTempDepth";
            depthDescriptor.clearBuffer = false;

            TextureHandle tempDepthTarget =
                renderGraph.CreateTexture(depthDescriptor);


            // ========================================================
            // PASS 0
            //
            // CAMERA DEPTH -> TEMP DEPTH
            //
            // Temp depth needs to begin containing the scene depth.
            //
            // Then grass can depth-test against terrain/buildings AND
            // write its own depth into the temporary depth target.
            // ========================================================

            using (
                var builder =
                    renderGraph.AddUnsafePass<DepthCopyData>(
                        "Grass - Copy Camera Depth",
                        out var passData))
            {
                passData.source =
                    resourceData.activeDepthTexture;

                passData.destination =
                    tempDepthTarget;

                builder.UseTexture(
                    passData.source,
                    AccessFlags.Read);

                builder.UseTexture(
                    passData.destination,
                    AccessFlags.Write);

                builder.SetRenderFunc(
                    (DepthCopyData data,
                     UnsafeGraphContext context) =>
                    {
                        CommandBuffer cmd =
                            CommandBufferHelpers
                                .GetNativeCommandBuffer(context.cmd);

                        // Whole-texture copy.
                        cmd.CopyTexture(
                            data.source,
                            data.destination);
                    });
            }


            // ========================================================
            // PASS 1
            //
            // DRAW GRASS INTO:
            //
            // COLOR -> TempColor
            // DEPTH -> TempDepth
            //
            // TempDepth already contains scene depth.
            //
            // The grass therefore:
            // 1. depth-tests against the scene
            // 2. writes its own depth
            //
            // But CAMERA DEPTH remains untouched!
            // ========================================================

            using (
                var builder =
                    renderGraph.AddRasterRenderPass<GrassDrawData>(
                        "Grass - Draw Color And Depth",
                        out var passData))
            {
                builder.SetRenderAttachment(
                    tempColorTarget,
                    0,
                    AccessFlags.Write);


                // IMPORTANT CHANGE:
                //
                // This is now TEMP depth, not camera depth.
                //
                // ReadWrite:
                // READ  -> depth-test against existing scene
                // WRITE -> write grass depth
                builder.SetRenderAttachmentDepth(
                    tempDepthTarget,
                    AccessFlags.ReadWrite);


                builder.SetRenderFunc(
                    (GrassDrawData data,
                     RasterGraphContext context) =>
                    {
                        // Clear ONLY color.
                        //
                        // DO NOT clear temp depth because it contains
                        // our copied scene depth.
                        context.cmd.ClearRenderTarget(
                            RTClearFlags.Color,
                            Color.clear,
                            1.0f,
                            0);


                        foreach (
                            GrassInstancer instancer
                            in GrassInstancer.ActiveInstancers)
                        {
                            if (instancer == null)
                                continue;

                            if (!instancer.IsInLayerMask(
                                    grassLayerMask))
                            {
                                continue;
                            }

                            if (!instancer.HasRenderableInstances)
                                continue;


                            for (
                                int i = 0;
                                i < instancer.BatchCount;
                                i++)
                            {
                                int count =
                                    instancer
                                        .GetBatchInstanceCount(i);

                                if (count <= 0)
                                    continue;

                                Matrix4x4[] matrices =
                                    instancer
                                        .GetBatchMatrices(i);


                                context.cmd.DrawMeshInstanced(
                                    instancer.grassMesh,
                                    0,
                                    instancer.grassMaterial,

                                    // Forward Shader Graph pass.
                                    0,

                                    matrices,
                                    count);
                            }
                        }
                    });
            }


            // ========================================================
            // PASS 2
            //
            // STENCIL-COMPOSITE GRASS COLOR
            //
            // Stencil == 8:
            //     TempColor -> CameraColor
            //
            // Stencil != 8:
            //     CameraColor unchanged
            // ========================================================

            using (
                var builder =
                    renderGraph.AddRasterRenderPass<GrassBlitData>(
                        "Grass - Stencil Color Composite",
                        out var passData))
            {
                passData.compositeMaterial =
                    compositeMaterial;

                passData.srcTexture =
                    tempColorTarget;

                // Pass 0 of our composite shader = color.
                passData.materialPass = 0;


                builder.UseTexture(
                    tempColorTarget,
                    AccessFlags.Read);


                builder.SetRenderAttachment(
                    resourceData.activeColorTexture,
                    0,
                    AccessFlags.ReadWrite);


                // Needed because this attachment contains the stencil
                // being tested by the composite shader.
                builder.SetRenderAttachmentDepth(
                    resourceData.activeDepthTexture,
                    AccessFlags.Read);


                builder.SetRenderFunc(
                    (GrassBlitData data,
                     RasterGraphContext context) =>
                    {
                        Blitter.BlitTexture(
                            context.cmd,
                            data.srcTexture,
                            new Vector4(
                                1.0f,
                                1.0f,
                                0.0f,
                                0.0f),
                            data.compositeMaterial,
                            data.materialPass);
                    });
            }


            // ========================================================
            // PASS 3
            //
            // STENCIL-COMPOSITE GRASS DEPTH
            //
            // Stencil == 8:
            //     TempDepth -> CameraDepth
            //
            // Stencil != 8:
            //     CameraDepth unchanged
            //
            // This is the critical new part.
            // ========================================================

            using (
                var builder =
                    renderGraph.AddRasterRenderPass<GrassBlitData>(
                        "Grass - Stencil Depth Composite",
                        out var passData))
            {
                passData.compositeMaterial =
                    compositeMaterial;

                passData.srcTexture =
                    tempDepthTarget;

                // Pass 1 of our composite shader = depth.
                passData.materialPass = 1;


                // Sample temporary depth.
                builder.UseTexture(
                    tempDepthTarget,
                    AccessFlags.Read);


                // READ:
                // stencil test
                //
                // WRITE:
                // write grass depth into camera depth
                builder.SetRenderAttachmentDepth(
                    resourceData.activeDepthTexture,
                    AccessFlags.ReadWrite);


                builder.SetRenderFunc(
                    (GrassBlitData data,
                     RasterGraphContext context) =>
                    {
                        Blitter.BlitTexture(
                            context.cmd,
                            data.srcTexture,
                            new Vector4(
                                1.0f,
                                1.0f,
                                0.0f,
                                0.0f),
                            data.compositeMaterial,
                            data.materialPass);
                    });
            }
        }
    }


    // ================================================================
    // SETTINGS
    // ================================================================

    [System.Serializable]
    public class Settings
    {
        [Header("Grass Selection")]
        public LayerMask grassLayerMask;


        [Header("Stencil Composite")]
        public Material compositeMaterial;


        [Header("Render Timing")]

        // This is before normal transparent rendering, so transparent
        // objects rendered afterward can depth-test against the grass.
        public RenderPassEvent renderPassEvent =
            RenderPassEvent.AfterRenderingOpaques;
    }


    public Settings settings =
        new Settings();

    private GrassPass grassPass;


    // ================================================================
    // CREATE
    // ================================================================

    public override void Create()
    {
        grassPass =
            new GrassPass(
                settings.compositeMaterial,
                settings.grassLayerMask);

        grassPass.renderPassEvent =
            settings.renderPassEvent;
    }


    // ================================================================
    // ENQUEUE
    // ================================================================

    public override void AddRenderPasses(
        ScriptableRenderer renderer,
        ref RenderingData renderingData)
    {
        if (settings.compositeMaterial == null)
            return;

        grassPass.Setup(
            settings.compositeMaterial,
            settings.grassLayerMask);

        grassPass.renderPassEvent =
            settings.renderPassEvent;

        renderer.EnqueuePass(grassPass);
    }
}