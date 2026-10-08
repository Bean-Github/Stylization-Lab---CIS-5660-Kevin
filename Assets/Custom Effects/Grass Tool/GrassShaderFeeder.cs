using UnityEngine;

namespace GrassTool
{
    public class GrassShaderFeeder : MonoBehaviour
    {
        //[Header("Trail Settings")]
        //public float stepRecordDistance = 0.5f;
        //public int maxSteps = 32;

        //private ComputeBuffer stepBuffer;
        //private PlayerStep[] stepData;
        //private int currentIndex = 0;
        //private Vector3 lastRecordedPosition;

        //struct PlayerStep
        //{
        //    public Vector3 position;
        //    public float time;
        //}

        //private void Start()
        //{
        //    stepBuffer = new ComputeBuffer(maxSteps, 16);
        //    stepData = new PlayerStep[maxSteps];

        //    for (int i = 0; i < maxSteps; i++)
        //    {
        //        stepData[i] = new PlayerStep { position = Vector3.zero, time = -1000f };
        //    }

        //    stepBuffer.SetData(stepData);

        //    // NEW: Push the buffer globally to all shaders, ignoring specific materials
        //    Shader.SetGlobalBuffer("_PlayerStepsBuffer", stepBuffer);
        //}

        //private void Update()
        //{
        //    if (PlatformingPlayerMovement.Instance == null) return;

        //    Vector3 currentPos = PlatformingPlayerMovement.Instance.playerRenderer.position;

        //    if (Vector3.Distance(currentPos, lastRecordedPosition) > stepRecordDistance)
        //    {
        //        // NEW: A debug log to prove the script is actually running when you walk
        //        Debug.Log("Player took a step! Updating GPU Buffer.");

        //        stepData[currentIndex] = new PlayerStep
        //        {
        //            position = currentPos,
        //            time = Time.time
        //        };

        //        currentIndex = (currentIndex + 1) % maxSteps;
        //        lastRecordedPosition = currentPos;

        //        stepBuffer.SetData(stepData);
        //    }
        //}

        //private void OnDestroy()
        //{
        //    if (stepBuffer != null)
        //    {
        //        stepBuffer.Release();
        //    }
        //}
    }
}