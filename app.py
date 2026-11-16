from pathlib import Path
import joblib
from fastapi import FastAPI
from pydantic import BaseModel, Field, FiniteFloat

app = FastAPI(title="Iris prediction API")
model = joblib.load(Path(__file__).with_name("model.pkl"))

class Request(BaseModel):
    instances: list[list[FiniteFloat]] = Field(min_length=1, max_length=1000)

@app.post("/predict")
def predict(req: Request):
    from fastapi import HTTPException
    if any(len(row) != 4 for row in req.instances):
        raise HTTPException(status_code=422, detail="Each instance needs four measurements.")
    return {"predictions": model.predict(req.instances).tolist()}

@app.get("/healthz")
def healthz():
    return {"ok": True}
