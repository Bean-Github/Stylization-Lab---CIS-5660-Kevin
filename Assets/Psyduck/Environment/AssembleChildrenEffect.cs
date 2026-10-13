using UnityEngine;
using System.Collections;
using System.Collections.Generic;

public class AssembleChildrenEffect : MonoBehaviour
{
    [Header("Animation Settings")]
    public float duration = 1.5f;
    public float scatterDistance = 5.0f;
    public AnimationCurve easeCurve = AnimationCurve.EaseInOut(0, 0, 1, 1);

    private struct ChildData
    {
        public Transform transform;
        public Vector3 originalPos;
        public Quaternion originalRot;
    }

    private List<ChildData> childrenData = new List<ChildData>();

    void Awake()
    {
        // Cache the original local positions and rotations of all children
        foreach (Transform child in transform)
        {
            childrenData.Add(new ChildData
            {
                transform = child,
                originalPos = child.localPosition,
                originalRot = child.localRotation
            });
        }
    }

    void OnEnable()
    {
        // Stop any running animations if the object is toggled rapidly
        StopAllCoroutines();
        StartCoroutine(AnimateIn());
    }

    IEnumerator AnimateIn()
    {
        Vector3[] randomStartPositions = new Vector3[childrenData.Count];
        Quaternion[] randomStartRotations = new Quaternion[childrenData.Count];

        // 1. Instantly snap children to random "out" positions and rotations
        for (int i = 0; i < childrenData.Count; i++)
        {
            Transform child = childrenData[i].transform;

            // Pick a random position in a sphere around the original position
            randomStartPositions[i] = childrenData[i].originalPos + (Random.insideUnitSphere * scatterDistance);

            // Pick a completely random orientation
            randomStartRotations[i] = Random.rotation;

            child.localPosition = randomStartPositions[i];
            child.localRotation = randomStartRotations[i];
        }

        // 2. Animate them back to their original states over time
        float elapsedTime = 0f;

        while (elapsedTime < duration)
        {
            elapsedTime += Time.deltaTime;

            // Normalize time between 0 and 1, then apply the smoothing curve
            float t = Mathf.Clamp01(elapsedTime / duration);
            float easeT = easeCurve.Evaluate(t);

            for (int i = 0; i < childrenData.Count; i++)
            {
                Transform child = childrenData[i].transform;

                // Lerp position and rotation
                child.localPosition = Vector3.Lerp(randomStartPositions[i], childrenData[i].originalPos, easeT);
                child.localRotation = Quaternion.Lerp(randomStartRotations[i], childrenData[i].originalRot, easeT);
            }

            yield return null; // Wait for the next frame
        }

        // 3. Ensure everything is perfectly aligned at the exact original values at the end
        foreach (var data in childrenData)
        {
            data.transform.localPosition = data.originalPos;
            data.transform.localRotation = data.originalRot;
        }
    }
}