# コーディング規約

stock_app のコードの書き方の決まり。**コードを変える前に読み、これに沿って書く。**
チャット（作業者）が変わっても、名前の付け方や書き方がそろうようにするためのもの。

- 置き場所・層の決まり・共通部品の一覧は [ARCHITECTURE.md](ARCHITECTURE.md)
- 規約にないことは、近くの既存コードに合わせる。新しい決まりができたら、ここに追記する（「8. この規約の育て方」）

---

## 0. 直す前にやること（影響調査・裏取り。省略禁止）

バグ修正・機能追加・改善など、**コードを変える前に毎回、次の順でやる。** 目的は、直したつもりで別の場所を壊すこと（デグレ）を防ぎ、バグを増やさないこと。

1. **目的・背景を理解する**：何が困っているか・なぜ必要か・変更後どうなっていてほしいかを確かめる。わからなければオーナーに聞く。要件（変更後の状態、やらないこと）を短い文章にまとめる
2. **現状をソースコードで確かめる**：このファイルや ARCHITECTURE.md・設計メモを読むのは前提。ただし **md は「地図」であって正解ではない。** 「こう書いてあるからこう直す」はしない。必ず main の最新コードを読んで裏を取る。md とコードが食い違っていたら、コードを正として md を直す（報告もする）
3. **影響調査をする（毎回・小さな修正でも必ず）**：変える関数・API・データ項目について、次を全部調べる
   - 呼び出し元・使っている側（`grep` で `backend/` と `lib/` の両方を検索する）
   - フロントとバックの受け渡し（JSON のキー名・型・null のとき）
   - DynamoDB の項目・キャッシュキー（古い形のキャッシュが残っていないか）、プロンプト（`PROMPT_VERSION`）、お知らせ（`config/notices.py`）
   - 単体テスト（`backend/tests/`・`test/`）と E2E（`stock-app-e2e`）で、その動きを前提にしているもの
   - 開いている他のPR（`gh pr list` で差分を見て、同じ場所を触っていないか）
   - [ARCHITECTURE.md](ARCHITECTURE.md) の「ここを変えたら、ここも直す」表
4. **直す前に提示して OK をもらう**：要件・原因・影響範囲（調べた場所と「影響なし」と判断した根拠）・修正方針をまとめて見せる
5. **直したあとに確かめる**：影響調査で挙げた場所が壊れていないかを、テスト（単体テスト・CI、必要なら E2E）で確認する。再発を防ぐテストも足す
6. **調べた内容を残す**：PR本文の「影響範囲・リスク」に、どこを調べたか（ファイル名:行）・何を確認したか・影響なしと判断した根拠を書く

**「たぶん影響ない」「設計書にそう書いてあるから」で済ませない。** 根拠（ファイル名:行、実行したコマンドと結果）を必ず示す。

---

## 1. 名前の付け方

### Python（backend/）

| 対象 | 形式 | 例 |
|---|---|---|
| ファイル・モジュール | `snake_case.py` | `market_data.py` |
| 関数・変数 | `snake_case` | `cache_get`, `today_jst` |
| モジュールの中だけで使う関数 | 先頭に `_` | `_to_decimal` |
| 定数（設定値） | `UPPER_SNAKE_CASE` | `JQUANTS_TIMEOUT`, `PROMPT_VERSION` |
| クラス | `UpperCamelCase` | `NanSafeEncoder` |
| APIのパス | `/名詞/snake_case` | `/stock/swing_analysis`, `/market/sectors` |
| JSONのキー（APIの入出力） | `snake_case` | `change_pct`, `error_type` |

### Dart（lib/）

| 対象 | 形式 | 例 |
|---|---|---|
| ファイル | `snake_case.dart` | `stock_service.dart` |
| 画面 | `xxx_screen.dart` / `XxxScreen` | `detail_screen.dart` / `DetailScreen` |
| ViewModel | `xxx_viewmodel.dart` / `XxxViewModel` | `home_viewmodel.dart` / `HomeViewModel` |
| サービス | `xxx_service.dart` / `XxxService` | `stock_service.dart` / `StockService` |
| クラス・enum | `UpperCamelCase` | `ErrorDialog` |
| 関数・変数・定数 | `lowerCamelCase` | `getAccuracyStats`, `aiTimeout` |
| 非公開（ファイル内だけ） | 先頭に `_` | `_load` |

### 共通

