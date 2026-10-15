using UnityEngine;

public class GentleWaterFloat : MonoBehaviour
{
    [SerializeField] private float amplitude = 0.015f;
    [SerializeField] private float frequency = 0.3f;

    private float startY;
    private float elapsed;

    private void Start()
    {
        startY = transform.localPosition.y;
    }

    private void Update()
    {
        elapsed += Time.deltaTime;

        Vector3 position = transform.localPosition;
        position.y = startY
            + Mathf.Sin(elapsed * frequency * Mathf.PI * 2f) * amplitude;

        transform.localPosition = position;
    }
}