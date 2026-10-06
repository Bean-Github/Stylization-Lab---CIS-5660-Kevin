using UnityEngine;

public class GameManager : MonoBehaviour
{

    public GameObject exclamationMark;

    public Animator cameraAnimator;

    public Animator pikachuAnimator;

    private void Update()
    {
        if (Input.GetKeyDown(KeyCode.Space))
        {
            cameraAnimator.Play("Jump");

            pikachuAnimator.Play("Jump");

            exclamationMark.SetActive(true);



        }
    }
}
