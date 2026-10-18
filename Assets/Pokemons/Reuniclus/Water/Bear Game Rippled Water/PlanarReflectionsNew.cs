using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;


[ExecuteAlways]
public class PlanarReflectionsNew : MonoBehaviour
{
    [Tooltip("Which layers should be reflected? (Exclude the water layer itself!)")]
    public LayerMask reflectionLayers = -1;

    [Tooltip("Higher resolution = sharper reflection, but costs more performance.")]
    public int resolution = 512;

    [Range(-0.05f, 0.05f)]
    public float clipPlaneOffset = 0.01f;

    private Camera _reflectionCamera;
    private RenderTexture _reflectionTexture;
    private readonly int _planarReflectionTextureId = Shader.PropertyToID("_MobileSSPR_ColorRT");

    [Tooltip("How far the reflection camera should be seen. Keep this as low as possible!")]
    public float maxReflectionDistance = 150f;

    [Tooltip("Forces lower LODs in the reflection. 1 is normal, 0.5 is lower quality, 0.1 is lowest.")]
    [Range(0.1f, 1f)]
    public float reflectionLodBias = 0.5f;

    void OnEnable()
    {
        RenderPipelineManager.beginCameraRendering += RenderReflectionCamera;
    }

    void OnDisable()
    {
        RenderPipelineManager.beginCameraRendering -= RenderReflectionCamera;
        CleanUp();
    }

    void CleanUp()
    {
        if (_reflectionCamera)
        {
            _reflectionCamera.targetTexture = null;
            SafeDestroy(_reflectionCamera.gameObject);
            _reflectionCamera = null;
        }
        if (_reflectionTexture)
        {
            // FIX 1: Properly release persistent textures
            _reflectionTexture.Release();
            SafeDestroy(_reflectionTexture);
            _reflectionTexture = null;
        }
    }

