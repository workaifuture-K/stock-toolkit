(function () {
  // ── V5.0 診斷：整段包 try/catch，有錯就 alert 出來
  try {

  if (window._fbScraper) {
    var oldVer = window._fbScraperVersion || '?';
    window._fbScraper.stop();
    alert('⚠️ 偵測到舊 scraper (v' + oldVer + ') 在跑，已停止。\n\n請再按一次書籤啟動 v5.4。');
    return;
  }
  window._fbScraperVersion = '5.4';
  console.log('%c[FB Scraper v5.4] 啟動了', 'color:#1877f2;font-weight:bold;font-size:14px');

  // ── V3.3 嚴格 URL 驗證 ──────────────────────────────────────────────────────
  var author = null;
  var blockedPaths = ['marketplace','groups','watch','events','gaming','home.php',
                      'login','reel','reels','stories','photo','photo.php','messages',
                      'help','settings','notifications','search','bookmarks','memories'];
  var profileIdMatch = location.href.match(/profile\.php\?[^#]*id=(\d+)/);
  if (profileIdMatch) {
    author = profileIdMatch[1];
  } else {
    var fbMatch = location.href.match(/facebook\.com\/(?:pages\/[^\/]+\/)?([^\/?#]+)/);
    if (fbMatch) {
      var candidate = fbMatch[1];
      if (blockedPaths.indexOf(candidate.toLowerCase()) === -1) {
        author = candidate;
      }
    }
  }
  if (!author) {
    alert('❌ 此書籤請在 facebook.com/<作者> 個人頁或粉專頁執行\n\n目前頁面不是個人/粉專頁。');
    return;
  }
  var sk = '_fb_' + author;

  var posts = {};
  try { posts = JSON.parse(localStorage.getItem(sk) || '{}'); } catch(e) {}

  // ── V5.0：頁面類型偵測 ──────────────────────────────────────────────────────
  // home / posts → 主時間軸（受 5-6 月限制）
  // photos       → 相片貼文（通常有更長歷史）
  // videos       → 影片貼文（同上）
  function detectPageType() {
    var p = location.pathname.toLowerCase();
    if (/\/photos(_by)?(\/|$)/.test(p)) return 'photos';
    if (/\/videos(\/|$)/.test(p)) return 'videos';
    if (/\/posts(\/|$)/.test(p)) return 'posts';
    return 'home';
  }
  var pageType = detectPageType();

  // ── V3.6 savePosts ──────────────────────────────────────────────────────────
  var saveFails = 0;
  function savePosts(label) {
    try {
      localStorage.setItem(sk, JSON.stringify(posts));
      return true;
    } catch (e) {
      saveFails++;
      console.error('FB scraper save failed at ' + label + ':', e);
      if (saveFails === 1) {
        alert('⚠️ localStorage 寫入失敗\n\n錯誤: ' + (e.message || e) + '\n\n位置: ' + label + '\n\n資料目前在記憶體（' + Object.keys(posts).length + ' 篇），先點面板「複製」備份再說！');
      }
      return false;
    }
  }

  // ── V3.2 Garbage 判定 ───────────────────────────────────────────────────────
  function isGarbage(text) {
    if (!text || text.length < 15) return true;
    if (/^\d+則\s*(Facebook\s*)?留言/.test(text)) return true;
    if (/^這段.{0,15}有\d+則/.test(text)) return true;
    if (/^[^一-鿿•\n]+•[^一-鿿\n]+$/.test(text) && text.length < 80) return true;
    if (/^\d{4}年\d{1,2}月\d{1,2}日$/.test(text)) return true;
    if (/^[A-Za-z\d._@]+$/.test(text) && text.length < 40) return true;
    if (/和其他人都說讚$/.test(text)) return true;
    if (/^(按讚|留言|分享|查看更多|See more|隱藏)$/.test(text.trim())) return true;
    if (/^\d+\s*(則?留言|個讚|次分享|likes?|comments?|shares?)$/i.test(text.trim())) return true;
    if (/^[\s#@\w.\-]+$/.test(text) && !/[一-鿿]/.test(text) && text.length < 100) return true;
    if (/shop-flyingacoustic|👇.*專屬購買連結|funlikev\.com/.test(text)) return true;
    if (/^(贊助|Sponsored)$/.test(text.trim())) return true;
    if (/^.{0,30}(立即購買|前往購物|了解更多)$/.test(text) && text.length < 60) return true;
    return false;
  }

  // 啟動時清掉舊 garbage
  (function cleanLegacyGarbage() {
    var removed = 0;
    Object.keys(posts).forEach(function(k) {
      if (posts[k] && posts[k].content && isGarbage(posts[k].content)) {
        delete posts[k];
        removed++;
      }
    });
    if (removed > 0) {
      savePosts('cleanLegacyGarbage');
      window._fbLegacyRemoved = removed;
    }
  })();

  // ── 日期解析 ───────────────────────────────────────────────────────────────
  function resolveDate(raw) {
    if (!raw) return new Date().toISOString().slice(0, 10);
    raw = String(raw).trim();
    if (/^\d{9,10}$/.test(raw)) {
      return new Date(parseInt(raw) * 1000).toISOString().slice(0, 10);
    }
    if (/^\d{4}-\d{2}-\d{2}/.test(raw)) return raw.slice(0, 10);
    var d = new Date(), m;
    if (/剛剛|秒/.test(raw)) return d.toISOString().slice(0, 10);
    if (/小時|小时/.test(raw)) return d.toISOString().slice(0, 10);
    if (/昨天|yesterday/i.test(raw)) { d.setDate(d.getDate() - 1); return d.toISOString().slice(0, 10); }
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

  // ── 內容雜湊（dedup）─────────────────────────────────────────────────────────
  function hash(str) {
    var h = 5381, s = str.substring(0, 150);
    for (var i = 0; i < s.length; i++) {
      h = ((h << 5) + h) ^ s.charCodeAt(i);
      h = h & h;
    }
    return (h >>> 0).toString(16);
  }

  // ── UI Panel ───────────────────────────────────────────────────────────────
  var existingPanel = document.getElementById('_fb_panel');
  if (existingPanel) existingPanel.remove();
  var panel = document.createElement('div');
  panel.id = '_fb_panel';
  panel.style.cssText = [
    'position:fixed','top:20px','right:20px','z-index:2147483647',
    'background:#fff','border:2px solid #1877f2','border-radius:14px',
    'padding:14px 16px','width:300px',
    'box-shadow:0 6px 24px rgba(0,0,0,0.18)',
    'font-family:-apple-system,sans-serif','font-size:13px','line-height:1.5'
  ].join(';');

  var pageTypeLabel = { home:'主頁', posts:'貼文', photos:'相片', videos:'影片' }[pageType];
  panel.innerHTML =
    '<div style="font-weight:700;color:#1877f2;font-size:14px;margin-bottom:4px">FB 擷取 v5.4 · 自主滾動</div>' +
    '<div style="color:#555;font-size:12px">@' + author + ' · <span style="background:#e7f3ff;padding:1px 6px;border-radius:4px">' + pageTypeLabel + '</span></div>' +
    '<div id="_fb_st" style="color:#777;font-size:11px;margin-bottom:6px">啟動中...</div>' +
    '<div style="background:#e7f3ff;border-radius:8px;padding:8px 10px;margin-bottom:8px">' +
      '<span id="_fb_n" style="font-size:22px;font-weight:700;color:#1877f2">0</span>' +
      '<span style="font-size:12px;color:#444"> 篇</span>' +
      '<span id="_fb_range" style="float:right;font-size:11px;color:#0d5bba;margin-top:8px">-</span>' +
    '</div>' +
    '<div style="display:flex;gap:6px;margin-bottom:6px">' +
      '<button id="_fb_s" style="flex:1;background:#ef4444;color:#fff;border:none;padding:6px;border-radius:8px;cursor:pointer;font-size:12px">停止</button>' +
      '<button id="_fb_c" style="flex:1;background:#1877f2;color:#fff;border:none;padding:6px;border-radius:8px;cursor:pointer;font-size:12px">複製</button>' +
    '</div>' +
    '<div id="_fb_nav" style="display:none;margin-top:6px;padding:8px;background:#fff7ed;border:1px solid #fdba74;border-radius:8px;font-size:11px;color:#9a3412"></div>' +
    '<details style="margin-top:6px;font-size:11px;color:#555">' +
      '<summary style="cursor:pointer;color:#1877f2;user-select:none">📖 操作說明</summary>' +
      '<div style="padding:6px 4px;line-height:1.6">' +
        '<b>⚠️ 主時間軸 + 影片要分兩次抓</b><br>' +
        '（FB SPA 換頁會清 localStorage）<br><br>' +
        '<b>1.</b> 在 <code>facebook.com/&lt;作者&gt;/</code> 點此書籤<br>' +
        '<b>2.</b> 等「滾完了」橘色提示 → 點 <b>複製</b><br>' +
        '<b>3.</b> 跑 <code>save_clipboard.ps1</code> 存到 <code>facebook_&lt;author&gt;.json</code><br>' +
        '<b>4.</b> 網址改 <code>/&lt;作者&gt;/videos</code> → 重點此書籤<br>' +
        '<b>5.</b> 一樣等→複製→ <code>save_videos.ps1</code> 存到 <code>_videos.json</code><br>' +
        '<b>6.</b> 跑 <code>merge_fb.ps1</code> 合併兩個檔（dedup）<br><br>' +
        '<b>特性</b>：自主滾動（不需 PowerShell 外掛）；偵測 home/posts/photos/videos 頁面類型；try/catch 包整段，有錯會 alert' +
      '</div>' +
    '</details>' +
    '<div id="_fb_l" style="margin-top:7px;font-size:11px;color:#999;word-break:break-all;min-height:16px"></div>';
  document.body.appendChild(panel);

  var stEl    = document.getElementById('_fb_st');
  var nEl     = document.getElementById('_fb_n');
  var rangeEl = document.getElementById('_fb_range');
  var navEl   = document.getElementById('_fb_nav');
  var lEl     = document.getElementById('_fb_l');

  function ui() {
    var keys = Object.keys(posts);
    var dates = keys.map(function(k){ return posts[k].date; }).filter(Boolean).sort();
    nEl.textContent = keys.length;
    if (dates.length > 0) {
      rangeEl.textContent = dates[0] + ' → ' + dates[dates.length-1];
    } else {
      rangeEl.textContent = '-';
    }
  }

  // ── 展開「查看更多」 ────────────────────────────────────────────────────────
  function expandSeeMore() {
    document.querySelectorAll('div[role="button"]').forEach(function(b) {
      var t = (b.innerText || '').trim();
      if (t === '查看更多' || t === 'See more' || t === 'See More') {
        try { b.click(); } catch(e) {}
      }
    });
  }

  // ── 作者偵測 ───────────────────────────────────────────────────────────────
  function getArticleAuthor(el) {
    var SKIP_NAMES = {photo:1,photos:1,videos:1,reel:1,reels:1,stories:1,sharer:1,
                      help:1,privacy:1,'permalink.php':1,'profile.php':1,login:1,
                      'home.php':1,me:1,permalink:1,pages:1,media:1};
    var permLinks = el.querySelectorAll('a[href*="/posts/"], a[href*="/permalink"], a[href*="/share/p/"], a[href*="/videos/"], a[href*="story_fbid"]');
    for (var i = 0; i < permLinks.length; i++) {
      var href = permLinks[i].getAttribute('href') || '';
      var m1 = href.match(/(?:^|\/)([\w.]+)\/(?:posts|videos|share)\//);
      if (m1 && !SKIP_NAMES[m1[1].toLowerCase()]) return m1[1];
      var m2 = href.match(/permalink\.php\?[^#]*[?&]id=(\d+)/);
      if (m2) return m2[1];
    }
    var headerLinks = el.querySelectorAll('h1 a[href], h2 a[href], h3 a[href], strong a[href], a[role="link"]');
    for (var i = 0; i < Math.min(headerLinks.length, 5); i++) {
      var h = headerLinks[i].getAttribute('href') || '';
      var m3 = h.match(/^\/([\w.]+)(?:\/|$|\?)/);
      if (m3 && !SKIP_NAMES[m3[1].toLowerCase()]) return m3[1];
      var m4 = h.match(/profile\.php\?[^#]*[?&]id=(\d+)/);
      if (m4) return m4[1];
    }
    return null;
  }

  // ── V4.0 harvest（主頁/貼文/相片/影片通用：找 message preview）──────────────
  // ── V5.3 videos harvester ───────────────────────────────────────────────────
  // /videos 頁面：每個影片卡有 <a href=".../reel/..."> + 旁邊有描述 + 日期
  function harvestVideos() {
    var added = 0, scanned = 0;
    var links = document.querySelectorAll('a[href*="/reel/"], a[href*="/videos/"]');
    var seenContainers = new Set();
    links.forEach(function(link) {
      var href = link.getAttribute('href') || '';
      var urlMatch = href.match(/\/(reel|videos)\/(\d+)/);
      if (!urlMatch) return;
      var url = (link.href || '').split('?')[0];

      // 往上找 8 層 parent，當作此影片的 card 容器
      var container = link;
      for (var i = 0; i < 8 && container.parentElement; i++) container = container.parentElement;

      if (seenContainers.has(container)) return;
      seenContainers.add(container);
      scanned++;

      // 找文字描述：通常是 span[dir="auto"] 或 div[dir="auto"]，且至少 30 字
      var textCandidates = container.querySelectorAll('span[dir="auto"], div[dir="auto"]');
      var bestText = '';
      for (var t = 0; t < textCandidates.length; t++) {
        var tx = (textCandidates[t].innerText || '').trim();
        if (tx.length >= 30 && tx.length > bestText.length) bestText = tx;
      }
      if (!bestText) return;

      // 找日期：「N週前」「N天前」「N小時前」等短文字 span
      var date = '';
      for (var d = 0; d < textCandidates.length; d++) {
        var dtxt = (textCandidates[d].innerText || '').trim();
        if (dtxt.length < 15 && /(週|周|天|小時|月|年|分鐘)前|昨天|剛剛/.test(dtxt)) {
          date = resolveDate(dtxt);
          break;
        }
      }
      if (!date) date = new Date().toISOString().slice(0, 10);

      if (isGarbage(bestText)) return;

      var clean = bestText.substring(0, 2000);
      var key = hash(clean);
      if (!posts[key]) {
        posts[key] = { author: author, date: date, type: 'video', url: url, content: clean, source: 'videos' };
        added++;
      } else if (url && !posts[key].url) {
        posts[key].url = url;
      }
    });

    if (added > 0) savePosts('harvestVideos');
    ui();
    lEl.textContent = '影片掃 ' + scanned + ' 個 +' + added + ' 篇';
    return added;
  }

  function harvest() {
    // V5.3: route by pageType
    if (pageType === 'videos') return harvestVideos();
    var panelEl = document.getElementById('_fb_panel');
    var added = 0, skippedAuthor = 0, skippedTrunc = 0, skippedNoUrl = 0;

    var msgEls = document.querySelectorAll('[data-ad-comet-preview="message"], [data-ad-preview="message"]');

    msgEls.forEach(function(msgEl) {
      if (panelEl && panelEl.contains(msgEl)) return;

      var content = (msgEl.innerText || '').trim();
      if (content.length < 15) return;

      var container = msgEl;
      var permLink = null;
      for (var depth = 0; depth < 10 && container; depth++) {
        permLink = container.querySelector('a[href*="/posts/"], a[href*="/videos/"], a[href*="/share/p/"], a[href*="permalink"], a[href*="story_fbid"]');
        if (permLink) break;
        container = container.parentElement;
      }

      var url = '', postAuthor = null;
      if (permLink) {
        url = permLink.href.split('?')[0];
        var href = permLink.getAttribute('href') || '';
        var m1 = href.match(/(?:^|\/)([\w.]+)\/(?:posts|videos|share)\//);
        if (m1) postAuthor = m1[1];
        var m2 = href.match(/permalink\.php\?[^#]*[?&]id=(\d+)/);
        if (m2) postAuthor = m2[1];
      }
      if (!permLink) { skippedNoUrl++; return; }

      if (postAuthor && postAuthor.toLowerCase() !== author.toLowerCase()) {
        skippedAuthor++;
        return;
      }

      var date = '';
      var linkText = (permLink.innerText || '').trim();
      if (linkText && linkText.length < 30) date = resolveDate(linkText);
      if (!date && container) {
        var dateLinks = container.querySelectorAll('a[href*="/posts/"], a[href*="/permalink"], a[href*="story_fbid"]');
        for (var i = 0; i < dateLinks.length; i++) {
          var dt = (dateLinks[i].innerText || '').trim();
          if (dt && dt.length < 30 && /\d/.test(dt)) {
            date = resolveDate(dt);
            if (date) break;
          }
        }
      }

      if (/(……\s*查看更多|… 查看更多|查看更多)$/.test(content.trim())) {
        skippedTrunc++;
        return;
      }

      var clean = content.split('\n')
        .map(function(l){ return l.trim(); })
        .filter(function(l){ return l.length > 0 && !/^\d+$/.test(l); })
        .join('\n')
        .substring(0, 2000);

      if (clean.length < 15) return;
      if (isGarbage(clean)) return;

      var key = hash(clean);
      if (!posts[key]) {
        posts[key] = { author: author, date: date, type: 'post', url: url, content: clean, source: pageType };
        added++;
      } else if (url && !posts[key].url) {
        posts[key].url = url;
      }
    });

    if (added > 0) savePosts('harvest');
    ui();
    var msg = '掃到 ' + msgEls.length + ' 個 msg  +' + added + ' 篇';
    if (skippedAuthor > 0) msg += '　跳非作者 ' + skippedAuthor;
    if (skippedNoUrl > 0)  msg += '　無連結 ' + skippedNoUrl;
    if (skippedTrunc > 0)  msg += '　待展開 ' + skippedTrunc;
    lEl.textContent = msg;
    return added;
  }

  // ── ★ V5.0 核心：自主滾動 ──────────────────────────────────────────────────
  // FB 對程式化 scroll 事件有 isTrusted 檢查，但 IntersectionObserver 只看
  // 「viewport 位置變化」不檢查事件來源 → 用 scrollTo + scrollIntoView 直接改
  // 文件滾動位置，IO 會觸發。
  var scrollMode = 0; // 輪流用不同策略
  function autoScroll() {
    var docEl = document.documentElement;
    var beforeH = docEl.scrollHeight;
    var beforeY = window.scrollY || window.pageYOffset || 0;

    // 策略 1：直接跳到文件底（最快、最直接）
    window.scrollTo({ top: docEl.scrollHeight, behavior: 'instant' });

    // 策略 2：role=main 容器（FB 有時是 nested scroll）
    var roleMain = document.querySelector('[role="main"]');
    if (roleMain && roleMain.scrollHeight > roleMain.clientHeight) {
      roleMain.scrollTop = roleMain.scrollHeight;
    }

    // 策略 3：scrollIntoView 最後一個 article/msg（觸發 IO）
    try {
      var lastSel;
      if (pageType === 'photos')      lastSel = 'a[href*="/photos/"], a[href*="fbid="]';
      else if (pageType === 'videos') lastSel = 'a[href*="/reel/"], a[href*="/videos/"]';
      else                            lastSel = '[data-ad-comet-preview="message"], [role="article"]';
      var els = document.querySelectorAll(lastSel);
      if (els.length > 0) {
        els[els.length - 1].scrollIntoView({ block: 'end', inline: 'nearest' });
      }
    } catch(e) {}

    // 策略 4：dispatch wheel（萬一 FB 沒做 isTrusted 嚴檢）
    try {
      window.dispatchEvent(new WheelEvent('wheel', {
        deltaY: 1500, bubbles: true, cancelable: true
      }));
    } catch(e) {}

    return { beforeH: beforeH, beforeY: beforeY };
  }

  // ── 主循環 ─────────────────────────────────────────────────────────────────
  var round = 0, noNewRun = 0, noGrowRun = 0;
  var hintShown = false;

  var iv = setInterval(function() {
    var docEl = document.documentElement;

    expandSeeMore();
    var added = harvest();
    var total = Object.keys(posts).length;

    // ★ 真正執行滾動（V4.6 漏掉這行）
    var sInfo = autoScroll();
    var grewH = docEl.scrollHeight > sInfo.beforeH;

    if (added > 0) noNewRun = 0; else noNewRun++;
    if (grewH)    noGrowRun = 0; else noGrowRun++;

    // 顯示狀態
    var phase = '🎯 滾動抓取';
    if (noGrowRun > 10 && noNewRun > 10) phase = '⏸ 沒新貼文';
    stEl.textContent = phase + ' (' + round + ') · ' + total + ' 篇 · 閒置 ' + noNewRun + '/' + noGrowRun;

    // ── 換頁建議：home 抓不到新貼文 30 拍 → 提示去 photos ───
    if (!hintShown && noNewRun >= 30 && noGrowRun >= 15) {
      hintShown = true;
      if (pageType === 'home' || pageType === 'posts') {
        navEl.style.display = 'block';
        navEl.innerHTML =
          '🔍 <b>主頁看不到更多貼文了</b><br>' +
          '繼續抓更早的內容（資料會自動累積）：<br>' +
          '<a href="/' + author + '/photos" style="color:#1877f2;text-decoration:underline">→ 跳到 Photos</a> ｜ ' +
          '<a href="/' + author + '/videos" style="color:#1877f2;text-decoration:underline">→ 跳到 Videos</a>';
      } else if (pageType === 'photos') {
        navEl.style.display = 'block';
        navEl.innerHTML =
          '🔍 <b>Photos 抓完</b><br>' +
          '<a href="/' + author + '/videos" style="color:#1877f2;text-decoration:underline">→ 跳到 Videos</a> 抓更多';
      } else if (pageType === 'videos') {
        navEl.style.display = 'block';
        navEl.innerHTML = '🔍 <b>Videos 抓完，全部 3 個分頁都跑過了</b><br>點上面「複製」匯出全部資料';
      }
    }

    round++;
  }, 1500); // 1.5 秒一輪：給 FB 時間 lazy load

  // ── 停止 ───────────────────────────────────────────────────────────────────
  function stop(auto) {
    clearInterval(iv); window._fbScraper = null;
    if (Object.keys(posts).length > 0) savePosts('stop');
    stEl.textContent = auto ? '✅ 全部完成！' : '⏹ 已停止';
    stEl.style.color = '#16a34a';
    document.getElementById('_fb_s').style.display = 'none';
    var total = Object.keys(posts).length;
    var saveStatus = saveFails > 0 ? ('（⚠️ 失敗 ' + saveFails + ' 次）') : '';
    lEl.textContent = '共擷取 ' + total + ' 篇' + saveStatus;
  }

  // ── 複製 ───────────────────────────────────────────────────────────────────
  function copy() {
    var arr = Object.values(posts).sort(function(a, b) {
      return (b.date || '').localeCompare(a.date || '');
    });
    var json = JSON.stringify(arr, null, 2);
    navigator.clipboard.writeText(json).catch(function() {
      var ta = document.createElement('textarea');
      ta.value = json; document.body.appendChild(ta); ta.select();
      document.execCommand('copy'); document.body.removeChild(ta);
    });
    alert('已複製 ' + arr.length + ' 筆！');
  }

  document.getElementById('_fb_s').onclick = function() { stop(false); };
  document.getElementById('_fb_c').onclick = copy;
  window._fbScraper = { stop: function() { stop(false); } };

  ui();
  harvest();
  autoScroll(); // 第一次就先滾一下
  stEl.textContent = '🎯 啟動，開始自主滾動...';

  } catch (err) {
    var stack = (err && err.stack) ? err.stack : '(no stack)';
    var msg = (err && err.message) ? err.message : String(err);
    alert('🔴 FB 擷取 v5.4 錯誤！\n\n訊息: ' + msg + '\n\n堆疊（前 500 字）:\n' + stack.substring(0, 500));
    console.error('FB v5.4 error:', err);
    throw err;
  }
})();
