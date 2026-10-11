using UnityEngine;

public class AnimatedCardLayer : MonoBehaviour
{
    [Tooltip("False = Outside Card, True = Inside Card")]
    public bool insideCard = false;

    public bool applyToChildren = false;

    private bool lastInsideCard;

    private void Awake()
    {
        lastInsideCard = !insideCard;
        ApplyLayer();
        lastInsideCard = insideCard;
    }

    private void LateUpdate()
    {
        if (insideCard != lastInsideCard)
        {
            ApplyLayer();
            lastInsideCard = insideCard;
        }
    }

    private void ApplyLayer()
    {
        string layerName = insideCard
            ? "Inside Card"
            : "Outside Card";

        int layer = LayerMask.NameToLayer(layerName);

        if (layer == -1)
        {
            Debug.LogError($"Layer '{layerName}' does not exist.");
            return;
        }

        if (applyToChildren)
            SetLayerRecursive(transform, layer);
        else
            gameObject.layer = layer;
    }

    private void SetLayerRecursive(Transform t, int layer)
    {
        t.gameObject.layer = layer;

        foreach (Transform child in t)
            SetLayerRecursive(child, layer);
    }

    private void OnValidate()
    {
        ApplyLayer();
    }
}