- **意味が分かる名前にする。** `data` `tmp` `res2` `flag` のような名前は、範囲が数行で済むときだけ
- **単位・形式が紛らわしい値は名前に入れる。** 例：`ttl_minutes`、`timeout_sec`、`change_pct`
- **銘柄コードは形式が分かる名前にする**（3形式あるため）

  | 形式 | 例 | 名前の例 |
  |---|---|---|
  | J-Quants・ウォッチリスト（5桁） | `72030` | `code5` |
  | 画面表示（4桁） | `7203` | `code` / `display_code` |
  | yfinance | `7203.T` | `ticker` / `ticker_code` |

  英字入りのコード（`285A0` / `285A` / `285A.T`）もある。日本株かどうかの判定・変換は `isdigit()` や正規表現を書かず、`services/stock_code.py`（アプリは `lib/utils/stock_code.dart`）を使う

- bool は `is_` / `has_` / `can_`（Dart は `is` / `has` / `can`）で始める。例：`is_loading`、`hasValidSession`
- 同じものには、ファイルが違っても同じ名前を使う（バックエンドの `change_pct` を Dart で `changePercent` と呼び替えない。Dart 側で受けるときも JSON のキーはそのまま使う）

---

## 2. 書き方（リーダブルコード）

- **1つの関数は1つの仕事。** 目安は50行。超えそうなら、意味のあるまとまりで関数に分ける
- **ネストは浅く。** 失敗・対象外のケースを先に `return` する（早期リターン）
- **マジックナンバー（意味の分からない数字）を書かない。** 設定値は名前を付けて `config/` か、ファイル先頭の定数にする
  - ✕ `timeout=30`　○ `timeout=JQUANTS_TIMEOUT`
- **同じ処理を2か所以上に書かない。** 2回目に書きたくなったら、共通部品にできないか先に [ARCHITECTURE.md](ARCHITECTURE.md) の一覧を見る
- **使わなくなったコードは消す。** コメントアウトで残さない（履歴は Git に残る）
- import はファイルの先頭にまとめる。同じものを2回 import しない
- Python は PEP 8（インデント4スペース）。Dart は `dart format` の形
- **整形（インデントや改行だけの変更）を、機能の修正PRに混ぜない。** 差分が読めなくなり、他のPRとコンフリクトする

---

## 3. コメント

- **「何をしているか」ではなく「なぜそうしているか」を日本語で書く。** コードを読めば分かることは書かない
- 過去に事故った・ハマったことがある箇所は、**その経緯をコメントに残す**（例：`services/clock.py`、`services/market_data.py` の冒頭）
- ファイル・大きなまとまりの先頭には、既存コードと同じ見出しを付ける

  ```python
  # ===================================================
  # 見出し（このファイル/まとまりの役割）
  #
  # なぜこうしているか・使うときの注意
  # ===================================================
  ```

  ```dart
  // ============================================================
  // クラス名
  // 役割の説明
  // ============================================================
  ```

- 関数には短い docstring（Python）/ `///` コメント（Dart）を付ける。引数や戻り値に注意点があれば書く
- 「あとで直す」は `TODO:` で書き、課題ID（`K-xx`）があれば添える

---

## 4. エラーの扱い

### バックエンド

- **AI分析系のAPIは、失敗しても HTTP 200 + `{error, error_type, error_detail}` で返す。** `routers/ai.py` の `classify_error()` + `error_response()` を使う。例外をそのまま投げて素の500にしない（アプリが結果として扱ってしまう）
- **データ取得（yfinance・J-Quants など）も `try` の中に入れる。** `try` の外で落ちると素の500になる
- **例外を握りつぶさない。** `except` で処理を続けるときも、必ず `print(f"〇〇エラー: {e}")` でログに残す（Lambda では CloudWatch Logs に出る）
- `except:` ではなく `except Exception as e:` と書く

### アプリ（Flutter）

- **失敗したら必ずユーザーに見せる。** `widgets/error_dialog.dart`（`ErrorDialog.show`）か `widgets/api_error_banner.dart` を使う。「失敗したのに画面に何も出ない」を作らない
- バックエンドの成否は**ステータスコードではなく `error` キーの有無**で判定する
- ログイン状態の判定は `isSignedIn` ではなく `AuthService.hasValidSession()` を使う
- `showDialog` を続けて出すときは `await` し、1件ごとに `context.mounted` を確認する

---

## 5. 外部サービス・時刻・データ

詳しい理由は [ARCHITECTURE.md](ARCHITECTURE.md) の「共通部品」。ここは守ることだけ。

