# ===================================================
# アップデート告知API
#
# 告知の内容は config/notices.py に定数で持っている。
# バックエンドをデプロイするだけで、アプリを更新しなくても
# 全ユーザーに告知が届く。
# ===================================================

from fastapi import APIRouter

from config.notices import get_notices, latest_version

router = APIRouter()


@router.get("/notices")
def list_notices(since: int = 0):
    """
    アップデート告知を返す。

    [since] この値より大きい version の告知だけを返す。
            アプリは保存済みの既読バージョンを渡して未読分を取得する。
            0（既定）を渡すと全件返るので、お知らせ履歴の表示にも使える。

    戻り値の notices は version の小さい順（古い順）。
    アプリはこの順にポップアップを1件ずつ表示する。
    """
    return {
        "latest_version": latest_version(),
        "notices": get_notices(since),
    }
