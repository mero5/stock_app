// ===================================================
// お知らせ履歴（web/pages/notices.html）
//
// ネイティブ版（lib/screens/notice_history_screen.dart）と同じ内容を出す。
//   ・/notices?since=0 の全件を、新しいものを上にして並べる
//   ・取得に失敗した・0件のときは同じ文言を出す
// ===================================================

(function () {
  "use strict";

  const { fetchJson, el } = window.StockApp;
  const content = document.getElementById("content");

  const EMPTY_MESSAGE =
    "お知らせを取得できませんでした。\n通信状況を確認してもう一度お試しください。";

  function buildCard(notice) {
    const card = el("article", "card");
    card.appendChild(el("h2", "card-title", notice.title || ""));
    if (notice.date) card.appendChild(el("p", "card-date", notice.date));

    const body = el("div", "card-body");
    (notice.sections || []).forEach((section) => {
      if (section.heading) body.appendChild(el("h3", "section-heading", section.heading));
      const list = el("ul", "bullets");
      (section.items || []).forEach((item) => list.appendChild(el("li", null, item)));
      body.appendChild(list);
    });
    card.appendChild(body);

    if (notice.footer) card.appendChild(el("p", "card-footer", notice.footer));
    return card;
  }

  async function load() {
    content.replaceChildren(el("div", "spinner"));
    let notices = [];
    try {
      const data = await fetchJson("/notices?since=0");
      notices = Array.isArray(data.notices) ? data.notices : [];
    } catch (e) {
      console.error("お知らせの取得エラー:", e);
    }
    if (notices.length === 0) {
      content.replaceChildren(el("p", "state", EMPTY_MESSAGE));
      return;
    }
    // 履歴は新しいものを上に出す（API は古い順で返す）
    content.replaceChildren(...notices.slice().reverse().map(buildCard));
  }

  load();
})();
