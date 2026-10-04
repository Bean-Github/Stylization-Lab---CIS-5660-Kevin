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

        private class ColorCopyData
        {
            public TextureHandle source;
        }

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

                // Normal rendering and stencil rendering
                // must be mutually exclusive.
                if (instancer.renderNormally)
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

            // HDR target.
            //
            // Important for preserving:
            // - lighting above 1.0
            // - emission
            // - bloom-producing HDR values
            // - alpha
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
            // ========================================================

            // Clone the actual camera depth target so format,
            // dimensions, MSAA and XR properties match.
            TextureDesc depthDescriptor =
                resourceData.activeDepthTexture.GetDescriptor(
                    renderGraph);

            depthDescriptor.name =
                "_GrassTempDepth";

            depthDescriptor.clearBuffer =
                false;


            TextureHandle tempDepthTarget =
                renderGraph.CreateTexture(
                    depthDescriptor);


            // ========================================================
            // PASS 0
            //
            // CAMERA COLOR -> TEMP COLOR
            //
            // THIS IS THE IMPORTANT NEW PASS.
            //
            // Instead of starting TempColor transparent, it starts
            // as an exact copy of the current rendered scene.
            // ========================================================

            using (
                var builder =
                    renderGraph.AddRasterRenderPass<ColorCopyData>(
                        "Grass - Copy Camera Color",
                        out var passData))
            {
                passData.source =
                    resourceData.activeColorTexture;


                builder.UseTexture(
                    passData.source,
                    AccessFlags.Read);


                builder.SetRenderAttachment(
                    tempColorTarget,
                    0,
                    AccessFlags.WriteAll);


                builder.SetRenderFunc(
                    (ColorCopyData data,
                     RasterGraphContext context) =>
                    {
                        Blitter.BlitTexture(
                            context.cmd,
                            data.source,
                            new Vector4(
                                1.0f,
                                1.0f,
                                0.0f,
                                0.0f),
                            0.0f,
                            false);
                    });
            }


            // ========================================================
            // PASS 1
            //
            // CAMERA DEPTH -> TEMP DEPTH
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
                                .GetNativeCommandBuffer(
                                    context.cmd);

                        cmd.CopyTexture(
                            data.source,
                            data.destination);
                    });
            }


            // ========================================================
            // PASS 2
            //
            // DRAW GRASS INTO COPIED CAMERA IMAGE
            //
            //
            // BEFORE:
            //
            // Transparent black
            //       ↓
            // grass alpha blend
            //       ↓
            // TempColor
            //
            //
            // NOW:
            //
            // CameraColor
            //       ↓
            // grass alpha blend ONCE
            //       ↓
            // TempColor
            //
            //
            // This makes transparent/emissive grass behave much more
            // like it does during normal rendering.
            // ========================================================

            using (
                var builder =
                    renderGraph.AddRasterRenderPass<GrassDrawData>(
                        "Grass - Draw Color And Depth",
                        out var passData))
            {
                // IMPORTANT:
                //
                // ReadWrite rather than Write.
                //
                // The destination already contains CameraColor,
                // and transparent grass blending needs to preserve/read
                // that existing destination.
                builder.SetRenderAttachment(
                    tempColorTarget,
                    0,
                    AccessFlags.ReadWrite);


                // TempDepth already contains camera scene depth.
                //
                // Grass can now:
                // - test against scene depth
                // - write its own depth
                //
                // without modifying CameraDepth yet.
                builder.SetRenderAttachmentDepth(
                    tempDepthTarget,
                    AccessFlags.ReadWrite);


                builder.SetRenderFunc(
                    (GrassDrawData data,
                     RasterGraphContext context) =>
                    {
                        // =================================================
                        // IMPORTANT:
                        //
                        // DO NOT CLEAR COLOR HERE.
                        //
                        // TempColor already contains CameraColor.
                        // =================================================


                        foreach (
                            GrassInstancer instancer
                            in GrassInstancer.ActiveInstancers)
                        {
                            if (instancer == null)
                                continue;


                            // Normal rendering and stencil rendering
                            // are mutually exclusive.
                            if (instancer.renderNormally)
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
            // PASS 3
            //
            // STENCIL COLOR COMPOSITE
            //
            //
            // TempColor already contains:
            //
            //     Original CameraColor
            //             +
            //     correctly blended grass
            //
            // Therefore this is a straight COPY.
            //
            // The shader uses:
            //
            //     Blend One Zero
            //
            // NOT SrcAlpha OneMinusSrcAlpha.
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

                passData.materialPass =
                    0;


                builder.UseTexture(
                    tempColorTarget,
                    AccessFlags.Read);


                // ReadWrite is important even though the shader itself
                // uses Blend One Zero.
                //
                // Pixels that FAIL stencil must preserve the existing
                // camera image.
                builder.SetRenderAttachment(
                    resourceData.activeColorTexture,
                    0,
                    AccessFlags.ReadWrite);


                // Supplies stencil buffer for:
                //
                // Stencil
                // {
                //     Ref 8
                //     ReadMask 8
                //     Comp Equal
                // }
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
            // PASS 4
            //
            // STENCIL DEPTH COMPOSITE
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

                passData.materialPass =
                    1;


                builder.UseTexture(
                    tempDepthTarget,
                    AccessFlags.Read);


                // Preserve depth outside the stencil while replacing
                // depth inside the accepted stencil region.
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


        renderer.EnqueuePass(
            grassPass);
    }
}