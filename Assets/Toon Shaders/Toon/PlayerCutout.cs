using System.Collections.Generic;
using UnityEngine;

public class PlayerCutout : MonoBehaviour
{
    [Header("References")]
    [SerializeField] private Camera targetCamera;
    [SerializeField] private Transform targetObject;

    [Header("Cutout")]
    [Tooltip("Radius of the cutout in normalized screen space.")]
    [SerializeField] private float cutoutSize = 0.08f;

    [Tooltip("Width of the soft edge around the cutout.")]
    [SerializeField] private float falloffSize = 0.02f;

    [SerializeField] private Vector2 cutoutOffset = Vector2.zero;

    [Tooltip("How fast the cutout fades in and out globally.")]
    [SerializeField] private float fadeSpeed = 5f;

    [Header("Spherecast")]
    [SerializeField] private LayerMask wallMask;
    public float spherecastRadius = 0.5f;

    private static readonly int CutoutPosID = Shader.PropertyToID("_CutoutPos");
    private static readonly int CutoutSizeID = Shader.PropertyToID("_CutoutSize");
    private static readonly int FalloffSizeID = Shader.PropertyToID("_FalloffSize");
    private static readonly int CutoutEnabledID = Shader.PropertyToID("_CutoutEnabled");

    // Tracks objects that currently have the cutout enabled on their material
    private readonly HashSet<Renderer> activeCutoutRenderers = new();

    private MaterialPropertyBlock propertyBlock;
    private float m_currentCutoutSize;
    private float m_targetCutoutSize;

    private void Awake()
    {
        propertyBlock = new MaterialPropertyBlock();
    }

    void CalculateTargetCutoutSize()
    {
        float frustumHeight;
        float distanceToPlayer = Vector3.Distance(targetCamera.transform.position, targetObject.position);

        // 1. Calculate the height of the camera's view at the player's exact distance
        if (targetCamera.orthographic)
        {
            frustumHeight = targetCamera.orthographicSize * 2.0f;
        }
        else
        {
            // 2 * Distance * Tan(FOV / 2) gives the exact world-space height of the camera frustum
            frustumHeight = 2.0f * distanceToPlayer * Mathf.Tan(targetCamera.fieldOfView * 0.5f * Mathf.Deg2Rad);
        }

        // 2. Calculate the world-space width using the aspect ratio
        float frustumWidth = frustumHeight * targetCamera.aspect;

        // 3. Convert the world-space radius (cutoutSize) into a normalized screen-space percentage (0.0 to 1.0)
        // Because your UV setup uses the screen width as 1.0, we divide by frustumWidth
        m_targetCutoutSize = cutoutSize / frustumWidth;
    }

    void SetGlobalCutoutParams()
    {
        Vector3 viewportPosition = targetCamera.WorldToViewportPoint(targetObject.position);
        Vector2 cutoutPos = new Vector2(viewportPosition.x, viewportPosition.y);

        cutoutPos.y /= targetCamera.aspect;
        cutoutPos += cutoutOffset;

        Shader.SetGlobalVector(CutoutPosID, new Vector4(cutoutPos.x, cutoutPos.y, _closestDistanceToPlayer, _cutoutUsed ? 1.0f : 0.0f));
        Shader.SetGlobalFloat(CutoutSizeID, m_currentCutoutSize);
        Shader.SetGlobalFloat(FalloffSizeID, falloffSize);
    }

    float _closestDistanceToPlayer = float.MaxValue;

    bool _cutoutUsed = false;

    private void LateUpdate()
    {
        _cutoutUsed = false;

        if (targetCamera == null || targetObject == null)
            return;

        CalculateTargetCutoutSize();

        Vector3 camPos = targetCamera.transform.position;
        Vector3 playerPos = targetObject.position;
        Vector3 direction = playerPos - camPos;
        float distanceToPlayer = direction.magnitude;

        if (distanceToPlayer <= 0f)
            return;

        direction /= distanceToPlayer;

        RaycastHit[] hits = Physics.SphereCastAll(
            camPos + spherecastRadius * direction,
            spherecastRadius,
            direction,
            distanceToPlayer,
            wallMask,
            QueryTriggerInteraction.Ignore
        );

        HashSet<Renderer> currentBlockers = new HashSet<Renderer>();
        bool isAnythingBlocking = false;

        foreach (RaycastHit hit in hits)
        {
            Renderer r = hit.collider.GetComponentInParent<Renderer>();
            if (r != null)
            {
                // Find the absolute closest point on this collider to the camera
                Vector3 closestPointToCam = hit.collider.ClosestPoint(camPos);
                float distToRenderer = Vector3.Distance(camPos, closestPointToCam);

                // If the closest surface is nearer than the player's center, it is in front
                if (distToRenderer < distanceToPlayer)
                {
                    currentBlockers.Add(r);
                    isAnythingBlocking = true;
                }
            }

            if (hit.collider.gameObject.layer == LayerMask.NameToLayer("Player"))
            {
                _closestDistanceToPlayer = Mathf.Min(_closestDistanceToPlayer, hit.distance);
            }
        }

        // Animate the global cutout hole
        if (isAnythingBlocking)
        {
            m_currentCutoutSize = Mathf.MoveTowards(m_currentCutoutSize, m_targetCutoutSize, Time.deltaTime * fadeSpeed);
        }
        else
        {
            m_currentCutoutSize = Mathf.MoveTowards(m_currentCutoutSize, 0.0f, Time.deltaTime * fadeSpeed);
        }

        SetGlobalCutoutParams();

        // Turn ON the cutout property for new blockers immediately
        foreach (Renderer r in currentBlockers)
        {
            if (!activeCutoutRenderers.Contains(r))
            {
                r.GetPropertyBlock(propertyBlock);
                propertyBlock.SetFloat(CutoutEnabledID, 1f);
                if (propertyBlock.HasFloat(CutoutEnabledID))
                {
                    _cutoutUsed = true;
                }

                r.SetPropertyBlock(propertyBlock);

                // Remember that we modified this renderer
                activeCutoutRenderers.Add(r);
            }
        }

        // Turn OFF the cutout property ONLY when the hole is completely invisible
        if (m_currentCutoutSize <= 0.0f && !isAnythingBlocking)
        {
            foreach (Renderer r in activeCutoutRenderers)
            {
                if (r != null)
                {
                    r.GetPropertyBlock(propertyBlock);
                    propertyBlock.SetFloat(CutoutEnabledID, 0f);
                    r.SetPropertyBlock(propertyBlock);
                }
            }

            // Now that everything is reset, it is safe to clear the list
            activeCutoutRenderers.Clear();
        }
    }
}