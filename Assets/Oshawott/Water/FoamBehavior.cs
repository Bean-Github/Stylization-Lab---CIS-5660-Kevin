using UnityEngine;

public class FoamBehavior : MonoBehaviour
{
    [Header("Movement & Lifetime")]
    public float moveSpeed = 2f;
    public float speedMultiplier = 1f;

    [Tooltip("X axis is normalized lifetime (0 to 1), Y axis is speed multiplier.")]
    public AnimationCurve speedCurve =
        AnimationCurve.Constant(0f, 1f, 1f);

    [Tooltip("X axis is normalized lifetime (0 to 1), Y axis is size multiplier.")]
    public AnimationCurve sizeCurve =
        AnimationCurve.Constant(0f, 1f, 1f);

    public float lifetime = 5f;

    [Header("Fading Settings")]
    [Tooltip("X axis is normalized lifetime (0 to 1), Y axis is alpha.")]
    public AnimationCurve alphaCurve =
        AnimationCurve.Linear(0f, 1f, 1f, 0f);

    [Range(0f, 1f)]
    public float overallAlpha = 1f;

    [Header("Size Settings")]
    public float overallSizeMultiplier = 1f;

    [Header("Shader Controls")]
    public bool randomizeSeed = true;
    public float customSeed = 0f;

    [HideInInspector]
    public float currentAlpha = 1f;

    private float age = 0f;
    private Material mat;

    void Start()
    {
        Renderer rnd = GetComponentInChildren<Renderer>();

        if (rnd != null)
        {
            mat = rnd.material;

            float seed = randomizeSeed
                ? Random.Range(0f, 1000f)
                : customSeed;

            mat.SetFloat("_Seed", seed);
            mat.SetFloat("_NoiseSeed", seed);

            float initialAlpha =
                overallAlpha * alphaCurve.Evaluate(0f);

            float initialSize =
                overallSizeMultiplier * sizeCurve.Evaluate(0f);

            mat.SetFloat("_OverallAlpha", initialAlpha);
            mat.SetFloat("_OverallSizeMult", initialSize);
        }
    }

    void Update()
    {
        age += Time.deltaTime;

        if (age > lifetime)
        {
            Destroy(gameObject);
            return;
        }

        float normalizedTime =
            Mathf.Clamp01(age / lifetime);

        float currentSpeed =
            moveSpeed *
            speedMultiplier *
            speedCurve.Evaluate(normalizedTime);

        transform.Translate(
            Vector3.forward * (currentSpeed * Time.deltaTime),
            Space.Self
        );

        currentAlpha =
            overallAlpha *
            alphaCurve.Evaluate(normalizedTime);

        float currentSize =
            overallSizeMultiplier *
            sizeCurve.Evaluate(normalizedTime);

        if (mat != null)
        {
            mat.SetFloat("_OverallAlpha", currentAlpha);
            mat.SetFloat("_OverallSizeMult", currentSize);
        }
    }
}