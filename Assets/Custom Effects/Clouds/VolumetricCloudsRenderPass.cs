using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;

public class VolumetricCloudsRenderPassFeature : ScriptableRendererFeature
{
    class VolumetricCloudsPass : ScriptableRenderPass
    {
        const string m_PassName = "VolumetricFogPass";
        Material m_Material;
        VolumetricCloudsSettings m_Settings;

        public void Setup(Material mat, VolumetricCloudsSettings settings)
        {
            m_Material = mat;
            m_Settings = settings;
            requiresIntermediateTexture = true;
        }


        private void UpdateMaterialProperties(ContextContainer frameData)
        {
            if (m_Material == null || m_Settings == null) return;

            // 1. Fetch Camera Data
            var cameraData = frameData.Get<UniversalCameraData>();
            var camera = cameraData.camera;

            // 2. Calculate Bounds (replacing the old Container Transform)
            Vector3 center = m_Settings.boundsCenter;
            Vector3 size = m_Settings.boundsSize;
            Vector3 boundsMin = center - size / 2f;
            Vector3 boundsMax = center + size / 2f;

            m_Material.SetFloat("NearPlane", camera.nearClipPlane);
            m_Material.SetFloat("FarPlane", camera.farClipPlane);

            m_Material.SetVector("BoundsMin", boundsMin);
            m_Material.SetVector("BoundsMax", boundsMax);

            // 3. Set Textures and Basic Properties
            //if (m_Settings.cloudTex != null)
            //    m_Material.SetTexture("ShapeNoise", m_Settings.cloudTex);

            // Calculate scale logic to match original script's aspect ratio compensation
            // (Assumes size.y and size.z are not zero)
            Vector3 computedScale = new Vector3(size.x, m_Settings.cloudScale / size.y, m_Settings.cloudScale / size.z);

            m_Material.SetFloat("CloudScale", m_Settings.cloudScale);

            // Handle Animation (Move Speed)
            // We add the offset to the speed * time
            Vector3 animatedOffset = m_Settings.cloudOffset + (m_Settings.moveSpeed * Time.time);
            m_Material.SetVector("CloudOffset", animatedOffset);

            // 4. Set Volume Properties
            m_Material.SetFloat("DensityMultiplier", m_Settings.densityMultiplier);

            // Add the subtle sine wave animation from the original script to density threshold
            float animatedDensity = m_Settings.densityThreshold + Mathf.Sin(Time.time) * 0.000001f;
            m_Material.SetFloat("DensityThreshold", animatedDensity);

            m_Material.SetFloat("Absorption", m_Settings.absorption);
            m_Material.SetFloat("AbsorptionThreshold", m_Settings.absorptionThreshold);
            m_Material.SetFloat("TransmittanceContrast", m_Settings.transmittanceContrast);

            m_Material.SetInt("NumSteps", m_Settings.numSteps);
            m_Material.SetInt("NumLightSteps", m_Settings.numLightSteps);
            m_Material.SetFloat("SampleLightDistance", m_Settings.sampleLightDist);

            m_Material.SetColor("CloudColor", m_Settings.cloudColor);

            // 5. Set Lighting/HG Properties
            m_Material.SetFloat("HGBias", m_Settings.harveyGreensteinBias);
            m_Material.SetFloat("HGThreshold", m_Settings.harveyGreensteinThreshold);
            m_Material.SetFloat("HGDualLobStrength", m_Settings.harveyGreensteinDualLobStrength);
            m_Material.SetFloat("Diffusion", m_Settings.diffusion);
            m_Material.SetColor("DiffusionColor", m_Settings.diffusionColor);

            // 6. Set Matrices (Standard URP Blit setup usually handles view/proj, 
            // but we provide inverses if the shader relies on raymarching from screen space)
            Matrix4x4 proj = camera.projectionMatrix;
            Matrix4x4 view = camera.worldToCameraMatrix;
            Matrix4x4 viewProj = proj * view;

            m_Material.SetMatrix("_CameraInvProjection", proj.inverse);
            m_Material.SetMatrix("_CameraProjection", proj);
            //m_Material.SetMatrix("_CameraToWorld", camera.cameraToWorldMatrix); // Enable if shader needs it
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            // Only render if material is valid
            if (m_Material == null) return;

            var resourceData = frameData.Get<UniversalResourceData>();

            // Ensure we aren't trying to write to the backbuffer directly if we need a texture read
            if (resourceData.isActiveTargetBackBuffer)
            {
                Debug.LogWarning($"Skipping {m_PassName}. Cannot run on BackBuffer; requires intermediate texture.");
                return;
            }

            // Update the material properties for this frame
            UpdateMaterialProperties(frameData);

            // 1. Get the source (Current Camera Color)
            var source = resourceData.activeColorTexture;

            // 2. Create the destination texture (New Texture)
            var destinationDesc = renderGraph.GetTextureDesc(source);
            destinationDesc.name = m_PassName;
            destinationDesc.clearBuffer = false;

            TextureHandle destination = renderGraph.CreateTexture(destinationDesc);

            // 3. Setup the Blit parameters
            // This helper struct handles creating the pass and setting up the source/dest
            RenderGraphUtils.BlitMaterialParameters para = new(source, destination, m_Material, 0);

            // 4. Add the pass to the graph
            renderGraph.AddBlitPass(para, passName: m_PassName);

            // 5. Swap the Camera Color
            // This tells URP: "The active camera color is now this new texture we just drew to."
            resourceData.cameraColor = destination;
        }
    }
    [System.Serializable]
    public class VolumetricCloudsSettings
    {
        [Header("Assets")]
        public Texture3D cloudTex;

