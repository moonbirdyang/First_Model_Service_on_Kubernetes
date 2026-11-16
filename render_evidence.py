"""Render recorded kubectl observations; never synthesize measurements."""
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
EVIDENCE = ROOT / "evidence"

def read(name):
    return json.loads((EVIDENCE / name).read_text(encoding="utf-8-sig"))

def esc(value):
    return html.escape(str(value))

training = json.loads((ROOT / "training-result.json").read_text(encoding="utf-8-sig"))
verification = read("verification-result.json")
history = read("hpa-history.json")
api = read("api-result.json")
rows = "".join(
    "<tr>" + "".join("<td>" + esc(row[key]) + "</td>" for key in
        ["time", "elapsedSeconds", "replicas", "readyReplicas", "cpuPercent", "jobComplete"]) + "</tr>"
    for row in history
)
snapshots = []
for label, filename in [("Before load", "before-load.json"), ("During load (peak)", "during-load.json"), ("After load", "after-load.json")]:
    record = read(filename)
    deployment = record["deployment"]["status"]
    current_metrics = record["hpa"].get("status", {}).get("currentMetrics", [])
    cpu = current_metrics[0].get("resource", {}).get("current", {}).get("averageUtilization", "unknown") if current_metrics else "unknown"
    pod_names = "<br>".join(esc(p["metadata"]["name"]) for p in record["pods"]["items"])
    snapshots.append("<section><h2>" + esc(label) + "</h2><p>" + esc(record["time"]) + "</p><p>Replicas: <b>" + esc(deployment.get("replicas", 0)) + "</b> &nbsp; Ready: <b>" + esc(deployment.get("readyReplicas", 0)) + "</b></p><p>CPU: <b>" + esc(cpu) + "%</b> / target 50%</p><p class='mono'>" + pod_names + "</p></section>")
style = """<style>body{font:17px Arial,sans-serif;margin:40px;color:#182c45;background:#f3f6fa}h1{font-size:30px}h2{font-size:21px}section{background:white;padding:20px;border:1px solid #d7e0ea;border-radius:10px;margin:18px 0}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:18px}.mono,pre{font-family:Consolas,monospace;font-size:14px}table{width:100%;border-collapse:collapse;background:white;font-size:14px}td,th{padding:8px;text-align:left;border-bottom:1px solid #d7e0ea}th{background:#16324f;color:white}.note{color:#50647b}pre{white-space:pre-wrap}</style>"""
page = "<!doctype html><meta charset='utf-8'>" + style + "<h1>Iris API on minikube — measured HPA results</h1>"
page += "<p class='note'>Recorded from kubectl JSON on profile iris-lab. Times use UTC+08:00. Original evidence is in evidence/*.json.</p>"
page += "<div class='cards'>" + "".join(snapshots) + "</div>"
page += "<section><h2>Verification</h2><pre>" + esc(json.dumps(verification, indent=2)) + "</pre></section>"
page += "<h2>Observed replica / CPU history</h2><table><tr><th>Time (UTC+08)</th><th>Elapsed (s)</th><th>Replicas</th><th>Ready</th><th>CPU (% request)</th><th>Load complete</th></tr>" + rows + "</table>"
(EVIDENCE / "hpa-report.html").write_text(page, encoding="utf-8")
api_page = "<!doctype html><meta charset='utf-8'>" + style + "<h1>Iris API — recorded verification</h1><section><h2>Training</h2><pre>" + esc(json.dumps(training, indent=2)) + "</pre></section><section><h2>HTTP request and response</h2><pre>" + esc(json.dumps(api, indent=2)) + "</pre></section>"
(EVIDENCE / "api-report.html").write_text(api_page, encoding="utf-8")
report = "# 實測作業報告\n\n"
report += "本次使用 minikube Docker driver、iris-lab profile，在本機 Kubernetes 執行 Iris RandomForest API。\n\n"
report += "- 訓練 accuracy：{}\n- MLflow run ID：{}\n- API 範例預測：{}\n- 最大副本數：{}\n- 擴容驗證：{}\n- 縮容驗證：{}\n- 觀察時間：{} 秒\n\n".format(training["accuracy"], training["run_id"], api["prediction"]["predictions"], verification["maxReplicas"], verification["scaleUpVerified"], verification["scaleDownVerified"], verification["elapsedSeconds"])
report += "負載由叢集內 hey Job 產生：180 秒、50 個並行連線、POST /predict，每次一筆四維 Iris 特徵。HPA 以 CPU request 100m 的 50% 為目標，副本範圍 1–5。\n\n"
report += "原始測量見 evidence/hpa-history.json、before-load.json、during-load.json、after-load.json；hey 的完整結果見 evidence/hey-results.txt。hpa-report.html 是由原始 kubectl JSON 整理的觀測頁面，並非終端機截圖。\n\n"
report += "## 觀察與說明\n\n負載提高 CPU 後，HPA 依採樣結果擴增副本。負載結束後不會立即縮容，需經過預設縮容穩定期；實際時間見觀測紀錄。擴容不表示模型準確率提高，而是增加可處理的並行請求能力。\n\n"
report += "## 繳交前確認\n\n檢查 screenshots 的 MLflow 與 HPA 圖片，補充個人心得並上傳 GitHub。不要上傳 .kube、.minikube、tools 等憑證或工具快取。\n"
(ROOT / "REPORT.md").write_text(report, encoding="utf-8")
print("Rendered evidence reports and REPORT.md")
