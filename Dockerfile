FROM python:3.12-slim AS training
WORKDIR /app
COPY requirements*.txt ./
RUN pip install --no-cache-dir -r requirements-train.txt
COPY train.py ./
CMD ["python", "train.py"]

FROM python:3.12-slim AS serving
WORKDIR /app
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py model.pkl ./
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
