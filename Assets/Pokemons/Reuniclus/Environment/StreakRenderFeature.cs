// Unity 6 / URP 17+ Render Graph implementation for StreakURP.shader.
// Replace the previous StreakRenderFeature/CustomPass implementation with this.
// No CustomRenderFeature, CustomPass, PostProcessingGraph, or Volume dependency.
//
// SETUP
// 1. Place this file and StreakURP.shader in Assets (not an Editor folder).
// 2. Add StreakRenderFeature to the active Universal Renderer Data asset.
// 3. Assign StreakURP.shader to Shader. Its name is Hidden/PostProcessing/Streak.
// 4. Leave Compatibility Mode (Render Graph Disabled) OFF in URP settings.
// 5. Adjust the effect directly in this renderer feature's inspector.
//
// Runs before post-processing so HDR highlights are available before tonemapping.
// Runs on the selected BASE camera, before overlay cameras render.
// The composite is copied back into the existing camera color target, preserving
// the color-buffer identity shared with subsequent cameras in the stack.
// Overlay cameras are skipped and do not generate their own streaks.
// Set targetCameraTag to your base camera's tag; empty means all game Base cameras.
// Scene View is controlled separately by showInSceneView.
// In the overlay camera's Culling Mask, include only layers it should draw.
// Opaque overlay geometry still covers underlying streaks where it draws.
// The shader preserves the pasted Kino behavior, including output alpha = 1.
// Unity compilation and scene rendering have not been executed in this environment.

using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

[DisallowMultipleRendererFeature("Kino Streak (Render Graph)")]
public sealed class StreakRenderFeature : ScriptableRendererFeature
{
    [Serializable]
    public sealed class Settings
    {
        public bool enabled = true;
        [Min(0f)] public float threshold = 1f;
        [Range(0f, 1f)] public float stretch = 0.5f;
        [Min(0f)] public float intensity = 0.1f;
        [ColorUsage(false, true)] public Color tint = Color.white;
        public bool showInSceneView = true;

        public string targetCameraTag = "MainCamera";
    }

    [SerializeField, Tooltip("Assign StreakURP.shader to retain the shader in builds.")]
    private Shader shader;
    [SerializeField] private Settings settings = new Settings();

    private Material material;
    private StreakPass pass;

    public override void Create()
    {
        CoreUtils.Destroy(material);
        material = null;
        pass = null;

        // Assign the field explicitly in the renderer asset for player builds.
        if (shader == null)
            shader = Shader.Find("Hidden/PostProcessing/Streak");
        if (shader == null || !shader.isSupported)
            return;

        material = CoreUtils.CreateEngineMaterial(shader);
        if (material.passCount < 4)
        {
            Debug.LogError("StreakRenderFeature requires the four-pass StreakURP.shader.", this);
            CoreUtils.Destroy(material);
            material = null;
            return;
        }

        pass = new StreakPass();
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (pass == null || material == null || settings == null ||
            !settings.enabled || settings.intensity <= 0f)
            return;

        CameraData camera = renderingData.cameraData;

        // resolveFinalTarget identifies the last camera in the stack. A Base
        // camera with overlays normally has this flag false, so do not filter on it.
        if (camera.renderType != CameraRenderType.Base)
            return;

        if (camera.cameraType == CameraType.SceneView)
        {
            if (!settings.showInSceneView)
                return;
        }
        else if (camera.cameraType == CameraType.Game)
        {
            if (!string.IsNullOrEmpty(settings.targetCameraTag) &&
                !camera.camera.CompareTag(settings.targetCameraTag))
                return;
        }
        else
        {
            return; // Skip preview and reflection cameras.
        }

        pass.Setup(material, settings);
        renderer.EnqueuePass(pass);
    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(material);
        material = null;
        pass = null;
        // Render Graph owns all intermediate textures; there are no RTHandles
        // allocated by this feature to release here.
    }

    private sealed class StreakPass : ScriptableRenderPass
    {
        private const int MaxLevels = 16;
        private static readonly int BlitTextureId = Shader.PropertyToID("_BlitTexture");
        private static readonly int BlitTexelSizeId = Shader.PropertyToID("_BlitTexture_TexelSize");
        private static readonly int BlitScaleBiasId = Shader.PropertyToID("_BlitScaleBias");
        private static readonly int HighTextureId = Shader.PropertyToID("_HighTex");
        private static readonly int HighScaleBiasId = Shader.PropertyToID("_HighTexScaleBias");
        private static readonly int ThresholdId = Shader.PropertyToID("_Threshold");
        private static readonly int StretchId = Shader.PropertyToID("_Stretch");
        private static readonly int IntensityId = Shader.PropertyToID("_Intensity");
        private static readonly int TintId = Shader.PropertyToID("_Color");

