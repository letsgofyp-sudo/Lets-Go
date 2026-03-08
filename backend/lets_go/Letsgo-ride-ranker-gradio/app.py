import gradio as gr

from MLRankerCode import RankRequest, rank_rides


def predict(payload: dict):
    req = RankRequest.model_validate(payload)
    res = rank_rides(req=req, authorization=None)
    return res.model_dump()


demo = gr.Interface(
    fn=predict,
    inputs=gr.JSON(label="RankRequest payload"),
    outputs=gr.JSON(label="RankResponse"),
)

if __name__ == "__main__":
    demo.launch(server_name="0.0.0.0", server_port=7860)