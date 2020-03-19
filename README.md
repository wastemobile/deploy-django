# Django 自動化佈署準備程序

## 預先準備

1. 新建一個 Linode VPS，完成主機預整備程序（新建非 root 用戶、使用金鑰登入、禁止 root 登入、禁止密碼登入、修改 ssh port；修改時區 tzdata、設置 hostname、設置 ufw 防火牆，最後安裝 fail2ban，編寫一份自己的監獄規則 `/etc/fail2ban/jail.local`）。
2. 取回 bash scripts `git clone https://github.com/wastemobile/deploy-django.git`
3. 將 Cloudflare API credentials 寫在 `~/.secrets/cloudflare.ini`，並更改權限、提高一點安全性。

## 安裝

1. 首先執行 `sudo -H ./install_pre.sh`，會安裝各種所需的系統套件。
2. 執行 `sudo ./certbot_wildcard.sh example.com`，會呼叫 cloudflare 驗證、取得 wildcard 證書等。
3. 執行 `sudo ./deploy.sh appname example.com`

所有的應用皆會安裝在 `/webapps` 目錄下，以 `appname_project` 為名，Django 應用則安裝在 `/webapps/appname_project/appname` 目錄下（manage.py），主應用皆以 `config` 為名。

Nginx 的設定檔在 `/webapps/appname_project/nginx/appname.conf`，再 `ln-sf` 到 `/etc/nginx/sites-enabled/` 目錄。

設置好 Wsgi 與 Gunicorn 的連接（`/webapps/appname_project/service/appname.socket`），以及 systemd 管理的服務（`appname.service`），同樣 `ln -sf` 到 `/etc/systemd/system/` 目錄下。

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

## deploy_ci

添加一個持續整合更新的 deploy_ci.sh，執行時一樣輸入 $APPNAME，會自動檢查該應用是否存在。

搭配 GitHub Actions 一個最簡單的 ssh-action 就很好用了，因為不需要在每一次主分支有異動就部署，所以設置為 release published 驅動。修改 `main.yml` 後搬到 Django 專案倉儲的 `.github/workflows` 目錄。

前往 GitHub 倉儲，建立四個 secrets，分別是 HOST, USERNAME, KEY 與 PORT。

> 這也才發現原來一般使用 git tag 對 GitHub 來說並不算「正式發佈」，終端機可能得要安裝 GitHub 專用 CLI 工具 - [hub](https://github.com/github/hub) 才能做到。

若持續部署使用的是 GitHub 私人倉儲，必須讓 `appname` 用戶記得 github 的密碼（＝額外替這主機生成的 personal token），先輸入 `git config --global credential.helper store`、再執行一次 `git pull`，就會將 token 記下來了，寫在家目錄（亦即 `/webapps/appname_project/.git-credentials`）。

發布前的準備：

1. (v)pipenv lock --requirements > requirements.txt
2. (v)python manage.py collectstatic
3. git add . && git commit -m 'commit message'
4. git push

接著到 GitHub 網站（或在本機安裝 hub）進行發佈，就會自動部署新版本了。

- hub release create v0.1.5 -m 'v0.1.5 - test run'
- hub sync（這樣就發佈了，GitHub 應該會立刻執行 action 去更新主機）

> Django static files 是採用本地集結、納入 git 管理的模式，就不需要在正式機上執行這個程序，畢竟自動部署能少些步驟、減少錯誤的發生比較好。

## 異動與服務重啟

每次自動部署完、也就是 Django 專案代碼有異動（已添加新套件、migrate 後），指令會執行 `systemctl restart appname`（執行 `service appname restart` 也可以）。

如果更改了 Gunicorn socket 或 systemd service 檔案，就必須重新載入監聽器（daemon）並重啟 process：

- sudo systemctl daemon-reload
- sudo systemctl restart appname.socket appname.service

如果異動了 Nginx server block 設定：

- sudo ngint -t （檢查設定有沒有寫錯）
- sudo systemctl restart nginx

## Nginx Bad Bot Blocker 搭配 fail2ban 服用

[Nginx Bad Bot Blocker](https://github.com/mariusv/nginx-badbot-blocker/tree/master/VERSION_2)

- nginx_bad_bot_blocker.sh
- update_nginx_blocker.sh

1. 複製 blacklist.conf 到 /etc/nginx/conf.d/
2. 建立 /etc/nginx/bots.d 目錄
3. 複製 blockbots.conf 到 /etc/nginx/bots.d/
4. 複製 ddos.conf 到 /etc/nginx/bots.d/
5. 複製 whitelist-ips.conf 到 /etc/nginx/bots.d/
6. 複製 whitelist-domains.conf 到 /etc/nginx/bots.d/
7. 修改 /etc/nginx/nginx.conf
8. 在自己的 vhost block 添加：
	- `include /etc/nginx/bots.d/blockbots.conf;`
	- `include /etc/nginx/bots.d/ddos.conf;`
9. 測試設定檔是否正確： `sudo nginx -t`
10. 重新載入設定： `sudo service nginx reload`
11. 複製 nginxrepeatoffender.conf 到 /etc/fail2ban/filter.d
12. 複製 nginxrepeatoffender.conf 到 /etc/fail2ban/action.d
13. `sudo touch /etc/fail2ban/nginx.repeatoffender`
14. `sudo +x /etc/fail2ban/nginx.repeatoffender` （不明白這個檔的作用⋯⋯）
15. 修改 /etc/fail2ban/jail.local
16. 重啟 fail2ban： `sudo systemctl restart fail2ban`


```
# /etc/nginx/nginx.conf
...
server_names_hash_bucket_size 64;
server_names_hash_max_size 4096;
limit_req_zone $binary_remote_addr zone=flood:50m rate=90r/s;
limit_conn_zone $binary_remote_addr zone=addr:50m;
...
```


```
# /etc/fail2ban/jail.local
[nginxrepeatoffender]
enabled = true
logpath = %(nginx_access_log)s
filter = nginxrepeatoffender
banaction = nginxrepeatoffender
bantime  = 86400   ; 1 day
findtime = 604800   ; 1 week
maxretry = 20
```


## TODO

- 據說設定 gunicorn worker 處理請求的方式中，指定 `-k gthread` （非同步模式）能獲得較高性能，測試看看接下來是否修改。數量一般會設置為 (CPU核心數x2)+1。
- 針對次網域的新應用設置（套用相同的 Let's Encrypt 證書等）。
- （已完成）接下來應該是要搞定 Django 的持續部署。
	- 採 GitHub workflow，且設定為「正式發佈」才自動部署到主機上。
	- GitHub Action 採用最簡單的 ssh-action，苦工其實都在 deploy_ci.sh 裡進行，主要還是為了讓使用者權限等皆維持原樣。



