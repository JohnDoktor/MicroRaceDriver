using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

public class OnScreenButton : MonoBehaviour, IPointerDownHandler, IPointerUpHandler
{
    public enum Axis { Horizontal, Vertical }
    public Axis axis = Axis.Horizontal;
    public float value = 1f; // +1 for right/forward, -1 for left/reverse

    private bool pressed;

    void Update()
    {
        if (pressed)
        {
            if (axis == Axis.Horizontal) MobileInput.AddHorizontal(value);
            else MobileInput.AddVertical(value);
        }
    }

    public void OnPointerDown(PointerEventData eventData)
    {
        pressed = true;
    }

    public void OnPointerUp(PointerEventData eventData)
    {
        pressed = false;
    }
}

