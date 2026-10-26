using UnityEngine;

public class FoamSpawner : MonoBehaviour
{
    [Header("Spawner Settings")]
    [Tooltip("The prefab with the FoamBehavior script attached")]
    public GameObject foamPrefab;

    [Header("Spawn Timing Range")]
    public float minSpawnInterval = 0.5f;
    public float maxSpawnInterval = 2.0f;

    [Header("Random Speed Variation")]
    [Tooltip("Minimum multiplier applied to the foam's base speed.")]
    public float minSpeedMultiplier = 0.8f;

    [Tooltip("Maximum multiplier applied to the foam's base speed.")]
    public float maxSpeedMultiplier = 1.2f;

    private float _timer = 0f;
    private float _currentInterval = 1f;

    void Start()
    {
        SetNextInterval();
    }

    private void SetNextInterval()
    {
        _currentInterval =
            Random.Range(minSpawnInterval, maxSpawnInterval);
    }

    void Update()
    {
        _timer += Time.deltaTime;

        if (_timer >= _currentInterval)
        {
            SpawnFoam();
            _timer = 0f;
            SetNextInterval();
        }
    }

    private void SpawnFoam()
    {
        if (foamPrefab == null)
            return;

        GameObject spawnedFoam = Instantiate(
            foamPrefab,
            transform.position,
            transform.rotation,
            transform
        );

        FoamBehavior foamBehavior =
            spawnedFoam.GetComponentInChildren<FoamBehavior>();

        if (foamBehavior != null)
        {
            float randomSpeedMultiplier = Random.Range(
                minSpeedMultiplier,
                maxSpeedMultiplier
            );

            foamBehavior.speedMultiplier *= randomSpeedMultiplier;
        }
    }
}