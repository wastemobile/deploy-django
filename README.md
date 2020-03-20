# Django 自動化佈署準備程序

研究 [deploy-django](https://github.com/harikvpy/deploy-django) 之後，部分與自己使用習慣不符，就一路修改、也增加了一些功能，目前堪用。

使用的是 Linode VPS，新建主機後須先完成 [Initial 預配置](https://gist.github.com/wastemobile/5c98e731fdd0d32d0742c2eb5f28837f)，包含新建用戶、時區、主機名稱，以及提升安全性的基礎設置。

## 可以做到下列事項

- 使用 Certbot 搭配 Cloudflare DNS plugin，自動取得 Let's Encrypt Wildcard 證書。
- 快速配置好 Django 使用 Gunicorn/WSGI，並建好 Nginx 的搭配。
- 每一個網站都設置獨立用戶名，互不干擾，自動化 git 連續部署時也比較安全。
- 自動建立 PostgreSQL 資料庫、角色、以及強密碼，連同 Django 密鑰等正式環境必要的配置，自動寫入 `.env` 環境檔中，搭配 [Django-environ](https://github.com/joke2k/django-environ) 使用。（**安裝成功後請務必備份 `.env`！**）
- 自動設置 virtual 虛擬環境，安裝必要的基礎套件，同時拉回 [django-project-template](https://github.com/wastemobile/django-project-template) 建立 Django 雛型網站。
- 配置好使用 systemd 管理 WSGI 進程的服務機制。
- 提供獨立用戶自動連續部署的 script，提供已受限的服務重啟指令權限，提供可利用 GitHub Actions 自動達成 automated git deployment 的腳本。

> 欲使用 Certbot wildcard 自動機制，需先設置 `~/.secrets/cloudflare.ini`；若檔案不存在，就會複製預設範本、停止執行，請加入 cloudflare Global API Key 後再次執行。
> 會在獨立用戶的家目錄下添加 `.gitconfig` 與 `.git-credentials`，能讓後續從私人倉儲執行自動化佈署時不被阻斷，欲使用此功能請先至 GitHub 生成獨立的 personal token 填入。

**白話一點說：**

1. 新建一台 vps、初始設置完成後，拉回這個腳本倉儲，執行 `install_pre.sh` 就立刻成為能申請 SSL Wildcard 證書、能跑 Django + PostgreSQL + Nginx 的正式環境。
2. 由 Cloudflare 管理網域；執行 `cerbot_wildcard.sh <domain>` 就能自動申請 Let's Encrypt Wildcard SSL 證書。
3. 執行 `deploy.sh <domain>` ，30 秒自動建立 Django 網站（主網域）。

接下來可重複執行 (2), (3) 步驟，增加不同網域的 Django 應用；或使用 `deploy_sub.sh <sub.domain>` 建立與主網域使用相同 SSL 證書的次網域 Django 網站。

## 使用方式

### 主機安裝（install_pre.sh）

在已完成初始設定的 Ubuntu 18.04 主機，以正常用戶登入，並在家目錄執行 `git clone https://github.com/wastemobile/deploy-django.git`，複製自動化代碼到主機上。

**僅適用於 Python 3（Ubuntu 18.04 目前預設為 3.6.9）**

**執行 `$ sudo -H ./install_pre.sh`**

會自動安裝好所有需要的程式套件（添加 certbot 套件庫時、終端機會提示一次確認訊息，按下 `enter` 繼續即可完成）。

### 申請 Let's Encrypt Wildcard 證書（certbot_wildcard.sh）

**執行 `$ sudo ./certbot_wildcard.sh yourdomain.com`**

實際執行指令為 `certbot certonly --dns-cloudflare --dns-cloudflare-credentials ~/.secrets/cloudflare.ini -d $DOMAINNAME,*.$DOMAINNAME --preferred-challenges dns-01 -i nginx`。

過程中需要輸入電郵、確認兩個提問，接著自動向 cloudflare DNS 發出驗證請求。會產生下面的檔案：

- /etc/letsencrypt/live/yourdomain.com/fullchain.pem
- /etc/letsencrypt/live/yourdomain.com/privkey.pem
- /etc/letsencrypt/options-ssl-nginx.conf
- /etc/letsencrypt/ssl-dhparams.pem

僅適用 Cloudflare DNS 且須預先設置好 `~/.secert/cloudflare.ini`；若該檔案不存在，腳本會自動複製範本到該目錄，請查詢 cloudflare Global API key 填入後再次執行。

如欲搭配其他 DNS 服務，請先查詢需要安裝的 [DNS Plugins](https://certbot.eff.org/docs/using.html#dns-plugins)與 API key 設置方式，自行安裝需要套件並修改腳本。

> 後續若想以 blog.yourdomain.com 新增額外的 Django 網站，就無需再次申請憑證。

成功取得證書後，請手動執行 `sudo certbot renew --dry-run` ，就會設置好每日的更新檢查、自動續命。

## 建立主網域的 Django 網站（deploy.sh）

**執行 `$ sudo ./deploy.sh yourdomain.com`**

完成後開瀏覽器前往 `https://yourdomain.com`，就會看到正常運行的 Django 網站。

網站統一建置在 `/webapps` 目錄，名稱即為 `/webapps/yourdomain_project`，這裡會擺放 virtualenv 虛擬環境、各種設定、logs 紀錄等，同時也是 `yourdomain` 這個獨立用戶的家目錄。

Django 應用在 `/webapps/yourdomain_project/yourdomain` 目錄，也就是應該設置讓 git 管理的目錄（已經擺好 `.gitignore` 與 `.github/workflows/main.yaml` GitHub Actions 自動化腳本）。

> 並未執行 migrate、建立 superuser 與 collectstatic，因此瀏覽管理後台會顯示不正常。

Nginx 的設定檔在 `/webapps/yourdomain_project/nginx/yourdomain.conf`，軟連結到 `/etc/nginx/sites-enabled/` 目錄。已設好 Wsgi 與 Gunicorn 的連接（`/webapps/yourdomain_project/service/yourdomain.socket`），以及 systemd 管理的服務（`yourdomain.service`），同樣 `ln -sf` 到 `/etc/systemd/system/` 目錄下。

## 建立次網域的 Django 網站（deploy_sub.sh）

前提是已經執行過 `certbot_wildcard` 、也就是已在主機上完成了 Wildcard SSL 設置。

程序與建主網域網站幾乎相同，輸入 `sudo ./deploy_sub.sh cyber.punk.com`：

1. 建立了 cyber_punk 用戶（同樣是 webapps 群組）。
2. 專案位於 `/webapps/cyber_punk_proj` ，Django 網站在 `/webapps/cyber_punk_proj/cyber_punk` 目錄。
3. Nginx 使用 `punk.com` 相同的證書設置。

## Automated Git Deploy

用於持續整合更新的 deploy_ci.sh 已擺放在專案目錄，搭配 GitHub Actions 一個最簡單的 ssh-action 就很好用了，不希望過於頻繁地在主分支異動就部署，所以設置為 release published 驅動。

前往 GitHub 倉儲，建立四個 secrets，分別是 HOST, USERNAME, KEY 與 PORT，金鑰若有 passphrase 保護，除了新增一個 secret 外，main.yaml 腳本也要添加一下。

> 這也才發現原來一般使用 git tag 對 GitHub 來說並不算「正式發佈」，使用 `brew install hub` 安裝 GitHub 專用 CLI 工具 - [hub](https://github.com/github/hub) 就能簡單做到從終端機直接發佈。

若持續部署使用的是 GitHub 私人倉儲，必須讓專屬用戶記得 github 的密碼（＝額外替這主機生成的 personal token），先輸入 `git config --global credential.helper store`、再執行一次 `git pull`，就會將 token 記下來了，密碼會寫在家目錄下（亦即 `/webapps/appname_project/.git-credentials`）。

發布前的準備：

1. (v)pipenv lock --requirements > requirements.txt
2. (v)python manage.py collectstatic
3. git add . && git commit -m 'commit message'
4. git push
5. hub release create v0.1.5 -m 'v0.1.5 - blog page online'
6. hub sync

GitHub Actions 就幫忙自動部署 Django project 的新版本到正式環境了。

> Django static files 是採用本地集結、納入 git 管理的模式，就不需要在正式機上執行這個程序，畢竟自動部署能少些步驟、減少錯誤的發生比較好。

## 異動與服務重啟

每次自動部署完、也就是 Django 專案代碼有異動（已添加新套件、migrate 後），腳本會自動執行 `systemctl restart appname`（執行 `service appname restart` 也可以）。

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
- （done）針對次網域的新應用設置（套用相同的 Let's Encrypt 證書等）。
- （done）接下來應該是要搞定 Django 的持續部署。
	- 採 GitHub workflow，且設定為「正式發佈」才自動部署到主機上。
	- GitHub Action 採用最簡單的 ssh-action，苦工其實都在 deploy_ci.sh 裡進行，主要還是為了讓使用者權限等皆維持原樣。



