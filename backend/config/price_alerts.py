# ===================================================
# 株価アラート（指定の株価になったらプッシュ通知）の設定
#
# ユーザーがアプリで「銘柄・条件・金額」を登録し、EventBridge Scheduler が
# 5分おきに Lambda を起こして判定する（services/price_alerts.py）。
# 通知は Firebase Cloud Messaging（FCM）で iPhone に送る（services/push.py）。
#
# 株価は yfinance なので、日本株は約20分遅れる。アプリの画面にも書いている。
# ===================================================

import os

# 1人が登録できるアラートの数
MAX_ALERTS_PER_USER = 10

# 条件の種類（アプリの lib/models/price_alert.dart の PriceAlertCondition と同じ値）
#   price_above      : 株価が target 以上になったら
#   price_below      : 株価が target 以下になったら
#   change_pct_above : 前日比が +target% 以上になったら（急騰）
#   change_pct_below : 前日比が -target% 以下になったら（急落）。target は正の数で持つ
CONDITION_PRICE_ABOVE = "price_above"
CONDITION_PRICE_BELOW = "price_below"
CONDITION_CHANGE_UP = "change_pct_above"
CONDITION_CHANGE_DOWN = "change_pct_below"
CONDITIONS = (CONDITION_PRICE_ABOVE, CONDITION_PRICE_BELOW, CONDITION_CHANGE_UP, CONDITION_CHANGE_DOWN)

# 繰り返し
#   daily : 条件を満たしている間、1日1回まで通知する
#   once  : 1回通知したら自動で OFF にする
REPEAT_DAILY = "daily"
REPEAT_ONCE = "once"
REPEATS = (REPEAT_DAILY, REPEAT_ONCE)

# 前日比の条件で受け付ける % の上限（入力ミスで 1000% などを入れないように）
MAX_CHANGE_PCT = 50

# 判定のときに yfinance を同時に呼ぶ数（routers/stock.QUOTES_MAX_WORKERS と同じ考え方）
PRICE_ALERT_MAX_WORKERS = 8

# EventBridge Scheduler から Lambda に渡す合図（lambda_handler.py が見分ける）
PRICE_ALERT_TASK = "price_alert_check"

# ===================================================
# 市場が開いている時間（この時間の外では株価を見ない）
# ===================================================
# 東証：前場 9:00〜11:30、後場 12:30〜15:30（2024年11月から15:30まで）。
# 株価は約20分遅れるので、引けの値まで拾えるよう終わりに余裕を足す
JP_SESSIONS = (((9, 0), (11, 30)), ((12, 30), (15, 30)))
# 米国：9:30〜16:00（ニューヨーク時間）
US_SESSIONS = (((9, 30), (16, 0)),)
# 終わりの時刻に足す余裕（分）。遅れて届く株価を拾うため
SESSION_GRACE_MINUTES = 25

# ===================================================
# FCM（Firebase Cloud Messaging）
# ===================================================
# Firebase のプロジェクトID（秘密ではない）
FCM_PROJECT_ID = os.getenv("FCM_PROJECT_ID", "")
# サービスアカウントの鍵（JSON）を置いた SSM パラメータストアの名前。
# 鍵は 2KB 以上あり、Lambda の環境変数（全部で4KBまで）に入れると他のキーと合わせて
# 上限を超えるおそれがあるので、パラメータストア（SecureString・無料）に置く
FCM_SERVICE_ACCOUNT_PARAM = os.getenv("FCM_SERVICE_ACCOUNT_PARAM", "/stock-app/fcm-service-account")
FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"

# 端末の宛先（FCM トークン）を保存しておく日数。
# アプリは起動のたびに送り直すので、しばらく使われていない端末のものは自動で消す
PUSH_TOKEN_TTL_DAYS = 60