- **時刻・日付** → `services/clock.py` の `now_jst()` / `today_jst()` / `JST`。`datetime.now()` / `date.today()` を直接使わない
- **外部APIの呼び出し** → 必ずタイムアウトを付ける。値は `config/timeouts.py` に定数で置く
- **yfinance の `history()` / `download()` の結果** → 必ず `services/market_data.drop_empty_rows()` を通す
- **DynamoDB のキャッシュ** → `services/cache.py` の `cache_get()` / `cache_set()` を使う。**中身の形（項目名・単位）を変えたらキャッシュキーの版を上げる**（例：`macro` → `macro_v2`）
- **DynamoDB の `scan`** → `Limit` は絞り込みの前に効く。ページングして、条件に合った件数で打ち切る
- **AIのプロンプトを変えた** → `services/technical.py` の `PROMPT_VERSION` を上げる
- **OpenAI を呼ぶ** → モデル名は `config/ai_models.py` の定数を使う（直書きしない）。出力の上限は `max_tokens` を直接書かず、`services/openai_params.py` の `openai_limit_params()` を `**` で渡す（GPT-5系は `max_tokens` を受け付けず、思考トークンも上限に数えられるため）
- **年ごとに変わる公式の日程など** → コードに直書きせず `config/` に切り出す
- **APIキー・秘密の値** → `.env`（環境変数）から読む。コードやドキュメントに書かない（このリポジトリは公開）

---

## 6. リファクタリング（コードの整理）

- **機能の修正・追加と混ぜない。** 整理は `chore/refactor-…` の別PRにする
  - 理由：差分が大きくなってレビューできない／他のPRとコンフリクトする／バグが出たときにどの変更が原因か分からない
- **動き（入出力）を変えない。** 変えてしまう場合はリファクタリングではなく `fix` / `feat` として出す
- **前後でテストが通ることを確認する**（`python -m pytest`、`flutter analyze --no-pub`）。テストが無い箇所は、確認した手順をPRに書く
- 機能PRの中でやってよいのは、**今回触る関数の中だけ**の小さな整理（名前の付け直し、重複の共通化など）まで
- 開いているPRが多いときは、大きな整理（ファイル分割・全体の整形）をしない。マージが終わってから出す
- 大きいファイル（`detail_screen.dart` など）に機能を足すときは、新しい部分をなるべく `lib/widgets/` に別ファイルとして切り出す（[ARCHITECTURE.md](ARCHITECTURE.md) の「大きいファイルの扱い」）

---

## 7. テスト

- **バグを直したら、再発を防ぐテストを足せないか考える**
  - 関数単位で確かめられる → `backend/tests/` に pytest
  - 画面やAPIの通しで確かめる → E2Eテストのリポジトリ（`mero5/stock-app-e2e`）
- 外部API（yfinance・OpenAI など）を呼ぶテストは、呼び出し部分を差し替えて（モック）ネットワーク無しで動くようにする
- 画面の文言（ボタン名など）を変えたら、E2Eの画面テストも直す必要がある。PRの「影響範囲」に書く

---

## 8. この規約の育て方

- レビューで指摘されたこと、作業中に「これは毎回守るべき」と分かったことは、**そのPRの中で**この規約か ARCHITECTURE.md に追記する
- 新しい決まりが古い決まりを置き換えるときは、古い記述を書き換える（矛盾する記述を残さない）
- 規約と違う既存コードを見つけても、その場で直さない。まとめて `chore/refactor-…` で直す（6章）

---

## 9. 自動チェック（CI）

- PR #21（`chore/ci-unit-tests`）で、PR のたびに GitHub Actions が `pytest`（backend）と `flutter analyze` / `flutter test` を自動で実行する。**CI が赤（失敗）のPRはマージしない**
- 自動整形（Python：`ruff`、Dart：`dart format`）はまだ入れていない。全ファイルの書き方が一気に変わり、開いているPRが全部コンフリクトするため、**開いているPRが無いときに別PRで** CI に追加する予定
- 入れたら、この章を「CI で自動チェックしている内容」に書き換える
- **`ci.yml` のジョブ名（`name:`）を変えない。** GitHub のルールセット「main を守る」で `backend（pytest）` と `flutter（analyze・test）` が必須チェックになっている。名前を変えると必須チェックが来なくなり、すべてのPRがマージできなくなる。変えるときはルールセットも同時に直す

### PRのプレビュー（Web版で画面を確認する）

- PR に **`preview` ラベル**を付けると、`.github/workflows/preview.yml` がそのPRのコードで Flutter Web版をビルドし、Firebase Hosting のプレビュー用URL（PRごと・7日で自動削除）に公開する。URL は PR のコメントに書き込まれる。ラベルが付いている間は push のたびに更新される
- 画面・表示の変更をしたPRは、レビューしやすいように `preview` ラベルを付ける
- **接続先は本番のAPI・本番のデータ。** 確認はテスト用アカウントで行う。AI分析ボタンを押すと OpenAI の料金がかかる。バックエンドの変更はデプロイされるまで反映されない
- Webで動かないもの（`dart:io` の `Platform` など）を `lib/` に足すと、プレビューと E2E の画面テストが動かなくなる。使うときは `kIsWeb` で分ける
- 必要な Secrets：`FIREBASE_SERVICE_ACCOUNT`（サービスアカウントの鍵のJSON）・`FIREBASE_PROJECT_ID`
