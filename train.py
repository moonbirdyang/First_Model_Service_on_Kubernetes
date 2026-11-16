import json
from pathlib import Path
import joblib
import mlflow
import mlflow.sklearn
from mlflow.models import infer_signature
from sklearn.datasets import load_iris
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split

ROOT = Path(__file__).resolve().parent
mlflow.set_tracking_uri("sqlite:///mlflow.db")
mlflow.set_experiment("iris")
X, y = load_iris(return_X_y=True)
Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.2, random_state=42, stratify=y)
with mlflow.start_run() as run:
    model = RandomForestClassifier(n_estimators=100, random_state=42, n_jobs=1)
    model.fit(Xtr, ytr)
    accuracy = model.score(Xte, yte)
    mlflow.log_params({"n_estimators": 100, "random_state": 42, "test_size": 0.2})
    mlflow.log_metric("accuracy", accuracy)
    mlflow.sklearn.log_model(model, "model", signature=infer_signature(Xtr, model.predict(Xtr)), input_example=Xtr[:2])
    joblib.dump(model, ROOT / "model.pkl")
    result = {"run_id": run.info.run_id, "accuracy": accuracy, "sample_prediction": model.predict([[5.1, 3.5, 1.4, 0.2]]).tolist()}
    (ROOT / "training-result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
