using UnityEngine;
using UnityEngine.Splines;
using Unity.Mathematics; // Required for spline calculations

public class SplineFollower : MonoBehaviour
{
    [Header("Spline Settings")]
    public SplineContainer splinePath;
    public float speed = 5f;
    public bool loop = true;

    // Value between 0 (start) and 1 (end)
    private float progress = 0f;
    private float splineLength;

    void Start()
    {
        if (splinePath != null)
        {
            // Calculate the total length of the spline to ensure constant speed
            splineLength = splinePath.CalculateLength();
        }
    }

    void Update()
    {
        if (splinePath == null || splineLength == 0) return;

        // Advance the progress based on speed and spline length
        progress += (speed * Time.deltaTime) / splineLength;

        // Handle looping or stopping at the end
        if (progress > 1f)
        {
            if (loop) progress -= 1f;
            else progress = 1f;
        }

        // Evaluate the position, tangent (forward direction), and up vector at the current progress
        splinePath.Evaluate(progress, out float3 position, out float3 tangent, out float3 upVector);

        // Move the object
        transform.position = position;

        // Rotate the object to face the path
        if (math.lengthsq(tangent) > 0f)
        {
            transform.rotation = Quaternion.LookRotation(tangent, upVector);
        }
    }
}