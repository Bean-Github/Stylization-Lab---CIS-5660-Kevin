using System.Collections;
using UnityEngine;

public class PsyduckGameManager : MonoBehaviour
{
    [Header("Animators")]
    [Tooltip("The main animator that will play the Idle animation.")]
    [SerializeField] private Animator psyduckAnimator;

    [Tooltip("The other animator that plays the SceneStart animation.")]
    [SerializeField] private Animator sceneAnimator;

    [Header("Settings")]
    [Tooltip("How long to wait after pressing space before playing Idle.")]
    [SerializeField] private float timeBeforeIdle = 2.0f;

    // A flag to ensure we only trigger the sequence once
    private bool hasStarted = false;

    void Update()
    {
        // Check if Space is pressed and the sequence hasn't started yet
        if (Input.GetKeyDown(KeyCode.Space) && !hasStarted)
        {
            hasStarted = true;
            StartCoroutine(SequenceRoutine());
        }
    }

    private IEnumerator SequenceRoutine()
    {
        // 1. Immediately play SceneStart on the scene animator
        if (sceneAnimator != null)
        {
            sceneAnimator.Play("SceneStart");
        }
        else
        {
            Debug.LogWarning("Scene Animator is not assigned!");
        }

        // 2. Wait for the specified time
        yield return new WaitForSeconds(timeBeforeIdle);

        // 3. Play Idle on the Psyduck animator
        if (psyduckAnimator != null)
        {
            psyduckAnimator.Play("Idle");
        }
        else
        {
            Debug.LogWarning("Psyduck Animator is not assigned!");
        }
    }
}