    void SafeDestroy(Object obj)
    {
        if (Application.isEditor) DestroyImmediate(obj);
        else Destroy(obj);
    }
    void RenderReflectionCamera(ScriptableRenderContext context, Camera camera)
    {
        if (camera.cameraType != CameraType.Game && camera.cameraType != CameraType.SceneView) return;

        UpdateCamera(camera);

        GL.invertCulling = true;

        float originalLodBias = QualitySettings.lodBias;
        QualitySettings.lodBias = reflectionLodBias;

        var request = new UniversalRenderPipeline.SingleCameraRequest
        {
            destination = _reflectionTexture
        };
        RenderPipeline.SubmitRenderRequest(_reflectionCamera, request);

        QualitySettings.lodBias = originalLodBias;
        GL.invertCulling = false;

        Shader.SetGlobalTexture(_planarReflectionTextureId, _reflectionTexture);
    }
    void UpdateCamera(Camera srcCamera)
    {
        if (_reflectionCamera == null)
        {
            GameObject go = new GameObject("Reflection Camera", typeof(Camera));
            go.hideFlags = HideFlags.HideAndDontSave;
            _reflectionCamera = go.GetComponent<Camera>();

            go.AddComponent<UniversalAdditionalCameraData>();
            _reflectionCamera.enabled = false;
        }

        // FIX 3: Replaced GetTemporary with a persistent RenderTexture to fix the "Depth Only Surface" error
        if (_reflectionTexture == null || _reflectionTexture.width != resolution)
        {
            if (_reflectionTexture)
            {
                _reflectionTexture.Release();
                SafeDestroy(_reflectionTexture);
            }

            RenderTextureDescriptor desc = new RenderTextureDescriptor(resolution, resolution)
            {
                graphicsFormat = GraphicsFormatUtility.GetGraphicsFormat(RenderTextureFormat.DefaultHDR, /*isSRGB*/ false),
                depthStencilFormat = GraphicsFormat.D24_UNorm_S8_UInt,
                msaaSamples = 1,
                dimension = UnityEngine.Rendering.TextureDimension.Tex2D,
                useMipMap = false,
                autoGenerateMips = false,
            };

            _reflectionTexture = new RenderTexture(desc);
            _reflectionTexture.name = "PlanarReflectionTexture";
            bool created = _reflectionTexture.Create();
            Debug.Log($"Reflection RT created: {created}, graphicsFormat: {_reflectionTexture.graphicsFormat}, depthStencilFormat: {_reflectionTexture.depthStencilFormat}");
        }

        _reflectionCamera.CopyFrom(srcCamera);
        _reflectionCamera.cameraType = CameraType.Reflection;
        _reflectionCamera.targetTexture = _reflectionTexture;
        _reflectionCamera.cullingMask = reflectionLayers;

        // APPLY FAR CLIP PLANE OPTIMIZATION
        _reflectionCamera.farClipPlane = maxReflectionDistance;

        _reflectionCamera.clearFlags = CameraClearFlags.SolidColor;
        _reflectionCamera.backgroundColor = new Color(0, 0, 0, 0);

        UniversalAdditionalCameraData camData = _reflectionCamera.GetComponent<UniversalAdditionalCameraData>();
        if (camData != null)
        {
            camData.renderPostProcessing = false;
            camData.renderShadows = false;
            // FIX 4: Removed requiresDepthOption/requiresColorOption overrides so URP attaches color properly
        }

        // 1. Calculate reflection plane
        Vector3 normal = transform.up;
        float d = -Vector3.Dot(normal, transform.position) - clipPlaneOffset;
        Vector4 reflectionPlane = new Vector4(normal.x, normal.y, normal.z, d);

        // 2. Calculate mirror matrix
        Matrix4x4 reflection = Matrix4x4.identity;
        reflection.m00 = 1F - 2F * reflectionPlane[0] * reflectionPlane[0];
        reflection.m01 = -2F * reflectionPlane[0] * reflectionPlane[1];
        reflection.m02 = -2F * reflectionPlane[0] * reflectionPlane[2];
        reflection.m03 = -2F * reflectionPlane[3] * reflectionPlane[0];

        reflection.m10 = -2F * reflectionPlane[1] * reflectionPlane[0];
        reflection.m11 = 1F - 2F * reflectionPlane[1] * reflectionPlane[1];
        reflection.m12 = -2F * reflectionPlane[1] * reflectionPlane[2];
        reflection.m13 = -2F * reflectionPlane[3] * reflectionPlane[1];

        reflection.m20 = -2F * reflectionPlane[2] * reflectionPlane[0];
        reflection.m21 = -2F * reflectionPlane[2] * reflectionPlane[1];
        reflection.m22 = 1F - 2F * reflectionPlane[2] * reflectionPlane[2];
        reflection.m23 = -2F * reflectionPlane[3] * reflectionPlane[2];

        reflection.m30 = 0F;
        reflection.m31 = 0F;
        reflection.m32 = 0F;
        reflection.m33 = 1F;

        Vector3 mirroredPos = reflection.MultiplyPoint(srcCamera.transform.position);
        Vector3 mirroredForward = reflection.MultiplyVector(srcCamera.transform.forward);
        Vector3 mirroredUp = reflection.MultiplyVector(srcCamera.transform.up);

        _reflectionCamera.transform.position = mirroredPos;
        _reflectionCamera.transform.rotation = Quaternion.LookRotation(mirroredForward, mirroredUp);

        _reflectionCamera.worldToCameraMatrix = srcCamera.worldToCameraMatrix * reflection;

        // 3. Oblique projection matrix
        Vector4 clipPlane = CameraSpacePlane(_reflectionCamera, transform.position, normal, 1.0f);
        _reflectionCamera.projectionMatrix = srcCamera.CalculateObliqueMatrix(clipPlane);
    }

    Vector4 CameraSpacePlane(Camera cam, Vector3 pos, Vector3 normal, float sideSign)
    {
        Vector3 offsetPos = pos + normal * clipPlaneOffset;
        Matrix4x4 m = cam.worldToCameraMatrix;
        Vector3 cpos = m.MultiplyPoint(offsetPos);
        Vector3 cnormal = m.MultiplyVector(normal).normalized * sideSign;
        return new Vector4(cnormal.x, cnormal.y, cnormal.z, -Vector3.Dot(cpos, cnormal));
    }
}