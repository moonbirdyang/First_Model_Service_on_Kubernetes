# 實測作業報告

本次使用 minikube Docker driver、iris-lab profile，在本機 Kubernetes 執行 Iris RandomForest API。

- 訓練 accuracy：0.9
- MLflow run ID：405ddd13709b429f8f650f28c6fdf18e
- API 範例預測：[0]
- 最大副本數：5
- 擴容驗證：True
- 縮容驗證：True
- 觀察時間：620 秒

負載由叢集內 hey Job 產生：180 秒、50 個並行連線、POST /predict，每次一筆四維 Iris 特徵。HPA 以 CPU request 100m 的 50% 為目標，副本範圍 1–5。

原始測量見 evidence/hpa-history.json、before-load.json、during-load.json、after-load.json；hey 的完整結果見 evidence/hey-results.txt。hpa-report.html 是由原始 kubectl JSON 整理的觀測頁面，並非終端機截圖。

## 觀察與說明

負載提高 CPU 後，HPA 依採樣結果擴增副本。負載結束後不會立即縮容，需經過預設縮容穩定期；實際時間見觀測紀錄。擴容不表示模型準確率提高，而是增加可處理的並行請求能力。

## 繳交前確認

檢查 screenshots 的 MLflow 與 HPA 圖片，補充個人心得並上傳 GitHub。不要上傳 .kube、.minikube、tools 等憑證或工具快取。
