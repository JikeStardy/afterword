/* Afterword · 长尾狐。Editable geometry; no embedded animation or network assets. */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.AfterwordScenes = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const ink = '#476b4f';
  const paper = '#faf8f3';
  // Each part keeps its native 160-unit coordinates so motion has a stable pivot.
  const tail = 'M58 34.5C79 16.8 114 29 124.3 55.5C141 98.2 116.2 133 76 133H68C94.4 132 119 106 112 83.5C108 69.8 98.7 65.7 85.5 59C77.3 54.8 74 50.8 72 45.8C69.5 38.9 65.4 34.4 58 34.5Z';
  const body = 'M54 50C54 56 54.3 59.3 56.3 61.6C60.3 61.8 63.6 63.4 65.8 65.4C68.4 68 73.6 67.4 77.1 66.2Q78.4 65.7 77.5 68.1C75.2 75.8 70.2 75.8 64.5 79.9C56.9 85.4 52.8 93.1 53.5 101C61.4 80.7 77.9 80.8 87.7 91.3C97.2 101.4 97.3 115.9 91.8 124.4C85.5 130 79.7 133 72 133H57.4C57.4 129.1 60.7 126 65.5 125.8C61.2 117.8 64 109.5 72 103.6C58.8 104.6 52.8 116 50 132Q49.8 133 49 133H41.5C41.5 130.8 43 129.4 44 128.5C47.8 124.5 46.6 117.4 43.9 113C38.8 105.5 34.2 99.4 34.3 87.4C34.3 72.1 42.3 58.8 54 50Z';

  function foxParts() {
    return '<g class="fox-tail"><path fill="currentColor" d="' + tail + '"/></g>' +
      '<g class="fox-body"><path fill="currentColor" d="' + body + '"/>' +
      '<g class="fox-eye"><circle cx="61.3" cy="69.1" r="2.3" fill="var(--fox-eye, ' + paper + ')"/></g></g>';
  }
  const line = (body) => '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + body + '</g>';
  const accent = (body) => '<g class="scene-accent">' + line(body) + '</g>';
  const motionPath = (body) => '<g class="motion-path">' + line(body) + '</g>';
  const ground = '<path d="M26 137H135" fill="none" stroke="currentColor" stroke-width="1.5" opacity=".18" stroke-linecap="round"/>';
  const companion = '<g transform="translate(37 36) scale(.7)">' + foxParts() + '</g>';
  const smallCompanion = '<g transform="translate(54 45) scale(.63)">' + foxParts() + '</g>';
  const sheet = '<path d="M26 35H59L69 45V84H26Z"/><path d="M59 35V45H69M35 56H58M35 65H54M35 74H47"/>';
  const book = '<path d="M20 64Q34 58 48 66Q62 58 76 64V98Q62 93 48 101Q34 93 20 98Z"/><path d="M48 66V101M27 73Q34 70 41 74M55 74Q62 70 69 73"/>';
  const check = '<path d="m28 53 8 8 16-19"/>';
  const scenes = [
    { id: 'today-clear', label: '今日留白', description: '今日暂无新的推荐；安静等待下一篇，不推断已有资料全部读完。', body: ground + companion + accent('<circle cx="37" cy="43" r="10"/><path d="M37 26V23M20 43H17M25 31l-2-2M49 31l2-2M21 62H55"/>') },
    { id: 'library-empty', label: '书库等第一篇', description: '书库尚无资料；配合“添加链接或文件”入口。', body: ground + smallCompanion + accent(book) },
    { id: 'archive-empty', label: '归档还空着', description: '归档列表为空；归档资料不会参与新的分析。', body: ground + smallCompanion + accent('<path d="M21 64H73V76H21ZM26 76V103H68V76M40 86H54"/><path d="M36 54Q43 42 55 48Q51 58 41 58"/>') },
    { id: 'trash-empty', label: '回收站很干净', description: '回收站为空；以轻盈叶片表达整理完成。', body: ground + smallCompanion + accent('<path d="M25 65H67M30 65l3 38H59l3-38M38 65V58H54V65M40 74V93M52 74V93M33 42Q41 30 54 35Q53 49 39 48Z"/><path d="M39 48l10-9"/>') },
    { id: 'search-empty', label: '还没找到', description: '书库、来源或日志筛选没有匹配项；保留修改查询入口。', body: ground + companion + accent('<circle cx="38" cy="51" r="18"/><path d="m25 64-10 11M30 51H46"/>') },
    { id: 'rss-empty', label: '等一缕新消息', description: '尚未添加订阅；以熟悉的 RSS 波纹提示订阅入口。', body: ground + companion + accent('<path d="M24 37A33 33 0 0 1 57 70M24 49A21 21 0 0 1 45 70"/><circle cx="26" cy="68" r="3"/>') },
    { id: 'feed-quiet', label: '订阅暂时安静', description: '已订阅但没有条目；保留刷新入口，不暗示自动同步。', body: ground + smallCompanion + accent('<path d="M20 65H34l6 9H53l6-9H72V98H20ZM20 88H72M32 55V50M47 55V42M62 55V50"/>') },
    { id: 'research-empty', label: '一个问题的起点', description: '尚无研究主题；问号与延伸路径提示提出问题。', body: ground + companion + accent('<path d="M27 41c0-13 23-13 23 0 0 8-11 7-11 15"/><circle cx="39" cy="65" r="1"/>') + motionPath('<path d="M20 86Q27 80 35 84" stroke-dasharray="3 5"/>') },
    { id: 'item-missing', label: '这一页不在了', description: '资料已删除，或所选主题、运行记录已经不存在。', body: ground + smallCompanion + accent('<path d="M24 39H59L69 49V92H49M59 39V49H69M24 39V71l8 5-8 8v8H36M34 59H57M34 68H51"/>') },
    { id: 'unanalyzed', label: '等一次细读', description: '资料已保存，尚未分析；对应“开始分析”操作。', body: ground + smallCompanion + accent(sheet) + motionPath('<path d="m39 102 7-9 7 9M46 93v23"/>') },
    { id: 'logs-clear', label: '记录清爽', description: '诊断日志为空；不把没有日志解读为服务已验证正常。', body: ground + smallCompanion + accent('<path d="M26 41H66V94L59 90l-7 4-7-4-7 4-6-4-6 4ZM36 55H56M36 65H50M36 75H46"/>') },
    { id: 'startup-error', label: '稍等，重试一下', description: '启动或加载失败；错误详情和重试按钮应由页面提供。', body: ground + companion + accent('<path d="M37 30 17 66Q15 70 20 70H57Q62 70 59 66L40 30Q38 27 37 30ZM38 42V54"/><circle cx="38" cy="62" r="1"/>') },
    { id: 'capturing', label: '把这一篇收好', description: '添加链接、导入文件或保存笔记；动效只表示处理中。', body: ground + smallCompanion + accent(sheet) + motionPath('<path d="M16 105H31l7 8H51l7-8H71v24H16ZM44 82v17m-6-6 6 6 6-6"/>') },
    { id: 'analyzing', label: '顺着线索读下去', description: '分析或研究进行中；路径循环表示等待，不表示百分比。', body: ground + companion + accent('<circle cx="22" cy="49" r="4"/><circle cx="42" cy="34" r="4"/><circle cx="54" cy="63" r="4"/><path d="m26 46 12-9m6 1 8 21m-26-8 24 10"/>') + motionPath('<path d="M16 89Q30 69 48 81" stroke-dasharray="4 5"/>') },
    { id: 'saved', label: '已经收好了', description: '保存成功的短反馈；完成后停在确定的勾选状态。', body: ground + companion + accent('<circle cx="40" cy="51" r="24"/>' + check) },
    { id: 'paused', label: '线索留在这里', description: '任务暂停或自动研究关闭；静止的暂停标记保留上下文。', body: ground + companion + accent('<rect x="21" y="33" width="12" height="35" rx="4"/><rect x="43" y="33" width="12" height="35" rx="4"/>') },
    { id: 'complete', label: '读到新的下文', description: '研究运行完成；书页与勾选表达得到成果，不替代结果内容。', body: ground + smallCompanion + accent(book + '<path d="m29 44 8 8 15-18"/>') },
  ];
  const motions = [
    { id: 'fox-greeting', label: '见面 · 尾尖轻摆', description: '进入样册或空态时轻摆一次；不在阅读时持续摇晃。', duration: 1800, loop: false, sceneId: 'today-clear', type: 'idle' },
    { id: 'collect-page', label: '收下 · 书页落定', description: '保存过程中书页向收纳方向轻落；真实成功另用勾选反馈。', duration: 1400, loop: true, sceneId: 'capturing', type: 'collect' },
    { id: 'follow-thread', label: '细读 · 线索流动', description: '研究或分析期间缓慢呼吸、线索前行；只表达忙碌，不伪造进度。', duration: 2400, loop: true, sceneId: 'analyzing', type: 'analyze' },
    { id: 'save-confirm', label: '收好 · 勾选回应', description: '收到保存成功事件后播放一次，停在成功图形。', duration: 700, loop: false, sceneId: 'saved', type: 'saved' },
    { id: 'empty-arrival', label: '等候 · 轻轻出现', description: '空态内容进入时播放一次，不掩盖添加或搜索入口。', duration: 650, loop: false, sceneId: 'library-empty', type: 'empty' },
    { id: 'retry-notice', label: '重试 · 温和提醒', description: '错误标记轻摆一次；不震动整个页面，也不自动重试任务。', duration: 520, loop: false, sceneId: 'startup-error', type: 'retry' },
    { id: 'pause-rest', label: '暂停 · 尾巴歇下', description: '任务暂停后轻轻收势一次，随后保持静止。', duration: 500, loop: false, sceneId: 'paused', type: 'paused' },
    { id: 'research-done', label: '完成 · 翻到下文', description: '研究完成后书页和勾选轻展一次，随后展示结果入口。', duration: 1000, loop: false, sceneId: 'complete', type: 'complete' },
  ];

  function escape(value) {
    return String(value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[c]);
  }
  function color(value, fallback) {
    if (value == null) return fallback;
    if (/^#(?:[0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(value) || value === 'currentColor') return value;
    throw new TypeError('Use a hex color or currentColor.');
  }
  function wrap(content, options, title) {
    options = options || {};
    const size = options.size == null ? 160 : Number(options.size);
    if (!Number.isFinite(size) || size <= 0 || size > 4096) throw new RangeError('Invalid SVG size.');
    const foreground = color(options.color, ink);
    const eye = color(options.eyeColor, options.background ? color(options.background, paper) : paper);
    const tile = options.background ? '<rect width="160" height="160" rx="' + (options.rounded === false ? '0' : '32') + '" fill="' + color(options.background, paper) + '"/>' : '';
    return '<svg xmlns="http://www.w3.org/2000/svg" width="' + size + '" height="' + size + '" viewBox="0 0 160 160" role="img" aria-label="' + escape(title) + '" style="color:' + foreground + ';--fox-eye:' + eye + '"><title>' + escape(title) + '</title>' + tile + content + '</svg>';
  }
  function svg(id, options) {
    const scene = scenes.find((entry) => entry.id === id);
    if (!scene) throw new RangeError('Unknown scene: ' + id);
    return wrap(scene.body, options, scene.label);
  }
  function fox(options) { return wrap(foxParts(), options, '有下文 · 长尾狐'); }
  return { scenes, motions, svg, fox };
});
