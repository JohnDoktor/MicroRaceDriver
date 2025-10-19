using UnityEngine;
using UnityEngine.UI;

public class BuildOverlay : MonoBehaviour
{
    void Awake()
    {
        DontDestroyOnLoad(gameObject);
    }

    public static void Create()
    {
        var go = new GameObject("BuildOverlay");
        var canvas = go.AddComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        var scaler = go.AddComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920, 1080);
        go.AddComponent<GraphicRaycaster>();

        // Panel
        var panel = new GameObject("Panel");
        panel.transform.SetParent(go.transform, false);
        var prt = panel.AddComponent<RectTransform>();
        prt.anchorMin = new Vector2(0f, 1f);
        prt.anchorMax = new Vector2(0f, 1f);
        prt.pivot = new Vector2(0f, 1f);
        prt.anchoredPosition = new Vector2(12f, -12f);
        prt.sizeDelta = new Vector2(420f, 48f);
        var pimg = panel.AddComponent<Image>();
        pimg.color = new Color(0f, 0f, 0f, 0.4f);

        // Text
        var txtGO = new GameObject("Text");
        txtGO.transform.SetParent(panel.transform, false);
        var trt = txtGO.AddComponent<RectTransform>();
        trt.anchorMin = Vector2.zero;
        trt.anchorMax = Vector2.one;
        trt.offsetMin = trt.offsetMax = Vector2.zero;
        var text = txtGO.AddComponent<Text>();
        text.font = Resources.GetBuiltinResource<Font>("Arial.ttf");
        text.alignment = TextAnchor.MiddleLeft;
        text.color = Color.white;
        text.fontSize = 24;
        text.horizontalOverflow = HorizontalWrapMode.Overflow;

        string buildNum = "?";
        var ta = Resources.Load<TextAsset>("build_number");
        if (ta != null) buildNum = ta.text.Trim();
        text.text = $"Aerial Rush  v{Application.version}  b{buildNum}";

        go.AddComponent<BuildOverlay>();
    }

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    static void RuntimeCreate()
    {
        if (FindObjectOfType<BuildOverlay>() == null)
            Create();
    }
}