        [Header("Bounds (World Space)")]
        public Vector3 boundsCenter = Vector3.zero;
        public Vector3 boundsSize = new Vector3(100, 50, 100);

        [Header("Shape & Movement")]
        public float cloudScale = 1.0f;
        public Vector3 cloudOffset;
        public Vector3 moveSpeed;

        [Header("Appearance")]
        public Color cloudColor = Color.white;
        public float densityThreshold = 0.5f;
        public float densityMultiplier = 1.0f;
        public float absorption = 0.5f;
        public float absorptionThreshold = 0.5f;
        public float transmittanceContrast = 0.5f;

        [Header("Lighting")]
        [Range(0f, 1f)] public float harveyGreensteinBias = 0.3f;
        public float harveyGreensteinThreshold = 0.5f;
        [Range(0f, 1f)] public float harveyGreensteinDualLobStrength = 0.5f;
        public float diffusion = 0.5f;
        public Color diffusionColor = Color.white;

        [Header("Performance")]
        [Range(3, 400)] public int numSteps = 64;
        [Range(1, 20)] public int numLightSteps = 4;
        public float sampleLightDist = 10f;
    }


    public VolumetricCloudsSettings settings = new VolumetricCloudsSettings();
    public Shader shader;
    public RenderPassEvent injectionPoint = RenderPassEvent.BeforeRenderingTransparents;

    Material m_Material;
    VolumetricCloudsPass m_ScriptablePass;

    public override void Create()
    {
        // Create material if shader is present
        if (shader != null)
        {
            m_Material = CoreUtils.CreateEngineMaterial(shader);
        }

        m_ScriptablePass = new VolumetricCloudsPass();
        m_ScriptablePass.renderPassEvent = injectionPoint;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // Don't run in scene view if you want to avoid visual clutter, or keep it if you want to see fog in editor
        if (renderingData.cameraData.cameraType == CameraType.Preview || renderingData.cameraData.cameraType == CameraType.Reflection)
            return;

        if (m_Material == null && shader != null)
            m_Material = CoreUtils.CreateEngineMaterial(shader);

        if (m_Material == null)
        {
            Debug.LogWarning("VolumetricClouds material is null.");
            return;
        }

        // Pass the settings to the Render Pass
        m_ScriptablePass.Setup(m_Material, settings);
        renderer.EnqueuePass(m_ScriptablePass);
    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(m_Material);
    }
}
