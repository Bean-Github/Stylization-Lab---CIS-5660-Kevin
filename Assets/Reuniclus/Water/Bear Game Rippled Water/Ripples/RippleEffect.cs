using System.Collections;
using UnityEngine;

public class RippleEffect : MonoBehaviour
{
    [Header("Texture Settings")]
    public int TextureSize = 512;
    public RenderTexture ObjectsRT;

    public float rippleSpeed = 0.2f;

    [Header("Debug")]
    public RenderTexture CurrRT;
    public RenderTexture PrevRT;
    public RenderTexture TempRT;

    [Header("Shaders")]
    public Shader RippleShader;
    public Shader AddShader;

    [Header("Ripple Camera")]
    public Camera RippleCamera;

    private Material RippleMat;
    private Material AddMat;

    private Renderer waterRenderer;
    private Material waterMaterial;

    void Start()
    {
        // ------------------------------------------------
        // VALIDATION
        // ------------------------------------------------

        waterRenderer = GetComponent<Renderer>();

        if (waterRenderer == null)
        {
            Debug.LogError(
                "RippleEffect must be attached to an object with a Renderer.",
                this
            );

            enabled = false;
            return;
        }

        if (RippleCamera == null)
        {
            Debug.LogError(
                "RippleCamera is not assigned.",
                this
            );

            enabled = false;
            return;
        }

        if (ObjectsRT == null)
        {
            Debug.LogError(
                "ObjectsRT is not assigned.",
                this
            );

            enabled = false;
            return;
        }

        if (RippleShader == null)
        {
            Debug.LogError(
                "RippleShader is not assigned.",
                this
            );

            enabled = false;
            return;
        }

        if (AddShader == null)
        {
            Debug.LogError(
                "AddShader is not assigned.",
                this
            );

            enabled = false;
            return;
        }


        // ------------------------------------------------
        // CREATE SIMULATION TEXTURES
        // ------------------------------------------------

        CurrRT = CreateRT("Ripple Current");
        PrevRT = CreateRT("Ripple Previous");
        TempRT = CreateRT("Ripple Temp");


        // ------------------------------------------------
        // CREATE MATERIALS
        // ------------------------------------------------

        RippleMat = new Material(RippleShader);
        AddMat = new Material(AddShader);

        waterMaterial = waterRenderer.material;


        // ------------------------------------------------
        // IMPORTANT:
        // GIVE WATER SHADER THE RIPPLE CAMERA DATA
        // ------------------------------------------------

        UpdateWaterShaderProperties();


        // Initial ripple texture
        waterMaterial.SetTexture(
            "_RippleTex",
            CurrRT
        );


        // ------------------------------------------------
        // START SIMULATION
        // ------------------------------------------------

        StartCoroutine(RipplesRoutine());
    }


    RenderTexture CreateRT(string rtName)
    {
        RenderTexture rt = new RenderTexture(
            TextureSize,
            TextureSize,
            0,
            RenderTextureFormat.RFloat,
            RenderTextureReadWrite.Linear
        );

        rt.name = rtName;

        rt.wrapMode = TextureWrapMode.Clamp;
        rt.filterMode = FilterMode.Bilinear;

        rt.useMipMap = false;
        rt.autoGenerateMips = false;

        rt.Create();


        // Clear to zero initially.
        RenderTexture oldActive = RenderTexture.active;

        RenderTexture.active = rt;

        GL.Clear(
            false,
            true,
            Color.black
        );

        RenderTexture.active = oldActive;


        return rt;
    }


    void UpdateWaterShaderProperties()
    {
        if (waterMaterial == null || RippleCamera == null)
            return;

        RippleMat.SetFloat(
            "_RippleSpeed",
            rippleSpeed
        );

        // Water's LOCAL up is the surface normal.
        Vector3 waterNormal = transform.up;

        // Orient the ripple camera perpendicular to the water.
        // Assumes the mesh uses local +Y as its surface normal.

        Transform cam = RippleCamera.transform;

        waterMaterial.SetVector(
            "_RippleCameraPos",
            cam.position
        );

        waterMaterial.SetVector(
            "_RippleCameraRight",
            cam.right
        );

        waterMaterial.SetVector(
            "_RippleCameraUp",
            cam.up
        );

        waterMaterial.SetFloat(
            "_RippleCameraSize",
            RippleCamera.orthographicSize
        );

        waterMaterial.SetFloat(
            "_RippleCameraAspect",
            RippleCamera.aspect
        );

        waterMaterial.SetFloat(
            "_RippleTextureSize",
            TextureSize
        );
    }

    IEnumerator RipplesRoutine()
    {
        while (true)
        {
            AddMat.SetTexture(
                "_ObjectsRT",
                ObjectsRT
            );

            AddMat.SetTexture(
                "_CurrentRT",
                CurrRT
            );


            // Temp =
            //
            // CurrRT + ObjectsRT

            Graphics.Blit(
                null,
                TempRT,
                AddMat
            );


            // Temp is now our injected current state.
            RenderTexture oldCurr = CurrRT;

            CurrRT = TempRT;
            TempRT = oldCurr;


            // simulate wave
            RippleMat.SetTexture(
                "_PrevRT",
                PrevRT
            );

            RippleMat.SetTexture(
                "_CurrentRT",
                CurrRT
            );


            // Calculate next wave state into TempRT.
            Graphics.Blit(
                null,
                TempRT,
                RippleMat
            );


            RenderTexture oldPrev = PrevRT;

            PrevRT = CurrRT;
            CurrRT = TempRT;
            TempRT = oldPrev;

            waterMaterial.SetTexture(
                "_RippleTex",
                CurrRT
            );

            UpdateWaterShaderProperties();

            yield return null;
        }
    }


    void OnDestroy()
    {
        Release(ref CurrRT);
        Release(ref PrevRT);
        Release(ref TempRT);


        if (RippleMat != null)
        {
            Destroy(RippleMat);
            RippleMat = null;
        }


        if (AddMat != null)
        {
            Destroy(AddMat);
            AddMat = null;
        }
    }


    void Release(ref RenderTexture rt)
    {
        if (rt == null)
            return;

        rt.Release();
        Destroy(rt);

        rt = null;
    }
}