# Django 自動化佈署準備程序

新建一個 Linode VPS，完成主機預整備程序（新建非 root 用戶、基礎安全防護等）。

`git clone https://github.com/wastemobile/deploy-django.git`

將 Cloudflare API credentials 寫在 `~/.secrets/cloudflare.ini`，並更改權限、提高一點安全性。

1. 首先執行 `sudo -H ./install_pre.sh`，會安裝各種所需的系統套件。
2. 執行 `sudo ./certbot_wildcard.sh example.com`，會呼叫 cloudflare 驗證、取得 wildcard 證書等。
3. 執行 `sudo ./deploy.sh appname example.com`

## install_pre

`$ sudo -H ./install_pre.sh`

1. 添加 'universe' 'ppa:certbot/certbot' 兩個 certbot 需要的套件倉儲。
2. 安裝 'git' 'build-essential' 'python3-dev' 'python3-pip' 'nginx' 'postgresql' 'postgresql-contrib' 'libpq-dev' 'software-properties-common' 'certbot' 'python-certbot-nginx' 'python3-certbot-dns-cloudflare' 這些套件
3. 升級 pip3 後，僅安裝 'virtualenv' 一個必要套件

自動取得的 Let's Encrypt 證書為 wildcard 模式，透過安裝 DNS plugin 自動去向 cloudflare DNS 驗證，若使用不同註冊商就需要修改安裝的 dns-plugin 套件，也需要確認 API。

## certbot_wildcard

`$ sudo ./certbot_wildcard.sh example.com`

實際執行指令為 `certbot certonly --dns-cloudflare --dns-cloudflare-credentials ~/.secrets/cloudflare.ini -d $DOMAINNAME,*.$DOMAINNAME --preferred-challenges dns-01 -i nginx`。

過程中需要輸入電郵、確認兩個提問，接著自動向 cloudflare DNS 發出驗證請求。會產生下面的檔案：

- /etc/letsencrypt/live/example.com/fullchain.pem
- /etc/letsencrypt/live/example.com/privkey.pem
- /etc/letsencrypt/options-ssl-nginx.conf
- /etc/letsencrypt/ssl-dhparams.pem

後續會根據這四個檔案名稱、位置，去修改 Nginx 的設定；注意若在同一台主機上重複執行相同網域的證書取得，會產生類似 `/etc/letsencrypt/live/example.com-0001/fullchain.pem`...這樣的不同檔案，就必須手動去修改 Nginx 設定。

## deploy

`$ sudo ./deploy.sh appname example.com`

這程序會做很多事：

1. 建立 `/webapps/appname_project` 專案目錄。
2. 新增 appname 用戶與 webapps 群組，appname 的家目錄即為專案目錄。
3. 建立 python virtualenv 虛擬環境。
4. 自動安裝 'django' 'django-environ' 'psycopg2-binary' 'gunicorn' 'setproctitle' 等套件。
5. 建立 `/webapps/appname_project/appname` Django 專案的目錄。
6. 從 GitHub 抓取 [django-project-template](https://github.com/wastemobile/django-project-template/archive/master.zip) 產生基礎架構，包含使用 django-environ 的多重設置環境。
7. 自動產生 Django Secret Key 與 PostgreSQL 強密碼，並將密碼連同 Django 正式環境需要的基本配置，寫入 `config/.env` 檔案中。
8. 自動建立 PostgreSQL 使用者與資料庫（使用上列的強密碼）。
9. 自動建立執行 Gunicorn 需要的 socket 檔案，配置同名 service 檔，使用 systemd 管理進程。
10. 自動設置 Nginx conf。

根據上面三步驟執行完、若沒有出錯，直接瀏覽 `https://example.com` 就會看到 Django 網站。

- 備份 `/webapps/appname_project/appname/config/.env`。
- 添加 git 倉儲、或以本地的 django repo 替換。

## TODO

接下來應該是要搞定 Django 的持續部署。

- 採 GitHub workflow，主分支若有更新，就自動部署到主機上。
- 需執行 migrate 程序。



