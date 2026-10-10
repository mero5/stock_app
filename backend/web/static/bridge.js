// ===================================================
// StockApp：WebView の画面とアプリの受け渡し
//
// アプリ（lib/widgets/web_page_view.dart）は、このページに
// JavaScriptChannel「StockAppBridge」を用意している。
//   ページ → アプリ：StockAppBridge.postMessage(JSON文字列)
//   アプリ → ページ：window.StockApp.receiveToken(トークン)
//
// ログインのトークンはURLに入れない（サーバーのログに残るため）。
// API を呼ぶたびにアプリに頼んで最新のトークンをもらい、Authorization ヘッダーに付ける。
// ブラウザで直接開いたとき（StockAppBridge が無い）はトークン無しで呼ぶ。
// ===================================================

(function () {
  "use strict";

  // アプリからトークンが返ってこないときに待つ長さ。過ぎたらトークン無しで進める
  const TOKEN_WAIT_MS = 3000;
  // API の待ち時間（アプリの AppTimeouts.api と同じ 40 秒）
  const API_TIMEOUT_MS = 40000;

  let waiting = [];

  function post(message) {
    if (!window.StockAppBridge) return false;
    window.StockAppBridge.postMessage(JSON.stringify(message));
    return true;
  }

  /** アプリに最新のトークンを頼む。もらえなければ null */
  function requestToken() {
    return new Promise((resolve) => {
      if (!post({ type: "token" })) {
        resolve(null);
        return;
      }
      const timer = setTimeout(() => {
        waiting = waiting.filter((w) => w !== done);
        resolve(null);
      }, TOKEN_WAIT_MS);
      function done(token) {
        clearTimeout(timer);
        resolve(token);
      }
      waiting.push(done);
    });
  }

  /** アプリから呼ばれる。待っている全員にトークンを渡す */
  function receiveToken(token) {
    const list = waiting;
    waiting = [];
    list.forEach((done) => done(token || null));
  }

  /**
   * バックエンドの API を呼んで JSON を返す。
   * path は "/notices?since=0" のように / から書く（このページと同じサーバーに送る）。
   * 通信に失敗・HTTP エラー・時間切れのときは例外を投げる。
   */
  async function fetchJson(path) {
    const token = await requestToken();
    const headers = {};
    if (token) headers.Authorization = "Bearer " + token;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), API_TIMEOUT_MS);
    try {
      const res = await fetch(path, { headers, signal: controller.signal });
      if (!res.ok) throw new Error("HTTP " + res.status);
      return await res.json();
    } finally {
      clearTimeout(timer);
    }
  }

  /** タグを作る小さな関数。文字は textContent で入れる（HTML として解釈させない） */
  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = text;
    return node;
  }

  window.StockApp = { fetchJson, receiveToken, post, el };
})();
