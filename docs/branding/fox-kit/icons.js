(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  root.AfterwordIcons = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  var STROKE = 1.75;
  var DEFAULT_COLOR = "#476b4f";

  function attrs(extra) {
    return (
      'fill="none" stroke="currentColor" stroke-width="' +
      STROKE +
      '" stroke-linecap="round" stroke-linejoin="round" ' +
      (extra || "")
    );
  }

  function path(d) {
    return '<path ' + attrs('d="' + d + '"') + "/>";
  }

  function line(x1, y1, x2, y2) {
    return (
      '<path ' +
      attrs('d="M' + x1 + " " + y1 + " L" + x2 + " " + y2 + '"') +
      "/>"
    );
  }

  function circle(cx, cy, r) {
    return '<circle ' + attrs('cx="' + cx + '" cy="' + cy + '" r="' + r + '"') + "/>";
  }

  function rect(x, y, w, h, r) {
    return (
      '<rect ' +
      attrs('x="' + x + '" y="' + y + '" width="' + w + '" height="' + h + '" rx="' + (r || 2) + '"') +
      "/>"
    );
  }

  function poly(points) {
    return '<path ' + attrs('d="' + points + " Z" + '"') + "/>";
  }

  function filledPath(d) {
    return '<path fill="currentColor" stroke="none" d="' + d + '"/>';
  }

  function filledCircle(cx, cy, r) {
    return '<circle cx="' + cx + '" cy="' + cy + '" r="' + r + '" fill="currentColor" stroke="none"/>';
  }

  function softTail() {
    return path("M15.8 18.6C18.5 18.2 20.8 16.6 20.5 14.4C20.3 13 19.1 12 17.8 12.2");
  }

  function smallTail() {
    return path("M14.5 19C16.7 18.7 18.4 17.6 18.2 16.1");
  }

  function plus(cx, cy, s) {
    return line(cx - s, cy, cx + s, cy) + line(cx, cy - s, cx, cy + s);
  }

  function checkPath() {
    return path("M5 12.3L9.1 16.3L19 7");
  }

  function compactCheckPath() {
    return path("M8 12L11 15L16 9");
  }

  function closePath() {
    return line(7, 7, 17, 17) + line(17, 7, 7, 17);
  }

  function chevron(dir) {
    return dir === "left" ? path("M14.5 6.5L9 12L14.5 17.5") : path("M9.5 6.5L15 12L9.5 17.5");
  }

  function bookBase() {
    return (
      '<path ' +
      attrs('d="M5 5.5C7.8 4.7 9.7 5.1 12 6.6C14.3 5.1 16.2 4.7 19 5.5V18.5C16.2 17.7 14.3 18.1 12 19.6C9.7 18.1 7.8 17.7 5 18.5V5.5"') +
      "/>" +
      line(12, 6.8, 12, 19.4)
    );
  }

  function docBase(fold) {
    return (
      path(fold ? "M6.5 3.8H14L18 7.8V20H6.5V3.8" : "M6.5 4H17.5V20H6.5V4") +
      (fold ? path("M14 3.8V8H18") : "") +
      line(9, 10.5, 15, 10.5) +
      line(9, 14, 14, 14)
    );
  }

  function trashBase(sweep) {
    return (
      line(4.8, 7, 19.2, 7) +
      path("M9 7V5.5C9 4.7 9.7 4 10.5 4H13.5C14.3 4 15 4.7 15 5.5V7") +
      path("M7.2 7.2L8 20H16L16.8 7.2") +
      (sweep ? path("M10 13.2C12.5 12.7 14.8 11.5 16 9.8") : line(10.2, 10.5, 10.7, 17)) +
      (sweep ? line(9.4, 16.7, 14.8, 11.3) : line(13.8, 10.5, 13.3, 17))
    );
  }

  function refreshBase(replay) {
    return (
      path(replay ? "M17.6 7.4C16.2 5.9 14.3 5 12 5C8.1 5 5 8.1 5 12" : "M18.5 8.2C17 6.2 14.7 5 12 5C8.4 5 5.5 7.2 4.5 10.2") +
      path(replay ? "M5 12C5 15.9 8.1 19 12 19C15.6 19 18.5 16.6 19.2 13.2" : "M5.5 15.8C7 17.8 9.3 19 12 19C15.6 19 18.5 16.8 19.5 13.8") +
      path(replay ? "M17.7 4.8V7.5H14.8" : "M18.6 5.3V8.4H15.5") +
      path(replay ? "M4.9 15.5V12H8.4" : "M5.4 18.7V15.6H8.5")
    );
  }

  function searchBase(off) {
    return (
      circle(10.5, 10.5, 5.1) +
      (off ? line(14.3, 14.3, 19.2, 19.2) + line(5, 5, 19, 19) : path("M14.3 14.3C16.2 16.2 17.7 17.6 19.4 18.8"))
    );
  }

  function globeBase() {
    return (
      circle(12, 12, 7.4) +
      path("M4.8 12H19.2") +
      path("M12 4.6C14.1 6.7 15.1 9.2 15.1 12C15.1 14.8 14.1 17.3 12 19.4") +
      path("M12 4.6C9.9 6.7 8.9 9.2 8.9 12C8.9 14.8 9.9 17.3 12 19.4")
    );
  }

  function navSelected(body) {
    return filledPath("M4 20C7.5 18.9 10 19.3 12 20.6C14 19.3 16.5 18.9 20 20V21.2H4Z") + body;
  }

  var records = [
    {
      id: "today",
      label: "今日",
      category: "navigation",
      tags: ["today", "daily", "recommendation"],
      material: ["today_outlined", "today"],
      body: rect(5.2, 5.3, 13.6, 13.5, 2) + line(8, 3.8, 8, 7.3) + line(16, 3.8, 16, 7.3) + line(5.2, 9, 18.8, 9) + path("M9 13H12.1C14.1 13 15.6 11.9 16.5 10.4") + smallTail(),
      selectedBody: navSelected(rect(5.2, 5.3, 13.6, 13.5, 2) + line(8, 3.8, 8, 7.3) + line(16, 3.8, 16, 7.3) + line(5.2, 9, 18.8, 9) + filledPath("M8.7 12.1H13.2C14.5 12.1 15.7 11.5 16.8 10.6C16.2 13.9 13.5 16.1 9.1 16.1Z")),
    },
    {
      id: "library",
      label: "资料库",
      category: "navigation",
      tags: ["library", "archive", "collection"],
      material: ["collections_bookmark_outlined", "collections_bookmark"],
      body: path("M6 5H16.8C17.7 5 18.4 5.7 18.4 6.6V19L12.2 16.6L6 19V5") + path("M8.2 5V3.7H18.1") + line(9.4, 8.8, 14.8, 8.8) + softTail(),
      selectedBody: navSelected(path("M6 5H16.8C17.7 5 18.4 5.7 18.4 6.6V19L12.2 16.6L6 19V5") + filledPath("M8 6.8H16.6V16.1L12.2 14.4L8 16.1Z")),
    },
    {
      id: "rss",
      label: "RSS",
      category: "navigation",
      tags: ["rss", "feed", "subscription"],
      material: ["rss_feed_outlined", "rss_feed"],
      body: circle(6.6, 17.4, 1.1) + path("M5.4 11.2C9.5 11.2 12.8 14.5 12.8 18.6") + path("M5.4 6C12.3 6 18 11.7 18 18.6") + smallTail(),
      selectedBody: navSelected(circle(6.6, 17.4, 1.1) + path("M5.4 11.2C9.5 11.2 12.8 14.5 12.8 18.6") + path("M5.4 6C12.3 6 18 11.7 18 18.6")),
    },
    {
      id: "research",
      label: "研究",
      category: "navigation",
      tags: ["research", "topic", "explore", "web"],
      material: ["travel_explore_outlined", "travel_explore"],
      body: globeBase() + circle(15.8, 8.2, 2.4) + line(17.6, 10, 20.1, 12.5),
      selectedBody: navSelected(globeBase() + circle(15.8, 8.2, 2.4) + line(17.6, 10, 20.1, 12.5)),
    },
    {
      id: "settings",
      label: "设置",
      category: "navigation",
      tags: ["settings", "tune", "scope"],
      material: ["tune_outlined", "tune"],
      body: line(5, 7, 19, 7) + circle(9, 7, 1.7) + line(5, 12, 19, 12) + circle(15, 12, 1.7) + line(5, 17, 19, 17) + circle(11.5, 17, 1.7),
      selectedBody: navSelected(line(5, 7, 19, 7) + circle(9, 7, 1.7) + line(5, 12, 19, 12) + circle(15, 12, 1.7) + line(5, 17, 19, 17) + circle(11.5, 17, 1.7)),
    },
    { id: "add", label: "添加", category: "actions", tags: ["add", "new"], material: ["add"], body: plus(12, 12, 6) + smallTail() },
    { id: "add-link", label: "收藏链接", category: "actions", tags: ["add", "link", "save"], material: ["add_link"], body: path("M9.5 8.2L8.1 8.2C5.9 8.2 4.2 9.9 4.2 12.1C4.2 14.3 5.9 16 8.1 16H10.2") + path("M13.8 8.2H15.9C18.1 8.2 19.8 9.9 19.8 12.1C19.8 14.3 18.1 16 15.9 16H14.5") + line(9.5, 12.1, 14.5, 12.1) + plus(17.2, 6.2, 2.1) },
    { id: "block", label: "跳过", category: "actions", tags: ["block", "skip"], material: ["block"], body: circle(12, 12, 7) + line(7.1, 16.9, 16.9, 7.1) },
    { id: "back", label: "返回", category: "implicit", tags: ["back", "appbar"], material: ["arrow_back", "chevron_left"], body: chevron("left") + line(9.5, 12, 19, 12) },
    { id: "chevron-left", label: "上一页", category: "actions", tags: ["previous", "page"], material: ["chevron_left"], body: chevron("left") },
    { id: "chevron-right", label: "下一步", category: "actions", tags: ["next", "detail"], material: ["chevron_right"], body: chevron("right") },
    { id: "expand-more", label: "展开", category: "implicit", tags: ["expand", "dropdown"], material: ["expand_more", "arrow_drop_down"], body: path("M6.5 9.5L12 15L17.5 9.5") },
    { id: "expand-less", label: "收起", category: "implicit", tags: ["collapse"], material: ["expand_less"], body: path("M6.5 14.5L12 9L17.5 14.5") },
    { id: "close", label: "关闭", category: "actions", tags: ["close", "cancel", "clear"], material: ["close"], body: closePath() },
    { id: "delete", label: "删除", category: "actions", tags: ["delete", "trash"], material: ["delete_outline"], body: trashBase(false) },
    { id: "delete-sweep", label: "清空回收站", category: "actions", tags: ["delete", "sweep", "trash"], material: ["delete_sweep_outlined"], body: trashBase(true) },
    { id: "permanent-delete", label: "永久删除", category: "implicit", tags: ["delete", "danger", "permanent"], material: ["delete_forever"], body: line(4.8, 7, 19.2, 7) + path("M9 7V5.5C9 4.7 9.7 4 10.5 4H13.5C14.3 4 15 4.7 15 5.5V7") + path("M7.2 7.2L8 20H16L16.8 7.2") + line(9.6, 11.3, 14.4, 16.1) + line(14.4, 11.3, 9.6, 16.1) },
    { id: "archive", label: "归档", category: "implicit", tags: ["archive"], material: ["archive_outlined"], body: rect(5, 5.5, 14, 13, 2) + line(5, 9, 19, 9) + path("M9.2 13L12 15.8L14.8 13") + line(12, 11.2, 12, 15.8) },
    { id: "unarchive", label: "移出归档", category: "implicit", tags: ["archive", "restore"], material: ["unarchive_outlined"], body: rect(5, 5.5, 14, 13, 2) + line(5, 9, 19, 9) + path("M9.2 14.2L12 11.4L14.8 14.2") + line(12, 11.4, 12, 16) },
    { id: "restore-trash", label: "从回收站恢复", category: "implicit", tags: ["trash", "restore"], material: ["restore_from_trash"], body: line(4.8, 7, 19.2, 7) + path("M9 7V5.5C9 4.7 9.7 4 10.5 4H13.5C14.3 4 15 4.7 15 5.5V7") + path("M7.2 7.2L8 20H16L16.8 7.2") + path("M9.4 14.2L12 11.6L14.6 14.2") + line(12, 11.6, 12, 17) },
    { id: "done", label: "完成", category: "actions", tags: ["done", "read"], material: ["done"], body: checkPath() + smallTail() },
    { id: "done-all", label: "全部完成", category: "actions", tags: ["done", "batch"], material: ["done_all"], body: path("M3.8 12.3L7.1 15.6L14.8 8.1") + path("M9.2 12.5L12.4 15.6L20.2 7.9") },
    { id: "download", label: "导出", category: "actions", tags: ["download", "export"], material: ["download_outlined"], body: path("M12 4.5V14.4") + path("M8.6 11.1L12 14.5L15.4 11.1") + path("M5.2 18.5H18.8") },
    { id: "edit", label: "编辑", category: "actions", tags: ["edit", "topic"], material: ["edit_outlined"], body: path("M5.2 18.8L6.2 14.4L15.4 5.2C16.1 4.5 17.2 4.5 17.9 5.2L18.8 6.1C19.5 6.8 19.5 7.9 18.8 8.6L9.6 17.8L5.2 18.8") + line(14.1, 6.5, 17.5, 9.9) },
    { id: "edit-note", label: "编辑批注", category: "actions", tags: ["edit", "note", "paste"], material: ["edit_note_outlined"], body: docBase(false) + path("M9 17.6L10 14.8L16.7 8.1L18.6 10L11.9 16.7L9 17.6") },
    { id: "share", label: "分享导出", category: "actions", tags: ["share", "export"], material: ["ios_share_outlined"], body: path("M12 14V4.8") + path("M8.7 8.1L12 4.8L15.3 8.1") + path("M6.5 11.2V19H17.5V11.2") },
    { id: "more", label: "更多", category: "actions", tags: ["more", "menu"], material: ["more_horiz"], body: circle(6.8, 12, 0.9) + circle(12, 12, 0.9) + circle(17.2, 12, 0.9) },
    { id: "more-vertical", label: "更多菜单", category: "implicit", tags: ["more", "popup"], material: ["more_vert"], body: circle(12, 6.8, 0.9) + circle(12, 12, 0.9) + circle(12, 17.2, 0.9) },
    { id: "note-add", label: "添加笔记", category: "actions", tags: ["note", "add", "pdf"], material: ["note_add_outlined"], body: docBase(true) + plus(12, 15.4, 2.2) },
    { id: "open-browser", label: "浏览器打开", category: "actions", tags: ["browser", "web", "open"], material: ["open_in_browser_outlined"], body: rect(4.8, 5.4, 14.4, 13.2, 2) + line(4.8, 9, 19.2, 9) + path("M9.2 15.4C11.5 14.7 13.4 13.1 14.4 10.8") },
    { id: "open-new", label: "外部打开", category: "actions", tags: ["external", "source"], material: ["open_in_new"], body: rect(5, 7.2, 11.8, 11.8, 2) + path("M12.4 5H19V11.6") + line(18.7, 5.3, 10.7, 13.3) },
    { id: "pause", label: "暂停", category: "actions", tags: ["pause", "tracking"], material: ["pause"], body: rect(7.3, 5.2, 3.2, 13.6, 1.1) + rect(13.5, 5.2, 3.2, 13.6, 1.1) },
    { id: "play", label: "启用", category: "actions", tags: ["play", "resume"], material: ["play_arrow"], body: poly("M8 5.6L18.3 12L8 18.4") },
    { id: "playlist-check", label: "选中处理", category: "actions", tags: ["playlist", "rss", "saved"], material: ["playlist_add_check"], body: line(5, 7, 14, 7) + line(5, 11, 14, 11) + line(5, 15, 10.5, 15) + path("M13 16L15.3 18.3L20 13.6") },
    { id: "refresh", label: "刷新", category: "actions", tags: ["refresh", "reload"], material: ["refresh", "refresh_outlined"], body: refreshBase(false) },
    { id: "replay", label: "重试", category: "actions", tags: ["retry", "replay"], material: ["replay"], body: refreshBase(true) },
    { id: "restore", label: "恢复", category: "actions", tags: ["restore", "backup"], material: ["restore", "restore_outlined"], body: path("M7 7.5C8.3 5.9 10.1 5 12.2 5C16 5 19 8 19 11.8C19 15.7 16 18.7 12.2 18.7C9.7 18.7 7.5 17.4 6.3 15.5") + path("M7.1 4.8V7.6H4.2") + line(12, 8.5, 12, 12.4) + line(12, 12.4, 15, 14) },
    { id: "save", label: "保存", category: "actions", tags: ["save", "settings"], material: ["save_outlined"], body: path("M5 5H16.5L19 7.5V19H5V5") + rect(8, 5, 6.8, 4.5, 0.8) + rect(8.2, 14, 7.6, 5, 1) },
    { id: "search", label: "搜索", category: "actions", tags: ["search", "find", "page"], material: ["search", "search_outlined"], body: searchBase(false) },
    { id: "select-all", label: "全选", category: "actions", tags: ["select", "batch"], material: ["select_all"], body: rect(5.5, 5.5, 5, 5, 1) + rect(13.5, 5.5, 5, 5, 1) + rect(5.5, 13.5, 5, 5, 1) + rect(13.5, 13.5, 5, 5, 1) + checkPath() },
    { id: "article", label: "文章", category: "reading", tags: ["article", "item"], material: ["article_outlined"], body: docBase(false) + line(9, 7.5, 15, 7.5) },
    { id: "attach-file", label: "附件", category: "reading", tags: ["attachment"], material: ["attach_file"], body: path("M8.2 12.3L13.4 7.1C14.9 5.6 17.3 5.6 18.8 7.1C20.3 8.6 20.3 11 18.8 12.5L11 20.3C8.9 22.4 5.4 22.4 3.3 20.3C1.2 18.2 1.2 14.7 3.3 12.6L11.5 4.4") + path("M8.7 15.1L15.3 8.5C15.9 7.9 16.9 7.9 17.5 8.5C18.1 9.1 18.1 10.1 17.5 10.7L10.1 18.1C8.8 19.4 6.7 19.4 5.4 18.1C4.1 16.8 4.1 14.7 5.4 13.4L12.1 6.7") },
    { id: "analysis", label: "分析", category: "reading", tags: ["analysis", "insight", "synthesis"], material: ["auto_awesome", "auto_awesome_outlined"], body: path("M12 4.5L13.5 9.6L18.5 11.2L13.5 12.8L12 17.9L10.5 12.8L5.5 11.2L10.5 9.6L12 4.5") + path("M18.1 4.4L18.8 6.4L20.8 7.1L18.8 7.8L18.1 9.8L17.4 7.8L15.4 7.1L17.4 6.4L18.1 4.4") },
    { id: "highlight", label: "高亮", category: "reading", tags: ["highlight", "mark"], material: ["border_color_outlined"], body: path("M6 16.2L12.4 9.8L15.2 12.6L8.8 19H6V16.2") + line(13.6, 8.6, 16.4, 11.4) + line(5.5, 20, 18.5, 20) },
    { id: "goal", label: "目标", category: "reading", tags: ["goal", "flag"], material: ["flag_outlined"], body: line(6.5, 4.5, 6.5, 20) + path("M6.5 5.2H17.5L15.4 9.1L17.5 13H6.5") },
    { id: "quote", label: "引用", category: "reading", tags: ["quote", "evidence"], material: ["format_quote"], body: path("M7.5 8H11V11.6C11 14.4 9.7 16.5 7.2 18") + path("M14 8H17.5V11.6C17.5 14.4 16.2 16.5 13.7 18") },
    { id: "text-size", label: "字号", category: "reading", tags: ["font", "text"], material: ["format_size"], body: line(4.8, 6, 14.2, 6) + line(9.5, 6, 9.5, 18) + line(6.8, 18, 12.2, 18) + line(14.5, 10, 20, 10) + line(17.3, 10, 17.3, 18) + line(15.3, 18, 19.3, 18) },
    { id: "history", label: "历史", category: "reading", tags: ["history"], material: ["history_outlined"], body: path("M7 7.2C8.4 5.8 10.2 5 12.2 5C16.1 5 19.2 8.1 19.2 12C19.2 15.9 16.1 19 12.2 19C9.8 19 7.7 17.8 6.4 16") + path("M6.8 4.7V7.4H4.1") + line(12, 8.3, 12, 12.2) + line(12, 12.2, 15, 13.8) },
    { id: "image-search", label: "补图", category: "reading", tags: ["image", "search"], material: ["image_search_outlined"], body: rect(4.8, 5.5, 11.5, 10.5, 2) + path("M6.5 14L9.2 11.3L11 13.1L12.2 11.9L15.4 15.1") + circle(12.6, 8.8, 0.9) + circle(16.8, 16.8, 2.6) + line(18.7, 18.7, 20.3, 20.3) },
    { id: "file", label: "文件", category: "reading", tags: ["file"], material: ["insert_drive_file"], body: docBase(true) },
    { id: "library-import", label: "资料导入", category: "reading", tags: ["library", "import", "background"], material: ["library_books_outlined"], body: bookBase() + path("M16.8 12H20") + path("M18.4 10.4L20 12L18.4 13.6") },
    { id: "idea", label: "观点", category: "reading", tags: ["idea", "insight"], material: ["lightbulb_outline"], body: path("M8.2 11C8.2 8.7 9.9 7 12 7C14.1 7 15.8 8.7 15.8 11C15.8 12.4 15.1 13.5 14 14.4C13.2 15 13 15.8 13 16.5H11C11 15.8 10.8 15 10 14.4C8.9 13.5 8.2 12.4 8.2 11") + line(10.5, 19, 13.5, 19) + line(10.8, 16.5, 13.2, 16.5) },
    { id: "link", label: "链接", category: "reading", tags: ["link", "source"], material: ["link"], body: path("M9.5 8.2L8.1 8.2C5.9 8.2 4.2 9.9 4.2 12.1C4.2 14.3 5.9 16 8.1 16H10.2") + path("M13.8 8.2H15.9C18.1 8.2 19.8 9.9 19.8 12.1C19.8 14.3 18.1 16 15.9 16H14.5") + line(9.5, 12.1, 14.5, 12.1) },
    { id: "notes", label: "笔记", category: "reading", tags: ["notes", "background"], material: ["notes_outlined"], body: line(5, 7, 19, 7) + line(5, 11, 19, 11) + line(5, 15, 14, 15) + smallTail() },
    { id: "pdf", label: "PDF", category: "reading", tags: ["pdf", "page"], material: ["picture_as_pdf_outlined"], body: docBase(true) + line(8.5, 16.5, 8.5, 13.1) + path("M8.5 13.1H10C11.3 13.1 11.3 15.1 10 15.1H8.5") + line(12.2, 13.1, 12.2, 16.5) + path("M12.2 13.1H13.4C15.6 13.1 15.6 16.5 13.4 16.5H12.2") },
    { id: "judgement", label: "判断", category: "reading", tags: ["judgement", "thinking"], material: ["psychology_alt_outlined"], body: path("M8.2 17C6.8 15.8 6 14.1 6 12C6 8.5 8.6 5.8 12 5.8C15.3 5.8 18 8.4 18 11.7C18 13.9 16.8 15.4 15 16.3V19H10.2V16.4") + path("M10.3 10.2C10.6 9.1 11.5 8.4 12.7 8.4C14 8.4 15 9.2 15 10.4C15 11.7 13.9 12.2 13 12.8C12.3 13.3 12 13.8 12 14.5") + circle(12, 17, 0.4) },
    { id: "review", label: "反馈", category: "reading", tags: ["review", "feedback"], material: ["rate_review_outlined"], body: path("M5 5.5H19V15.5H11L6.5 19V15.5H5V5.5") + path("M9 13L10 10.6L14.6 6L16 7.4L11.4 12L9 13") },
    { id: "rule", label: "限制", category: "reading", tags: ["constraint", "rule"], material: ["rule_outlined"], body: rect(5, 5, 14, 14, 2) + line(8.1, 9.1, 9.4, 10.4) + line(9.4, 10.4, 11.4, 8.1) + line(13.7, 8.4, 16.4, 11.1) + line(16.4, 8.4, 13.7, 11.1) + line(8.2, 14.5, 11.7, 14.5) + line(13.6, 14.5, 16.8, 14.5) },
    { id: "science", label: "研究记录", category: "reading", tags: ["science", "task", "record"], material: ["science_outlined"], body: path("M9 4.5H15") + line(10.5, 4.5, 10.5, 10.2) + line(13.5, 4.5, 13.5, 10.2) + path("M10.5 10.2L6.2 18.4C5.7 19.3 6.4 20.4 7.4 20.4H16.6C17.6 20.4 18.3 19.3 17.8 18.4L13.5 10.2") + path("M8.2 16H15.8") },
    { id: "public-web", label: "网页抓取", category: "reading", tags: ["web", "fetch"], material: ["public"], body: globeBase() },
    { id: "review-repeat", label: "七天复查", category: "reading", tags: ["review", "repeat", "calendar"], material: ["event_repeat_outlined"], body: rect(5.2, 5.5, 13.6, 13, 2) + line(5.2, 9, 18.8, 9) + path("M9.2 13C10.2 11.9 11.8 11.7 13 12.5") + path("M13 10.8V12.5H14.7") + path("M14.8 15C13.8 16.1 12.2 16.3 11 15.5") + path("M11 17.2V15.5H9.3") },
    { id: "review-clear", label: "清除复查", category: "reading", tags: ["review", "clear", "calendar"], material: ["event_busy_outlined"], body: rect(5.2, 5.5, 13.6, 13, 2) + line(5.2, 9, 18.8, 9) + line(9.2, 12.3, 14.8, 16) + line(14.8, 12.3, 9.2, 16) },
    { id: "help", label: "问题", category: "reading", tags: ["question", "help"], material: ["help_outline"], body: circle(12, 12, 7) + path("M9.8 9.6C10.1 8.4 11 7.7 12.3 7.7C13.8 7.7 14.8 8.6 14.8 10C14.8 11.1 14.1 11.7 13.1 12.3C12.3 12.8 12 13.4 12 14.3") + circle(12, 16.8, 0.4) },
    { id: "check-circle", label: "成功", category: "state", tags: ["success", "selected", "done"], material: ["check_circle", "check_circle_outline"], body: circle(12, 12, 7.2) + compactCheckPath() },
    { id: "bullet", label: "列表圆点", category: "state", tags: ["bullet", "dot"], material: ["circle"], body: filledCircle(12, 12, 2.2) },
    { id: "radio-off", label: "单选未选", category: "state", tags: ["radio", "off", "unselected"], material: ["circle_outlined", "radio_button_unchecked"], body: circle(12, 12, 5.8) },
    { id: "radio-on", label: "单选已选", category: "state", tags: ["radio", "on", "selected"], material: ["circle", "radio_button_checked"], body: circle(12, 12, 5.8) + filledCircle(12, 12, 2.4) },
    { id: "circle", label: "圆形状态", category: "state", tags: ["circle", "status"], material: ["circle", "circle_outlined"], body: circle(12, 12, 5.8) },
    { id: "error", label: "错误", category: "state", tags: ["error", "failed"], material: ["error_outline"], body: circle(12, 12, 7.2) + line(12, 7.8, 12, 13) + circle(12, 16.2, 0.4) },
    { id: "image-missing", label: "图片损坏", category: "state", tags: ["image", "missing"], material: ["image_not_supported"], body: rect(4.8, 5.5, 14.4, 12.5, 2) + path("M6.6 16.2L10 12.8L12.1 14.9L13.4 13.6L16.7 16.9") + line(5, 5, 19, 19) },
    { id: "inbox", label: "收件箱空", category: "state", tags: ["inbox", "empty"], material: ["inbox_outlined"], body: path("M5.2 8.5L7.4 5H16.6L18.8 8.5V18H5.2V8.5") + path("M5.2 12.8H9L10.5 15H13.5L15 12.8H18.8") },
    { id: "notifications-active", label: "通知开启", category: "state", tags: ["notification", "tracking"], material: ["notifications_active", "notifications_active_outlined"], body: path("M8 16.5H16L15.2 14.8V11C15.2 8.9 13.9 7.4 12 7.4C10.1 7.4 8.8 8.9 8.8 11V14.8L8 16.5") + path("M10.5 18.4C11.2 19.1 12.8 19.1 13.5 18.4") + path("M6.3 7.4C6.8 6.2 7.7 5.3 8.8 4.7") + path("M17.7 7.4C17.2 6.2 16.3 5.3 15.2 4.7") },
    { id: "notifications-off", label: "通知关闭", category: "state", tags: ["notification", "off"], material: ["notifications_off_outlined"], body: path("M8 16.5H16L15.2 14.8V11C15.2 8.9 13.9 7.4 12 7.4C10.1 7.4 8.8 8.9 8.8 11V14.8L8 16.5") + line(5, 5, 19, 19) },
    { id: "search-off", label: "无搜索结果", category: "state", tags: ["search", "empty"], material: ["search_off", "search_off_outlined"], body: searchBase(true) },
    { id: "timelapse", label: "运行中", category: "state", tags: ["running", "diagnostic"], material: ["timelapse"], body: circle(12, 12, 7.1) + path("M12 5C15.9 5 19 8.1 19 12H12V5") + line(12, 12, 15.4, 15.4) },
    { id: "bug", label: "事件诊断", category: "settings", tags: ["bug", "diagnostic"], material: ["bug_report_outlined"], body: rect(8, 8, 8, 8.8, 3) + line(10, 5.8, 11, 8) + line(14, 5.8, 13, 8) + line(5.2, 10, 8, 10) + line(16, 10, 18.8, 10) + line(5.2, 15, 8, 15) + line(16, 15, 18.8, 15) + circle(10.5, 11.2, 0.3) + circle(13.5, 11.2, 0.3) },
    { id: "code", label: "开发者日志", category: "settings", tags: ["code", "developer"], material: ["code_outlined"], body: path("M9 8L5 12L9 16") + path("M15 8L19 12L15 16") + line(13, 6, 11, 18) },
    { id: "backup-box", label: "诊断包", category: "settings", tags: ["backup", "inventory"], material: ["inventory_2_outlined"], body: rect(5, 6.5, 14, 12, 2) + line(5, 10, 19, 10) + path("M9.2 14.2H14.8") + path("M7.5 6.5L8.8 4.4H15.2L16.5 6.5") },
    { id: "logs", label: "任务日志", category: "settings", tags: ["log", "receipt"], material: ["receipt_long_outlined"], body: path("M6.2 4.5L8 5.6L9.8 4.5L11.6 5.6L13.4 4.5L15.2 5.6L17 4.5V19.5L15.2 18.4L13.4 19.5L11.6 18.4L9.8 19.5L8 18.4L6.2 19.5V4.5") + line(9, 9, 15, 9) + line(9, 12, 15, 12) + line(9, 15, 13, 15) },
    { id: "schedule", label: "每日时间", category: "settings", tags: ["schedule", "time"], material: ["schedule", "access_time"], body: circle(12, 12, 7.2) + line(12, 7.8, 12, 12.2) + line(12, 12.2, 15.2, 14) },
    { id: "checkbox-off", label: "复选未选", category: "implicit", tags: ["checkbox", "off"], material: ["check_box_outline_blank"], body: rect(5.5, 5.5, 13, 13, 2.2) },
    { id: "checkbox-on", label: "复选已选", category: "implicit", tags: ["checkbox", "chip", "on"], material: ["check_box", "check"], body: rect(5.5, 5.5, 13, 13, 2.2) + compactCheckPath() },
    { id: "checkbox-check", label: "勾选标记", category: "implicit", tags: ["checkbox", "chip", "check"], material: ["check"], body: compactCheckPath() },
    { id: "date-picker", label: "日期", category: "implicit", tags: ["date", "calendar"], material: ["calendar_today"], body: rect(5.2, 5.3, 13.6, 13.5, 2) + line(8, 3.8, 8, 7.3) + line(16, 3.8, 16, 7.3) + line(5.2, 9, 18.8, 9) },
    { id: "time-picker", label: "时间", category: "implicit", tags: ["time", "clock"], material: ["access_time", "schedule"], body: circle(12, 12, 7.2) + line(12, 7.8, 12, 12.2) + line(12, 12.2, 15.2, 14) },
  ];

  var icons = records.map(function (record) {
    return Object.freeze({
      id: record.id,
      label: record.label,
      category: record.category,
      tags: Object.freeze(record.tags.slice()),
      material: Object.freeze(record.material.slice()),
      body: record.body,
      selectedBody: record.selectedBody,
    });
  });

  function findIcon(id) {
    for (var i = 0; i < icons.length; i += 1) {
      if (icons[i].id === id) return icons[i];
    }
    for (var j = 0; j < icons.length; j += 1) {
      if (icons[j].material.indexOf(id) !== -1) return icons[j];
    }
    return null;
  }

  function escape(value) {
    return String(value).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&apos;" }[c];
    });
  }

  function color(value, fallback) {
    if (value == null) return fallback;
    if (/^#(?:[0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(value) || value === "currentColor") return value;
    throw new TypeError("Use a hex color or currentColor.");
  }

  function size(value) {
    if (value != null && typeof value !== "number") throw new RangeError("Invalid SVG size.");
    var resolved = value == null ? 24 : value;
    if (!Number.isFinite(resolved) || resolved <= 0 || resolved > 4096) throw new RangeError("Invalid SVG size.");
    return resolved;
  }

  function svg(id, options) {
    options = options || {};
    var icon = findIcon(id);
    if (!icon) throw new Error("Unknown Afterword icon: " + id);
    var resolvedSize = size(options.size);
    var resolvedColor = color(options.color, DEFAULT_COLOR);
    var body = options.selected && icon.selectedBody ? icon.selectedBody : icon.body;
    return (
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="' +
      resolvedSize +
      '" height="' +
      resolvedSize +
      '" color="' +
      resolvedColor +
      '" role="img" aria-label="' +
      escape(icon.label) +
      '">' +
      body +
      "</svg>"
    );
  }

  return Object.freeze({
    icons: Object.freeze(icons),
    svg: svg,
    strokeWidth: STROKE,
    defaultColor: DEFAULT_COLOR,
  });
});
