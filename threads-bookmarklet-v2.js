(function () {
  if (window._tScraper) { window._tScraper.stop(); return; }

  var aM = location.href.match(/threads\.(?:com|net)\/@([\w.]+)/);
  var author = aM ? aM[1] : 'unknown';
  var sk = '_threads_' + author;

  var posts = {};
  try { posts = JSON.parse(localStorage.getItem(sk) || '{}'); } catch(e) {}

  // ── ★ V3.5：Garbage 判定（套 IG V5+ 規則）──────────────────────────────
  function isGarbage(text) {
    if (!text || text.length < 15) return true;
    // Threads / Threads 影片字幕的副本
    if (/^\d+則\s*(Facebook\s*)?留言/.test(text)) return true;
    if (/^這段.{0,15}有\d+則/.test(text)) return true;
    // Artist • Song 音樂
    if (/^[^一-鿿•\n]+•[^一-鿿\n]+$/.test(text) && text.length < 80) return true;
    // 純日期
    if (/^\d{4}年\d{1,2}月\d{1,2}日$/.test(text)) return true;
    // 純帳號（純英數）
    if (/^[A-Za-z\d._@]+$/.test(text) && text.length < 40) return true;
    // 互動通知
    if (/和其他人都說讚$/.test(text)) return true;
    // UI 文字
    if (/^查看更多/.test(text) && text.length < 40) return true;
    if (/^\d+\s*(讚|likes?|comments?|replies?|個讚|則留言)$/i.test(text.trim())) return true;
    // 純 hashtag（無中文有意義內容）
    if (/^[\s#@\w.\-]+$/.test(text) && !/[一-鿿]/.test(text) && text.length < 100) return true;
    // 廣告 / 業配 / 商店連結
    if (/shop-flyingacoustic|👇.*專屬購買連結|funlikev\.com/.test(text)) return true;
    if (/^業配 有需要可以看看/.test(text)) return true;
    // 穿搭/Fashion 雜訊（zhao1945 早期內容）
    if (/一天一穿搭|顏值不夠.*穿搭/.test(text)) return true;
    return false;
  }

  // ── ★ V3.5：啟動時清掉舊資料中的 garbage ────────────────────────────────
  (function cleanLegacyGarbage() {
    var removed = 0;
    Object.keys(posts).forEach(function(k) {
      if (posts[k] && posts[k].content && isGarbage(posts[k].content)) {
        delete posts[k];
        removed++;
      }
    });
    if (removed > 0) {
      localStorage.setItem(sk, JSON.stringify(posts));
      window._tsLegacyRemoved = removed;
    }
  })();

  // ── 日期解析：相對時間 → ISO ──────────────────────────────────────────────
  function resolveDate(raw) {
    if (!raw) return new Date().toISOString().slice(0, 10);
    raw = String(raw).trim();
    if (/^\d{4}-\d{2}-\d{2}/.test(raw)) return raw.slice(0, 10);
    var d = new Date(), m;
    if (/剛剛|秒/.test(raw)) return d.toISOString().slice(0, 10);
    if (/小時|小时/.test(raw)) return d.toISOString().slice(0, 10);
    if (/昨天/.test(raw)) { d.setDate(d.getDate() - 1); return d.toISOString().slice(0, 10); }
    if ((m = raw.match(/(\d+)\s*(天)/))) { d.setDate(d.getDate() - parseInt(m[1])); return d.toISOString().slice(0, 10); }
    if ((m = raw.match(/(\d+)\s*(週|周)/))) { d.setDate(d.getDate() - parseInt(m[1]) * 7); return d.toISOString().slice(0, 10); }
    if ((m = raw.match(/(\d+)\s*(個月)/))) { d.setMonth(d.getMonth() - parseInt(m[1])); return d.toISOString().slice(0, 10); }
    if ((m = raw.match(/(\d{4})年(\d{1,2})月(\d{1,2})日/))) {
      return m[1] + '-' + ('0' + m[2]).slice(-2) + '-' + ('0' + m[3]).slice(-2);
    }
    if ((m = raw.match(/^(\d{1,2})月(\d{1,2})日/))) {
      return d.getFullYear() + '-' + ('0' + m[1]).slice(-2) + '-' + ('0' + m[2]).slice(-2);
    }
    return d.toISOString().slice(0, 10);
  }

  // ── 內容 hash（dedup 用，取代舊版 date|length 爛 key）─────────────────────
  function hash(str) {
    var h = 5381, s = str.substring(0, 150);
    for (var i = 0; i < s.length; i++) {
      h = ((h << 5) + h) ^ s.charCodeAt(i);
      h = h & h;
    }
    return (h >>> 0).toString(16);
  }

  // ── V1 資料遷移：舊 key(date|length) → 新 key(hash) ─────────────────────
  // 避免 V2 把舊資料當新資料重複存入
  (function migrate() {
    var needsMigration = false;
    Object.keys(posts).forEach(function(k) {
      if (k.indexOf('|') !== -1) needsMigration = true;
    });
    if (!needsMigration) return;

    var migrated = {};
    Object.keys(posts).forEach(function(k) {
      var p = posts[k];
      if (!p || !p.content) return;
      var newKey = hash(p.content);
      if (!migrated[newKey]) {
        migrated[newKey] = {
          author: p.author || author,
          date: resolveDate(p.date || ''),
          content: p.content
        };
      }
    });
    posts = migrated;
    localStorage.setItem(sk, JSON.stringify(posts));
  })();

  // ── UI Panel ───────────────────────────────────────────────────────────────
  // 啟動時清掉舊 panel
  var existingPanel = document.getElementById('_ts_panel');
  if (existingPanel) existingPanel.remove();
  var panel = document.createElement('div');
  panel.id = '_ts_panel';
  panel.style.cssText = [
    'position:fixed','top:20px','right:20px','z-index:2147483647',
    'background:#fff','border:2px solid #000','border-radius:14px',
    'padding:14px 16px','width:280px',
    'box-shadow:0 6px 24px rgba(0,0,0,0.18)',
    'font-family:-apple-system,sans-serif','font-size:13px','line-height:1.5'
  ].join(';');
  panel.innerHTML =
    '<div style="font-weight:700;color:#000;font-size:14px;margin-bottom:4px">Threads 全量擷取 v3.5</div>' +
    '<div style="color:#555;font-size:12px">@' + author + '</div>' +
    '<div id="_ts_st" style="color:#777;font-size:11px;margin-bottom:6px">啟動中...</div>' +
    '<div style="background:#f3f4f6;border-radius:8px;padding:8px 10px;margin-bottom:8px">' +
      '<span id="_ts_n" style="font-size:22px;font-weight:700;color:#111">0</span>' +
      '<span style="font-size:12px;color:#666"> 篇</span><br>' +
      '<span id="_ts_d" style="font-size:11px;color:#444">最新：-</span>' +
    '</div>' +
    '<div style="display:flex;gap:6px">' +
      '<button id="_ts_s" style="flex:1;background:#ef4444;color:#fff;border:none;padding:6px;border-radius:8px;cursor:pointer;font-size:12px">停止</button>' +
      '<button id="_ts_c" style="flex:1;background:#111;color:#fff;border:none;padding:6px;border-radius:8px;cursor:pointer;font-size:12px">複製</button>' +
      '<button id="_ts_dl" style="flex:1;background:#0891b2;color:#fff;border:none;padding:6px;border-radius:8px;cursor:pointer;font-size:12px">下載</button>' +
    '</div>' +
    '<details style="margin-top:6px;font-size:11px;color:#555">' +
      '<summary style="cursor:pointer;color:#111;user-select:none">📖 操作說明</summary>' +
      '<div style="padding:6px 4px;line-height:1.6">' +
        '<b>1.</b> 在 <code>threads.com/@&lt;作者&gt;</code> 點此書籤<br>' +
        '<b>2.</b> 自動滾動 + DOM 抓貼文<br>' +
        '<b>3.</b> 連續 12 拍沒新篇 → 自動停（或按 <b>停止</b>）<br>' +
        '<b>4.</b> 點 <b>複製</b> → 跑 <code>save_clipboard.ps1</code> 存檔<br><br>' +
        '<b>特性</b>：DOM 優先（<code>article</code> / <code>[data-pressable-container=true]</code>）；找不到結構自動退 regex；抓 permalink URL；自動點「更多」展開內文；啟動時清舊 garbage' +
      '</div>' +
    '</details>' +
    '<div id="_ts_l" style="margin-top:7px;font-size:11px;color:#999;word-break:break-all;min-height:16px"></div>';
  document.body.appendChild(panel);

  var stEl = document.getElementById('_ts_st');
  var nEl  = document.getElementById('_ts_n');
  var dEl  = document.getElementById('_ts_d');
  var lEl  = document.getElementById('_ts_l');

  function ui() {
    var keys = Object.keys(posts);
    var dates = keys.map(function(k){ return posts[k].date; }).filter(Boolean).sort().reverse();
    nEl.textContent = keys.length;
    dEl.textContent = dates[0] || '-';
  }

  // ── 展開「更多」─────────────────────────────────────────────────────────────
  // ★ V3.5：限定在貼文容器內（article / role=article / data-pressable-container）
  // 避免誤點到 Threads 左側導航選單裡的「更多」設定按鈕
  function expandMore() {
    var containers = document.querySelectorAll('article, [role="article"], div[data-pressable-container="true"]');
    containers.forEach(function(container) {
      container.querySelectorAll('div[role="button"], span[role="button"]').forEach(function(b) {
        var t = (b.innerText || '').trim();
        if (t === '更多' || t === '... 更多' || t === 'more' || t === 'See more') {
          try { b.click(); } catch(e) {}
        }
      });
    });
  }

  // ── DOM 擷取（主要方式）──────────────────────────────────────────────────────
  // Threads 使用 article 元素，結構比 body.innerText regex 穩定
  function harvestDOM() {
    var panelEl = document.getElementById('_ts_panel');
    var added = 0;
    var containers = [];

    var selectors = ['article', '[role="article"]', 'div[data-pressable-container="true"]'];
    for (var i = 0; i < selectors.length; i++) {
      var found = Array.from(document.querySelectorAll(selectors[i]));
      // 至少要有 3 個才算找到（避免誤判）
      if (found.length >= 3) { containers = found; break; }
    }

    if (containers.length === 0) return -1; // 找不到，通知 fallback

    containers.forEach(function(el) {
      if (panelEl && panelEl.contains(el)) return;

      // 取日期（time[datetime] → 顯示文字）
      var date = '';
      var timeEl = el.querySelector('time[datetime]');
      if (timeEl) date = resolveDate(timeEl.getAttribute('datetime'));
      if (!date) {
        el.querySelectorAll('time, a[href*="/t/"]').forEach(function(t) {
          if (!date) {
            var txt = (t.innerText || '').trim();
            if (txt && txt.length < 20) date = resolveDate(txt);
          }
        });
      }

      // ★ V3：抓 permalink（threads.com/@user/post/XXX）
      var url = '';
      var permLink = el.querySelector('a[href*="/post/"]');
      if (permLink) url = permLink.href.split('?')[0];

      // 取內容（最長的 dir="auto" 元素）
      var content = '', maxLen = 0;
      el.querySelectorAll('span[dir="auto"], div[dir="auto"]').forEach(function(d) {
        if (panelEl && panelEl.contains(d)) return;
        var t = (d.innerText || '').trim();
        if (t.length > maxLen && t.length > 10) { maxLen = t.length; content = t; }
      });

      if (!content || content.length < 10) return;

      var clean = content.split('\n')
        .map(function(l){ return l.trim(); })
        .filter(function(l){ return l.length > 0 && !/^\d+$/.test(l); })
        .join('\n').substring(0, 2000);

      // ★ V3.5：垃圾過濾
      if (isGarbage(clean)) return;

      var key = hash(clean);
      if (!posts[key]) {
        posts[key] = { author: author, date: date, content: clean, url: url };
        added++;
      } else if (url && !posts[key].url) {
        // ★ V3：舊資料沒 url → 回補
        posts[key].url = url;
      }
    });

    return added;
  }

  // ── innerText regex 擷取（fallback）─────────────────────────────────────────
  // 當 DOM 選擇器找不到結構時用，移除 panel 文字避免污染
  function harvestRegex() {
    var panelEl = document.getElementById('_ts_panel');
    var panelText = panelEl ? (panelEl.innerText || '') : '';
    var text = document.body.innerText;
    // 移除 panel 自身文字，避免被當成貼文內容
    if (panelText) { text = text.split(panelText).join(''); }

    var ea = author.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    var tp = '(?:\\d+(?:小時|天|週|個月)|20\\d\\d-\\d{1,2}-\\d{1,2})';
    var regex = new RegExp(
      ea + '\\n(' + tp + ')\\n(?:互動率：[\\d.]+%\\n)?([\\s\\S]*?)(?=' + ea + '\\n' + tp + '\\n|$)',
      'g'
    );

    var match, added = 0;
    while ((match = regex.exec(text)) !== null) {
      var date = resolveDate(match[1].trim());
      var content = match[2].trim();
      if (content.length < 15) continue;

      var clean = content.split('\n')
        .map(function(l){ return l.trim(); })
        .filter(function(l){ return l.length > 0 && !/^\d+$/.test(l); })
        .join('\n').substring(0, 2000);

      if (clean.length < 15) continue;
      // ★ V3.5：垃圾過濾
      if (isGarbage(clean)) continue;
      var key = hash(clean);
      if (!posts[key]) {
        posts[key] = { author: author, date: date, content: clean };
        added++;
      }
    }
    return added;
  }

  // ── 合併擷取（DOM 優先，失敗才 fallback regex）────────────────────────────
  function harvest() {
    var added = harvestDOM();
    if (added === -1) {
      added = harvestRegex(); // DOM 找不到結構，用 regex
      lEl.textContent = '[regex mode] +' + added + ' 篇';
    }
    if (added > 0) {
      localStorage.setItem(sk, JSON.stringify(posts));
      ui();
      if (added !== -1) lEl.textContent = '+' + added + ' 篇，共 ' + Object.keys(posts).length + ' 篇';
    }
    return Math.max(added, 0);
  }

  // ── 主循環 ─────────────────────────────────────────────────────────────────
  var round = 0, stuckCount = 0, extraScrolls = 0;
  var lastScrollH = 0, lastCount = 0;
  var noNewRun = 0; // ★ V3：連續多少拍沒抓到新篇

  var iv = setInterval(function() {
    var docEl = document.documentElement;

    expandMore();
    var added = harvest();

    var total = Object.keys(posts).length;
    var scrollH = docEl.scrollHeight;

    // ★ V3：連續 12 拍（~24秒）沒抓到新篇 → 視為已到舊資料區，自動停
    //   解決「page 一直載入舊內容、scrollH 一直變、永遠不 stuck」的問題
    if (added > 0) {
      noNewRun = 0;
    } else {
      noNewRun++;
      if (noNewRun >= 12) {
        stEl.textContent = '連 12 拍無新篇，停止';
        lEl.textContent = '⚡ 已到舊資料區';
        stop(true);
        return;
      }
    }

    if (scrollH === lastScrollH && total === lastCount) {
      stuckCount++;
      if (stuckCount >= 8) {
        if (extraScrolls < 5) {
          window.scrollTo(0, docEl.scrollHeight);
          extraScrolls++;
          stEl.textContent = '加載確認... 剩 ' + (5 - extraScrolls) + ' 次';
        } else {
          stop(true);
        }
      } else {
        stEl.textContent = '等待載入 (' + stuckCount + '/8)';
      }
    } else {
      stuckCount = 0; extraScrolls = 0;
      lastScrollH = scrollH; lastCount = total;
      docEl.scrollTop += 900;
      stEl.textContent = '滾動 (' + round + ') ' + total + '篇 / 無新 ' + noNewRun + '/12';
    }
    round++;
  }, 2000);

  // ── 停止 ───────────────────────────────────────────────────────────────────
  function stop(auto) {
    clearInterval(iv); window._tScraper = null;
    stEl.textContent = auto ? '✅ 全部完成！' : '⏹ 已停止';
    stEl.style.color = '#16a34a';
    document.getElementById('_ts_s').style.display = 'none';
    var total = Object.keys(posts).length;
    lEl.textContent = '共擷取 ' + total + ' 篇';
    if (auto) {
      var now = new Date();
      var ts = now.getFullYear() + '-' +
               ('0' + (now.getMonth()+1)).slice(-2) + '-' +
               ('0' + now.getDate()).slice(-2) + ' ' +
               ('0' + now.getHours()).slice(-2) + ':' +
               ('0' + now.getMinutes()).slice(-2) + ':' +
               ('0' + now.getSeconds()).slice(-2);
      var legacyMsg = window._tsLegacyRemoved ? ('\n啟動時清掉舊 garbage：' + window._tsLegacyRemoved + ' 篇') : '';
      setTimeout(function() {
        alert('✅ Threads 擷取完成\n\n@' + author + '\n總篇數：' + total + legacyMsg + '\n完成時間：' + ts + '\n\n點面板上「複製」即可貼到對話框。');
      }, 200);
    }
  }

  // ── 複製 ───────────────────────────────────────────────────────────────────
  // ★ V3.5：先 await 寫入，成功才 alert；失敗顯示警告並建議按「下載」
  function copy() {
    var arr = Object.values(posts).sort(function(a, b) {
      return (b.date || '').localeCompare(a.date || '');
    });
    var json = JSON.stringify(arr, null, 2);

    function fallback() {
      try {
        var ta = document.createElement('textarea');
        ta.value = json;
        ta.style.cssText = 'position:fixed;top:0;left:0;opacity:0';
        document.body.appendChild(ta);
        ta.focus();
        ta.select();
        var ok = document.execCommand('copy');
        document.body.removeChild(ta);
        return ok;
      } catch (e) { return false; }
    }

    navigator.clipboard.writeText(json).then(function() {
      alert('✅ 已複製 ' + arr.length + ' 筆！');
    }).catch(function() {
      if (fallback()) {
        alert('✅ 已複製 ' + arr.length + ' 筆！(fallback)');
      } else {
        alert('⚠️ 複製失敗（剪貼簿被擋）\n\n請按面板「下載」鈕匯出 JSON 檔。\n共 ' + arr.length + ' 筆。');
      }
    });
  }

  // ★ V3.5：下載 JSON 當保底（總是可用，不受剪貼簿權限影響）
  function download() {
    var arr = Object.values(posts).sort(function(a, b) {
      return (b.date || '').localeCompare(a.date || '');
    });
    var json = JSON.stringify(arr, null, 2);
    var blob = new Blob([json], {type: 'application/json'});
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    var ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    a.href = url;
    a.download = 'threads_' + author + '_' + ts + '.json';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(function() { URL.revokeObjectURL(url); }, 1000);
  }

  document.getElementById('_ts_s').onclick  = function() { stop(false); };
  document.getElementById('_ts_c').onclick  = copy;
  document.getElementById('_ts_dl').onclick = download;
  window._tScraper = { stop: function() { stop(false); } };

  ui();
  harvest();
  stEl.textContent = '開始滾動...';
})();