        private Material material;
        private Parameters parameters;
        private bool warnedAboutBackBuffer;

        private struct Parameters
        {
            public float threshold, stretch, intensity;
            public Color tint;
        }

        // Render Graph pools PassData. Each live graph pass owns a separate
        // property block; it is filled only inside the execution callback.
        private sealed class PassData
        {
            public TextureHandle source;
            public TextureHandle high;
            public bool hasHigh;
            public Material material;
            public int shaderPass;
            public Parameters parameters;
            public readonly MaterialPropertyBlock properties = new MaterialPropertyBlock();
        }

        private sealed class CopyBackData
        {
            public TextureHandle source;
        }

        public StreakPass()
        {
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
            // We sample camera color, so a directly rendered backbuffer is invalid.
            requiresIntermediateTexture = true;
        }

        public void Setup(Material effectMaterial, Settings settings)
        {
            material = effectMaterial;
            parameters = new Parameters
            {
                threshold = Mathf.Max(0f, settings.threshold),
                stretch = Mathf.Clamp01(settings.stretch),
                intensity = Mathf.Max(0f, settings.intensity),
                tint = settings.tint
            };
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalResourceData resources = frameData.Get<UniversalResourceData>();
            UniversalCameraData camera = frameData.Get<UniversalCameraData>();
            if (camera.renderType != CameraRenderType.Base ||
                material == null || parameters.intensity <= 0f)
                return;

            // Normally prevented by requiresIntermediateTexture. Keep a guard for
            // unusual renderers, instead of trying to sample the swapchain image.
            if (resources.isActiveTargetBackBuffer)
            {
                if (!warnedAboutBackBuffer)
                {
                    Debug.LogWarning("Streak needs a sampleable camera color texture. " +
                        "Set the Universal Renderer Intermediate Texture setting to Always.");
                    warnedAboutBackBuffer = true;
                }
                return;
            }

            TextureHandle source = resources.activeColorTexture;
            if (!source.IsValid())
                return;

            TextureDesc sourceDesc = renderGraph.GetTextureDesc(source);
            int fullWidth = Mathf.Max(1, camera.cameraTargetDescriptor.width);
            int fullHeight = Mathf.Max(1, camera.cameraTargetDescriptor.height);
            int height = Mathf.Max(1, fullHeight / 2);
            int width = fullWidth;

            // These handles belong only to this graph recording, never another frame.
            var levels = new TextureHandle[MaxLevels];
            var widths = new int[MaxLevels];
            widths[0] = width;
            levels[0] = CreateColor(renderGraph, sourceDesc, width, height,
                GraphicsFormat.R16G16B16A16_SFloat, "Streak / Prefilter");
            AddStage(renderGraph, "Streak / Prefilter", source, levels[0], 0);

            int count = 1;
            while (count < MaxLevels && width / 2 > 7)
            {
                width /= 2;
                widths[count] = width;
                levels[count] = CreateColor(renderGraph, sourceDesc, width, height,
                    GraphicsFormat.R16G16B16A16_SFloat, "Streak / Down " + count);
                AddStage(renderGraph, "Streak / Down " + count,
                    levels[count - 1], levels[count], 1);
                count++;
            }

            TextureHandle last = levels[count - 1];
            for (int i = count - 2; i >= 1; i--)
            {
                TextureHandle up = CreateColor(renderGraph, sourceDesc, widths[i], height,
                    GraphicsFormat.R16G16B16A16_SFloat, "Streak / Up " + i);
                AddStage(renderGraph, "Streak / Up " + i, last, up, 2, levels[i]);
                last = up;
            }

            TextureHandle output = CreateColor(renderGraph, sourceDesc, fullWidth, fullHeight,
                sourceDesc.colorFormat, "Streak / Composite");
            AddStage(renderGraph, "Streak / Composite", last, output, 3, source);

            // Preserve the original camera-stack target. Replacing cameraColor
            // with a transient texture is a local frame-data change; it does not
            // reliably replace the backing target inherited by the next camera.
            // Composite used source as an input, so copy back in a SEPARATE pass.
            CopyBackToCamera(renderGraph, output, source);
        }

