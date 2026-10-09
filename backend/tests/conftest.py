# ===================================================
# 単体テストの共通設定
#
# ・本物の AWS（DynamoDB）・OpenAI・株価API には一切つながない。
#   つながりそうな所は FakeTable / FakeOpenAI などの偽物に差し替える。
#   → テストは何回流してもタダ・数秒で終わる・ネットワークが無くても動く
# ・backend/ を import パスに入れて、本番と同じ `from services.xxx import ...` で読めるようにする
# ===================================================

import os
import sys
from pathlib import Path

import pytest

BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_DIR))

# services/cache.py は import した瞬間に boto3 の DynamoDB リソースを作る。
# 作るだけなら通信しないが、リージョン・認証情報が無いと環境によってはエラーになるので
# ダミーを入れておく（本物の鍵が入っている環境でも、テストでは上書きして使わせない）。
os.environ["AWS_DEFAULT_REGION"] = "ap-northeast-1"
os.environ["AWS_ACCESS_KEY_ID"] = "testing"
os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
os.environ.pop("AWS_SESSION_TOKEN", None)
os.environ.pop("AWS_PROFILE", None)


class FakeTable:
    """
    DynamoDB の Table の偽物。

    [scan_pages] scan() を呼ばれるたびに順番に返すレスポンスのリスト
                 （ページング＝何回かに分けて返ってくる動きを再現する）
    [item]       get_item() で返す1件
    """

    def __init__(self, scan_pages=None, item=None):
        self.scan_pages = list(scan_pages or [])
        self.item = item
        self.scan_calls = []
        self.put_calls = []
        self.update_calls = []

    def scan(self, **kwargs):
        self.scan_calls.append(dict(kwargs))
        return self.scan_pages[len(self.scan_calls) - 1]

    def get_item(self, Key):
        return {"Item": self.item} if self.item is not None else {}

    def put_item(self, Item):
        self.put_calls.append(Item)

    def update_item(self, **kwargs):
        self.update_calls.append(kwargs)


@pytest.fixture
def fake_table():
    return FakeTable
