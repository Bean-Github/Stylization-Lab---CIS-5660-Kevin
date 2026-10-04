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

        // Makes the sprite face the exact same direction as the camera
        transform.LookAt(transform.position + mainCam.transform.forward);
    }
}