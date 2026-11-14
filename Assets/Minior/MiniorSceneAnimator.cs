using UnityEngine;

public class MiniorSceneAnimator : MonoBehaviour
{
    [SerializeField] private Vector3 direction = Vector3.right;
    [SerializeField, Min(0f)] private float speed = 1f;

    private void Update()
    {
        transform.position += direction.normalized * speed * Time.deltaTime;
    }
}
