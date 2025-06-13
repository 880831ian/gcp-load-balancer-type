# gcp-load-balancer-type

## 說明

此腳本可以快速掃描 GCP Load Balancer 類型，詳細類型說明，可以參考：[GCP Load Balancer 介紹](https://pin-yi.me/blog/gcp/gcp-lb-introduce/)

<br>

## 使用

執行 run.sh 腳本，並於後面帶上想要查詢的 GCP Project ID，會先檢查是否有安裝 gcloud、是否已登入 gcloud、檢查是否安裝 jq。

<br>

![圖片](https://raw.githubusercontent.com/880831ian/gcp-load-balancer-type/master/images/1.png)

<br>

若沒有指定，則會選擇 config 中的 Project 來搜尋

<br>

![圖片](https://raw.githubusercontent.com/880831ian/gcp-load-balancer-type/master/images/2.png)

<br>