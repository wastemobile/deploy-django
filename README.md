# Django 自動化佈署準備程序

新建一個 Linode VPS，完成主機預整備程序（新建非 root 用戶、基礎安全防護等）。

將 Cloudflare API credentials 寫在 `~/.secrets/cloudflare.ini`，並更改權限、提高一點安全性。

1. 首先執行 `sudo ./install_pre.sh`，會安裝各種所需的系統套件。
2. 執行 `sudo ./certbot_wildcard.sh yourdomain.com`，會呼叫 cloudflare 驗證、取得 wildcard 證書等。
3. 執行 `sudo ./deploy.sh project_name yourdomain.com`