        private static void CopyBackToCamera(RenderGraph graph,
            TextureHandle composite, TextureHandle cameraColor)
        {
            using (var builder = graph.AddRasterRenderPass<CopyBackData>(
                "Streak / Copy Back To Base Camera", out var data))
            {
                data.source = composite;
                builder.UseTexture(composite, AccessFlags.Read);
                builder.SetRenderAttachment(cameraColor, 0, AccessFlags.Write);
                // This write also serves later cameras outside this camera's graph.
                builder.AllowPassCulling(false);
                builder.SetRenderFunc(static (CopyBackData passData, RasterGraphContext context) =>
                {
                    RTHandle input = passData.source;
                    Blitter.BlitTexture(context.cmd, input, GetScaleBias(input), 0f, true);
                });
            }
        }

        private static TextureHandle CreateColor(RenderGraph graph, TextureDesc template,
            int width, int height, GraphicsFormat format, string name)
        {
            // Preserve camera texture dimension/slices (including XR arrays).
            // Explicit sizes already use camera render resolution; do not apply
            // dynamic scaling again to this owned pyramid.
            template.name = name;
            template.sizeMode = TextureSizeMode.Explicit;
            template.width = width;
            template.height = height;
            template.colorFormat = format;
            template.depthBufferBits = DepthBits.None;
            template.msaaSamples = MSAASamples.None;
            template.bindTextureMS = false;
            template.useMipMap = false;
            template.autoGenerateMips = false;
            template.enableRandomWrite = false;
            template.useDynamicScale = false;
            template.useDynamicScaleExplicit = false;
            template.clearBuffer = false;
            template.filterMode = FilterMode.Bilinear;
            template.wrapMode = TextureWrapMode.Clamp;
            return graph.CreateTexture(template);
        }

        private void AddStage(RenderGraph graph, string name, TextureHandle source,
            TextureHandle destination, int shaderPass, TextureHandle high = default)
        {
            using (var builder = graph.AddRasterRenderPass<PassData>(name, out var data))
            {
                data.source = source;
                data.high = high;
                data.hasHigh = high.IsValid();
                data.material = material;
                data.shaderPass = shaderPass;
                data.parameters = parameters; // Value copy, not live shared settings.

                builder.UseTexture(source, AccessFlags.Read);
                if (data.hasHigh)
                    builder.UseTexture(high, AccessFlags.Read);
                builder.SetRenderAttachment(destination, 0, AccessFlags.Write);
                builder.SetRenderFunc(static (PassData passData, RasterGraphContext context) =>
                    ExecuteStage(passData, context));
            }
        }

        private static Vector4 GetScaleBias(RTHandle texture)
        {
            if (texture.useScaling)
            {
                Vector4 scale = texture.rtHandleProperties.rtHandleScale;
                return new Vector4(scale.x, scale.y, 0f, 0f);
            }
            return new Vector4(1f, 1f, 0f, 0f);
        }

        private static void ExecuteStage(PassData data, RasterGraphContext context)
        {
            // Handles can be resolved to physical textures here, after graph
            // allocation. Doing this during RecordRenderGraph would be too early.
            RTHandle source = data.source;
            RenderTexture sourceTexture = source.rt;
            MaterialPropertyBlock props = data.properties;
            props.Clear();
            props.SetTexture(BlitTextureId, sourceTexture);
            props.SetVector(BlitTexelSizeId, new Vector4(
                1f / sourceTexture.width, 1f / sourceTexture.height,
                sourceTexture.width, sourceTexture.height));
            props.SetVector(BlitScaleBiasId, GetScaleBias(source));
            props.SetFloat(ThresholdId, data.parameters.threshold);
            props.SetFloat(StretchId, data.parameters.stretch);
            props.SetFloat(IntensityId, data.parameters.intensity);
            props.SetColor(TintId, data.parameters.tint);

            if (data.hasHigh)
            {
                RTHandle high = data.high;
                props.SetTexture(HighTextureId, high.rt);
                props.SetVector(HighScaleBiasId, GetScaleBias(high));
            }

            // Fullscreen triangle using the shader's Blit.hlsl-based vertex stage.
            // A property block carries BOTH inputs, without shared material/global
            // texture mutations or unsafe render passes. RG sets target/viewport.
            context.cmd.DrawProcedural(Matrix4x4.identity, data.material,
                data.shaderPass, MeshTopology.Triangles, 3, 1, props);
        }
    }
}
