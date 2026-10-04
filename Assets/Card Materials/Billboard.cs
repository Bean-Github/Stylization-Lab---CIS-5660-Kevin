using UnityEngine;

public class Billboard : MonoBehaviour
{
    private Camera mainCam;

    void Start()
    {
        // Cache the main camera for performance
        mainCam = Camera.main;
    }

    void LateUpdate()
    {
        if (mainCam == null) return;

        Vector3 toCam = mainCam.transform.position - transform.position;

        transform.LookAt(-toCam.normalized);
    }
}