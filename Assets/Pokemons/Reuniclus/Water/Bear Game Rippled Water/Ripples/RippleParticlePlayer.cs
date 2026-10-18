using UnityEngine;

public class RippleParticlePlayer : MonoBehaviour
{
    public bool isPainting = false;
    public float paintMoveThreshold = 0.1f;

    public ParticleSystem waterPaintVFX;

    Vector3 _lastPaintPosition;
    public void StartPainting()
    {
        PlayWaterPaintEffect();
        _lastPaintPosition = new Vector3(transform.position.x, 0.0f, transform.position.z); // Ignore vertical movement for distance check
        isPainting = true;
    }

    public void StopPainting()
    {
        isPainting = false;
        StopWaterPaintEffect();
    }

    public void PlayWaterPaintEffect()
    {
        waterPaintVFX.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
        waterPaintVFX.Play();
    }

    public void StopWaterPaintEffect()
    {
        waterPaintVFX.Stop(true, ParticleSystemStopBehavior.StopEmitting);
    }

    private void Update()
    {
        if (isPainting)
        {
            Vector3 currentFlatPos = new Vector3(transform.position.x, 0.0f, transform.position.z); // Ignore vertical movement for distance check

            if (Vector3.Distance(currentFlatPos, _lastPaintPosition) >= paintMoveThreshold)
            {
                PlayWaterPaintEffect();
                _lastPaintPosition = currentFlatPos;
            }
        }

    }
}
