// Local deterministic protocol fixture. It never contacts a model or search vendor.
import http from 'node:http';
const counts = { analysis: 0, research: 0, search: 0, synthesis: 0, sourceSummary: 0, pdfSummary: 0, sourceMerge: 0 };
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAIAAADYYG7QAAAAQklEQVR4nO3OMQ0AIBAAsXfHiBD877jgGJpUQGed/ZXJB0JCQkL1QEhISKgeCAkJCdUDISEhoXogJCQkVA+EhIQeu13nCYghyLU9AAAAAElFTkSuQmCC', 'base64');
function pdf() {
  const stream = 'BT /F1 20 Tf 40 120 Td (Readlater local PDF evidence) Tj ET';
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    `<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`,
  ];
  let data = '%PDF-1.4\n';
  const offsets = [0];
  objects.forEach((object, i) => { offsets.push(Buffer.byteLength(data)); data += `${i + 1} 0 obj\n${object}\nendobj\n`; });
  const xref = Buffer.byteLength(data);
  data += `xref\n0 6\n0000000000 65535 f \n${offsets.slice(1).map(x => `${String(x).padStart(10, '0')} 00000 n \n`).join('')}trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return Buffer.from(data);
}
const server = http.createServer(async (req, res) => {
  const send = (status, type, body) => { res.writeHead(status, {'content-type': type}); res.end(body); };
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname === '/stats') return send(200, 'application/json', JSON.stringify(counts));
  if (url.pathname === '/image.png') return send(200, 'image/png', png);
  if (url.pathname === '/sample.pdf') return send(200, 'application/pdf', pdf());
  if (url.pathname === '/feed') return send(200, 'application/rss+xml; charset=utf-8', `<?xml version="1.0"?><rss version="2.0"><channel><title>研究订阅</title><item><guid>fixture-a</guid><title>博客笔记</title><link>http://${req.headers.host}/article</link><description>从资料到认识</description></item><item><guid>fixture-b</guid><title>订阅中的新观点</title><link>http://${req.headers.host}/second</link></item></channel></rss>`);
  if (['/article','/wechat','/second'].includes(url.pathname)) {
    const tag = url.pathname === '/wechat' ? 'div id="js_content"' : 'article';
    const closing = url.pathname === '/wechat' ? 'div' : 'article';
    return send(200, 'text/html; charset=utf-8', `<html><head><title>从收藏到认识</title></head><body><nav>杂项菜单</nav><${tag}><h1>从收藏到认识</h1><p>笔记应当留下自己的问题，并保留原文出处。将不同资料放在一起比较，才能逐渐判断一个观点的适用条件。</p><p>阅读之后需要区分资料的主张和自己的推断，发现分歧时再提出下一步研究问题，而不是把收藏当作已经掌握。</p><img data-src="/image.png"></${closing}></body></html>`);
  }
  if (req.method !== 'POST') return send(404, 'text/plain', 'not found');
  const chunks = []; for await (const chunk of req) chunks.push(chunk);
  let body; try { body = JSON.parse(Buffer.concat(chunks).toString()); } catch { return send(400, 'text/plain', 'invalid JSON'); }
  if (req.headers.authorization !== 'Bearer fixture-key') return send(401, 'text/plain', 'fixture authorization required');
  if (url.pathname === '/search') {
    counts.search++;
    return send(200, 'application/json; charset=utf-8', JSON.stringify({results:[{title:'知识管理依据',url:`http://${req.headers.host}/article`,content:'把来源、结论与适用范围分开，能够帮助持续检验认识。',raw_content:'检索所得资料：来源与推断必须区分，重复阅读不代表认同。'}]}));
  }
  if (url.pathname === '/v1/chat/completions') {
    const content = body.messages.at(-1).content;
    const text = Array.isArray(content) ? content[0].text : content;
    let result;
    if (text.includes('"task":"summarize_source_segment"')) {
      counts.sourceSummary++;
      result = {summary: '中立摘要：资料片段要求保留原始来源，并区分资料主张和个人推断。'};
    } else if (text.includes('"task":"summarize_pdf_pages"')) {
      counts.pdfSummary++;
      result = {summary: '中立摘要：PDF 页面展示本地验证资料，需打开原始页图核对。'};
    } else if (text.includes('"task":"merge_source_segment_summaries"')) {
      counts.sourceMerge++;
      result = {summary: '合并摘要：原始资料与推断应分开保存，保留可核对的来源。'};
    } else if (text.includes('生成观点卡片')) {
      counts.analysis++;
      const marker = '\n输入数据：';
      const input = JSON.parse(text.slice(text.indexOf(marker) + marker.length));
      result = {summary:'收藏只有带着问题阅读，才能逐渐形成认识。',insights:[`保留来源与适用条件 [${input.item.id}]`],connections: input.related.length ? ['与已有笔记相互补充'] : ['目前没有相关的本地资料'],questions:['如何验证笔记方法的适用范围？'],sourceIds:[input.item.id],suggestedTopics:['个人知识管理']};
      const block = input.item.contentBlocks?.find(block => block.text?.trim());
      const evidence = input.availableEvidence !== undefined
        ? input.availableEvidence.slice(0, 1)
        : block ? [{sourceId: input.item.id, sourceVersion: input.item.contentVersion, blockId: block.id, quote: block.text}] : [];
      result.structuredInsights = evidence.length ? [{id: `fixture-${input.item.id}`, title: '保留来源与适用条件', finding: '原始资料是核对观点的依据。', evidence, unknowns: ['实际效果仍需验证。']}] : [];
    } else if (text.includes('仅基于以下本地资料')) {
      counts.synthesis++;
      const input = JSON.parse(text.slice(text.lastIndexOf('\n{') + 1));
      result = {overview:`现有资料都强调保留来源，但实践效果仍需查证 [${input.sources[0].id}]`, sourceIds:input.sources.map(x=>x.id)};
    } else {
      counts.research++;
      const input = JSON.parse(text.slice(text.lastIndexOf('\n{') + 1));
      result = {report:'已有证据支持将原始资料与自己的推断区分保存 [S1]。仍需验证不同学习场景的适用性。',nextQuery:input.remainingCalls>=2?'进一步比较适用条件':'',meaningful:input.previousReport===''};
    }
    return send(200,'application/json; charset=utf-8',JSON.stringify({choices:[{message:{role:'assistant',content:JSON.stringify(result)}}]}));
  }
  send(404,'text/plain','not found');
});
server.listen(Number(process.env.READLATER_FIXTURE_PORT ?? 18765), '127.0.0.1', () => console.log(`Readlater local fixture listening on 127.0.0.1:${server.address().port}`));
