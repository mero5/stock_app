# ===================================================
# Lambda エントリポイント
# FastAPI アプリ（main.py）を Mangum で Lambda 用に変換する
# ===================================================

from mangum import Mangum

from main import app

# lifespan="auto" で main.py の startup（銘柄マスタ取得）がコールドスタート時に走る
handler = Mangum(app, lifespan="auto")
