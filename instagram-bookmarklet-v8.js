(function () {
  // === IG 擷取 v8.1 ===
  // 徹底換 framework：
  //   Phase 1 純滾動蒐集 URL（不點 modal，IG 不易察覺）
  //   Phase 2 用 fetch() 直接抓每個 URL 的 HTML，從 embed/captioned 或 og:description 拿 caption
  //
  // 優點：
  //   - URL 蒐集與 caption 擷取分離 → 漏抓中間貼文機率大幅降低
  //   - 不點 modal → 不觸發 IG 自動化偵測
  //   - 可中斷續抓（state 存在 localStorage）
  //
  // v8.1 變更（相對 v8）：
  //   - decodeHtmlEntities 補上一般 &#xHHHH; / &#NNNN; 解碼（emoji + 中文不再爛碼）
  //   - parseDateFromHtml 也檢 og:description（IG 主頁 URL 的日期通常在這）
  //   - parseOgDescription 去掉結尾殘留的 ". "

  if (window._igScraper) { window._igScraper.stop(false); return; }

  var aMatch = location.href.match(/instagram\.com\/([\w.]+)/);
  var author = aMatch ? aMatch[1] : 'unknown';
  var isReelsTab = /\/reels\/?(\?|$)/.test(location.href);
  var modeLabel = isReelsTab ? 'reels' : 'main';

  var sk_posts = '_ig_' + author;
  var sk_urls  = '_ig_urls_' + author + (isReelsTab ? '_reels' : '_main');
  var sk_phase = '_ig_phase_' + author + (isReelsTab ? '_reels' : '_main');
  var sk_failed = '_ig_failed_' + author + (isReelsTab ? '_reels' : '_main');

  var posts = {};
  try { posts = JSON.parse(localStorage.getItem(sk_posts) || '{}'); } catch (e) {}

  var urlSet = new Set();
  try {
    JSON.parse(localStorage.getItem(sk_urls) || '[]').forEach(function (u) { urlSet.add(u); });
  } catch (e) {}

  var failedUrls = {};
  try { failedUrls = JSON.parse(localStorage.getItem(sk_failed) || '{}'); } catch (e) {}

  var phase = localStorage.getItem(sk_phase) || 'collect';

  // posts 已存的 URL，方便 Phase 2 跳過
  var fetchedUrls = new Set();
  Object.values(posts).forEach(function (p) { if (p.url) fetchedUrls.add(p.url); });

  function hash(str) {
    var h = 5381, s = (str || '').substring(0, 150);
    for (var i = 0; i < s.length; i++) {
      h = ((h << 5) + h) ^ s.charCodeAt(i);
      h = h & h;
    }
    return (h >>> 0).toString(16);
  }

  function saveAll() {
    try {
      localStorage.setItem(sk_posts, JSON.stringify(posts));
      localStorage.setItem(sk_urls, JSON.stringify(Array.from(urlSet)));
      localStorage.setItem(sk_phase, phase);
      localStorage.setItem(sk_failed, JSON.stringify(failedUrls));
    } catch (e) {}
  }

  // ── UI Panel ──
  var existingPanel = document.getElementById('_ig_panel');
  if (existingPanel) existingPanel.remove();
  var panel = document.createElement('div');
  panel.id = '_ig_panel';
  panel.style.cssText = 'position:fixed;top:20px;right:20px;z-index:2147483647;background:#fff;border:2px solid #e1306c;border-radius:14px;padding:14px 16px;width:320px;box-shadow:0 6px 24px rgba(0,0,0,0.18);font-family:-apple-system,sans-serif;font-size:13px;line-height:1.5';
  panel.innerHTML =
    '<div style="font-weight:700;color:#c13584;font-size:14px">IG 擷取 v8.1' +
      '&nbsp;<span style="background:#fce4ec;color:#c13584;padding:1px 7px;border-radius:10px;font-size:11px">' + modeLabel + '</span>' +
      '&nbsp;<span id="_ig_phase_badge" style="background:#dbeafe;color:#1e40af;padding:1px 7px;border-radius:10px;font-size:11px">Phase ?</span>' +
    '</div>' +
    '<div style="color:#555;font-size:12px;margin-bottom:6px">@' + author + '</div>' +
    '<div id="_ig_st" style="color:#777;font-size:11px;margin-bottom:6px;min-height:14px">啟動中...</div>' +
    '<div style="background:#fce4ec;border-radius:8px;padding:8px 10px;margin-bottom:8px;font-size:12px">' +
      '<div>URL 蒐集 <b id="_ig_urls" style="color:#c13584;font-size:16px">0</b> 　已抓內容 <b id="_ig_n" style="color:#e1306c;font-size:18px">0</b></div>' +
      '<div style="margin-top:3px">進度 <b id="_ig_prog">0/0</b>　失敗 <b id="_ig_f" style="color:#9ca3af">0</b>　最新：<span id="_ig_d" style="color:#ad1457">-</span></div>' +
    '</div>' +
    '<div style="display:flex;gap:6px">' +
      '<button id="_ig_stop" style="flex:1;background:#9ca3af;color:#fff;border:none;padding:6px;border-radius:8px;cursor:pointer;font-size:11px">停止</button>' +
      '<button id="_ig_finish" style="flex:1;background:#16a34a;color:#fff;border:none;padding:6px;border-radius:8px;cursor:pointer;font-size:11px">完成</button>' +
      '<button id="_ig_copy" style="flex:1;background:#e1306c;color:#fff;border:none;padding:6px;border-radius:8px;cursor:pointer;font-size:11px">複製</button>' +
    '</div>' +
    '<details style="margin-top:6px;font-size:11px;color:#555">' +
      '<summary style="cursor:pointer;color:#c13584;user-select:none">📖 v8.1 流程</summary>' +
      '<div style="padding:6px 4px;line-height:1.6">' +
        '<b>Phase 1（蒐集 URL）：</b>純滾動，不點 modal，把所有 /p/ /reel/ URL 加進清單<br>' +
        '<b>Phase 2（抓內容）：</b>對每個 URL 用 fetch() 拿 HTML，從 embed/captioned 解 caption<br>' +
        '<b>節奏：</b>P1 每 1.2 秒一拍，P2 每篇隨機 1.5~3 秒<br>' +
        '<b>可中斷：</b>關 tab / Stop 後再點書籤可從上次斷點續抓<br>' +
        '<b>清除：</b>點「清 IG 資料」會清掉 URL list + posts + phase'+
      '</div>' +
    '</details>' +
    '<div id="_ig_log" style="margin-top:7px;font-size:11px;color:#999;word-break:break-all;min-height:30px;max-height:60px;overflow:hidden"></div>';
  document.body.appendChild(panel);

  function $(id) { return document.getElementById(id); }

  function ui() {
    var nPosts = Object.keys(posts).length;
    var dates = Object.values(posts).map(function (p) { return p.date; }).filter(Boolean).sort().reverse();
    $('_ig_urls').textContent = urlSet.size;
    $('_ig_n').textContent = nPosts;
    $('_ig_prog').textContent = fetchedUrls.size + '/' + urlSet.size;
    $('_ig_f').textContent = Object.keys(failedUrls).length;
    $('_ig_d').textContent = dates[0] || '-';
    $('_ig_phase_badge').textContent = phase === 'collect' ? 'Phase 1: 蒐集' : 'Phase 2: 抓內容';
  }

  var logHistory = [];
  function log(msg) {
    logHistory.unshift(msg);
    if (logHistory.length > 4) logHistory.pop();
    $('_ig_log').innerHTML = logHistory.join('<br>');
  }

  // ── Phase 1: URL collection ──
  function collectVisibleUrls() {
    var sel = isReelsTab
      ? 'a[href*="/reel/"]'
      : 'a[href*="/p/"], a[href*="/reel/"]';
    var added = 0;
    document.querySelectorAll(sel).forEach(function (a) {
      var url = a.href.split('?')[0];
      // 過濾：必須是這個作者的貼文（href 通常是 /p/XYZ/ 或 /reel/XYZ/，不帶 author 路徑）
      if (!/\/(p|reel)\/[^/]+\/$/.test(url)) return;
      if (!urlSet.has(url)) {
        urlSet.add(url);
        added++;
      }
    });
    return added;
  }

  // ── Phase 2: caption fetch ──
  function decodeHtmlEntities(s) {
    if (!s) return '';
    // Hex numeric entities &#xHHHH;
    s = s.replace(/&#x([0-9a-fA-F]+);/g, function (_, hex) {
      try { return String.fromCodePoint(parseInt(hex, 16)); }
      catch (e) { return ''; }
    });
    // Decimal numeric entities &#NNNN;
    s = s.replace(/&#(\d+);/g, function (_, dec) {
      try { return String.fromCodePoint(parseInt(dec, 10)); }
      catch (e) { return ''; }
    });
    // Named entities
    return s.replace(/&nbsp;/g, ' ')
            .replace(/&amp;/g, '&')
            .replace(/&quot;/g, '"')
            .replace(/&apos;/g, "'")
            .replace(/&lt;/g, '<')
            .replace(/&gt;/g, '>');
  }

  function parseEmbedCaption(html) {
    // IG embed page 結構：<div class="Caption">...</div> 含完整 caption
    // 也可能是 <div class="CaptionContainer"> 或其他
    var m = html.match(/<div[^>]*class="[^"]*Caption[^"]*"[^>]*>([\s\S]*?)<\/div>/);
    if (m) {
      var inner = m[1];
      // 去掉 <a class="CaptionUsername">...</a> 之類的作者連結
      inner = inner.replace(/<a[^>]*class="[^"]*CaptionUsername[^"]*"[^>]*>[\s\S]*?<\/a>/g, '');
      // 去掉 <br>
      inner = inner.replace(/<br\s*\/?>/gi, '\n');
      // 移除其他 HTML tags
      inner = inner.replace(/<[^>]+>/g, '');
      var caption = decodeHtmlEntities(inner).trim();
      if (caption.length > 5) return caption;
    }
    return null;
  }

  function parseOgDescription(html) {
    // <meta property="og:description" content="N likes, M comments - zhao1945 on May 10, 2026: &quot;caption&quot;">
    var m = html.match(/<meta\s+property="og:description"\s+content="([^"]+)"/);
    if (!m) return null;
    var text = decodeHtmlEntities(m[1]);
    // 嘗試擷取 colon + quote 後的 caption
    var idx = text.indexOf(': "');
    var cap;
    if (idx >= 0) {
      cap = text.substring(idx + 3);
    } else {
      // 沒找到 quote 結構就回傳原文
      cap = text;
    }
    // 去掉結尾殘留 quote + "."（og:description 樣板殘餘）
    cap = cap.replace(/"\.\s*$/, '').replace(/\s+$/, '');
    if (cap.endsWith('"')) cap = cap.slice(0, -1);
    return cap;
  }

  function parseDateFromHtml(html) {
    // 1. og:title / og:description 含 "on Month Day, Year"
    //    主 URL 在 og:description（"N likes, M comments - user on May 10, 2026: ..."）
    //    embed/captioned 通常在 og:title
    var m = html.match(/<meta\s+property="og:(?:title|description)"\s+content="[^"]*?\bon\s+([A-Z][a-z]+\s+\d+,\s+\d{4})\b/);
    if (m) {
      try {
        var d = new Date(m[1]);
        if (!isNaN(d)) return d.toISOString().slice(0, 10);
      } catch (e) {}
    }
    // 2. embed page 的 <time datetime="...">
    m = html.match(/<time[^>]*datetime="([^"]+)"/);
    if (m) return m[1].slice(0, 10);
    // 3. JSON 內的 taken_at_timestamp
    m = html.match(/"taken_at_timestamp"\s*:\s*(\d+)/);
    if (m) {
      var d2 = new Date(parseInt(m[1]) * 1000);
      if (!isNaN(d2)) return d2.toISOString().slice(0, 10);
    }
    // 4. ISO datetime hidden in body
    m = html.match(/datetime="(\d{4}-\d{2}-\d{2})/);
    if (m) return m[1];
    return null;
  }

  function fetchOne(url) {
    return new Promise(function (resolve) {
      // 先試 embed/captioned（完整 caption）
      fetch(url + 'embed/captioned/', { credentials: 'include' })
        .then(function (r) { return r.ok ? r.text() : Promise.reject('embed http ' + r.status); })
        .then(function (html) {
          var caption = parseEmbedCaption(html);
          var date = parseDateFromHtml(html);
          if (caption) {
            resolve({ caption: caption.substring(0, 2000), date: date, source: 'embed' });
            return;
          }
          throw 'embed no caption';
        })
        .catch(function () {
          // Fallback: 抓主 URL 解 og:description（截短）
          fetch(url, { credentials: 'include' })
            .then(function (r) { return r.ok ? r.text() : Promise.reject('main http ' + r.status); })
            .then(function (html) {
              var caption = parseOgDescription(html);
              var date = parseDateFromHtml(html);
              if (caption) {
                resolve({ caption: caption.substring(0, 2000), date: date, source: 'og' });
              } else {
                resolve(null);
              }
            })
            .catch(function () { resolve(null); });
        });
    });
  }

  // ── 狀態機 ──
  var stopped = false;
  var idleScrolls = 0;
  var P1_IDLE_THRESHOLD = 25;   // 連續 25 拍沒新 URL 就進 Phase 2
  var P1_INTERVAL = 1200;       // Phase 1 每拍 1.2 秒
  var fetchInProgress = false;

  function tick() {
    if (stopped) return;

    if (phase === 'collect') {
      var added = collectVisibleUrls();
      if (added > 0) {
        idleScrolls = 0;
        log('+' + added + ' URLs (total ' + urlSet.size + ')');
      } else {
        idleScrolls++;
      }

      // scroll 策略：每 5 拍 bounce 一次（往上一點，觸發 re-render）
      if (idleScrolls > 0 && idleScrolls % 5 === 0) {
        window.scrollBy(0, -400 - Math.floor(Math.random() * 300));
      } else {
        window.scrollBy(0, 1000 + Math.floor(Math.random() * 600));
      }

      saveAll();
      $('_ig_st').textContent = 'P1 蒐集 URL: idle=' + idleScrolls + '/' + P1_IDLE_THRESHOLD;
      ui();

      if (idleScrolls >= P1_IDLE_THRESHOLD) {
        phase = 'fetch';
        saveAll();
        log('✅ Phase 1 完成：' + urlSet.size + ' 個 URL');
        scheduleNext(2000);
        return;
      }

      scheduleNext(P1_INTERVAL);
      return;
    }

    if (phase === 'fetch') {
      if (fetchInProgress) {
        scheduleNext(500);
        return;
      }

      // 找下一個還沒抓的 URL
      var allUrls = Array.from(urlSet);
      var next = null;
      for (var i = 0; i < allUrls.length; i++) {
        var u = allUrls[i];
        if (fetchedUrls.has(u)) continue;
        if ((failedUrls[u] || 0) >= 2) continue;  // 失敗 2 次就放棄
        next = u;
        break;
      }

      if (!next) {
        $('_ig_st').textContent = '✅ 全部抓完';
        stop(true);
        return;
      }

      fetchInProgress = true;
      $('_ig_st').textContent = 'P2 抓內容: ' + (fetchedUrls.size + 1) + '/' + urlSet.size;
      ui();

      fetchOne(next).then(function (result) {
        fetchInProgress = false;
        if (result && result.caption && result.caption.length > 3) {
          var key = hash(result.caption);
          // 處理 hash 衝突：若 key 已存在但 url 不同，append 些東西讓 key 不同
          if (posts[key] && posts[key].url !== next) {
            key = key + '_' + next.split('/').filter(Boolean).pop();
          }
          posts[key] = {
            author: author,
            date: result.date || '',
            type: /\/reel\//.test(next) ? 'reel' : 'post',
            url: next,
            content: result.caption
          };
          fetchedUrls.add(next);
          delete failedUrls[next];
          saveAll();
          log('✅ ' + (result.date || '?') + ' [' + result.source + '] ' + result.caption.length + '字');
        } else {
          failedUrls[next] = (failedUrls[next] || 0) + 1;
          saveAll();
          log('⚠️ 抓失敗 ' + (failedUrls[next]) + '/2 ' + next.split('/').filter(Boolean).pop());
        }
        ui();
        // 隨機間隔 1.5~3 秒
        scheduleNext(1500 + Math.random() * 1500);
      });
      return;
    }
  }

  var timer = null;
  function scheduleNext(delay) {
    if (stopped) return;
    if (timer) clearTimeout(timer);
    timer = setTimeout(tick, delay);
  }

  function stop(auto) {
    if (stopped) return;
    stopped = true;
    if (timer) clearTimeout(timer);
    window._igScraper = null;
    $('_ig_stop').style.display = 'none';
    $('_ig_finish').style.display = 'none';
    $('_ig_st').textContent = auto ? '✅ 完成' : '⏹ 已停止';
    $('_ig_st').style.color = '#16a34a';

    var total = Object.keys(posts).length;
    var postCount = Object.values(posts).filter(function (p) { return p.type !== 'reel'; }).length;
    var reelCount = Object.values(posts).filter(function (p) { return p.type === 'reel'; }).length;
    log('共 ' + total + ' 篇 (post ' + postCount + ' / reel ' + reelCount + ')');

    if (auto) {
      var now = new Date();
      var ts = now.getFullYear() + '-' + ('0' + (now.getMonth() + 1)).slice(-2) + '-' + ('0' + now.getDate()).slice(-2) + ' ' +
               ('0' + now.getHours()).slice(-2) + ':' + ('0' + now.getMinutes()).slice(-2) + ':' + ('0' + now.getSeconds()).slice(-2);
      var nextHint = isReelsTab ? '' : '\n\n下一步：到 instagram.com/' + author + '/reels/ 跑 Reels 模式。';
      setTimeout(function () {
        alert('✅ IG ' + modeLabel + ' 模式完成 (v8.1)\n\n@' + author +
              '\nURL 蒐集：' + urlSet.size +
              '\n抓到內容：' + total +
              '\n  • /p/：' + postCount +
              '\n  • /reel/：' + reelCount +
              '\n失敗：' + Object.keys(failedUrls).length +
              '\n完成時間：' + ts +
              '\n\n點面板「複製」貼到對話框。' + nextHint);
      }, 200);
    }
  }

  function copy() {
    var arr = Object.values(posts)
      .filter(function (p) { return p.content && p.content.length > 3; })
      .sort(function (a, b) { return (b.date || '').localeCompare(a.date || ''); });
    var json = JSON.stringify(arr, null, 2);
    navigator.clipboard.writeText(json).catch(function () {
      var ta = document.createElement('textarea');
      ta.value = json; document.body.appendChild(ta); ta.select();
      document.execCommand('copy'); document.body.removeChild(ta);
    });
    alert('已複製 ' + arr.length + ' 筆');
  }

  $('_ig_stop').onclick = function () { stop(false); };
  $('_ig_finish').onclick = function () { stop(true); };
  $('_ig_copy').onclick = copy;
  window._igScraper = { stop: function (auto) { stop(auto || false); } };

  ui();
  $('_ig_st').textContent = '啟動 v8 - phase: ' + phase;
  scheduleNext(800);
})();
