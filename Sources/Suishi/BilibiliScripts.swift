import Foundation

enum BilibiliScripts {
    // Browsing stays an official webpage. Capture only ordinary video selection;
    // login, search, redirects, popups and other website interactions remain website-owned.
    static let browser = #"""
    (() => {
      if (window.top !== window || window.__suishiBrowse) return;
      window.__suishiBrowse = true;
      const send = url => {
        try { window.webkit.messageHandlers.suishi.postMessage({kind:'route', url}); return true; }
        catch (_) { return false; }
      };
      const videoURL = value => {
        try {
          const u = new URL(value, location.href), parts = u.pathname.split('/').filter(Boolean);
          return ['www.bilibili.com','bilibili.com','m.bilibili.com'].includes(u.hostname) &&
            parts.length === 2 && parts[0] === 'video' && /^(BV[A-Za-z0-9]{10}|av[0-9]+)$/.test(parts[1]);
        }
        catch (_) { return false; }
      };
      document.addEventListener('click', event => {
        const label = event.target.textContent?.trim() || '';
        if (/^(登录|立即登录)$/.test(label)) window.webkit.messageHandlers.suishi.postMessage({kind:'account', url:location.href});
        const a = event.target.closest?.('a[href]');
        if (!a || event.button !== 0 || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey || !videoURL(a.href)) return;
        if (send(a.href)) { event.preventDefault(); event.stopImmediatePropagation(); }
      }, true);
      document.addEventListener('play', event => { if (event.target instanceof HTMLMediaElement) event.target.pause(); }, true);
      let previous = '';
      setInterval(() => {
        if (location.href !== previous) {
          previous = location.href;
          if (videoURL(previous)) send(previous);
        }
      }, 300);
    })();
    """#

    static let player = #"""
    (() => {
      if (window.top !== window || window.__suishiPlayer) return;
      window.__suishiPlayer = true;
      window.__suishiActive = true;
      const style = document.createElement('style');
      style.id = 'suishi-player-style';
      style.textContent = `
        html.suishi-player, html.suishi-player body { margin:0!important; padding:0!important; min-width:0!important; overflow:hidden!important; background:#000!important; }
        /* Hide page siblings, never override the player's own hidden panels.
           Forcing all descendants visible activates invisible ending/share hit targets. */
        html.suishi-player .suishi-player-path > :not(.suishi-player-path):not(#bilibili-player):not(.bpx-player-container) { display:none!important; }
        /* Keep the player's anchor visible to the site's sticky/mini-player logic.
           A fixed child alone leaves its original page ancestors collapsed/offscreen. */
        html.suishi-player .suishi-player-path { display:block!important; position:static!important; transform:none!important; width:100vw!important; min-width:0!important; max-width:none!important; height:100vh!important; min-height:100vh!important; margin:0!important; padding:0!important; }
        html.suishi-player #bilibili-player { position:fixed!important; inset:0!important; width:100vw!important; height:100vh!important; min-width:0!important; min-height:0!important; margin:0!important; z-index:10000!important; }
        html.suishi-player .bpx-player-container { width:100%!important; height:100%!important; }
        html.suishi-player .bpx-player-primary-area { width:100%!important; height:100%!important; }
        html.suishi-player .bpx-player-sending-area { display:none!important; }
        html.suishi-player .bpx-player-container[data-screen="mini"] { opacity:0!important; pointer-events:none!important; }
      `;
      (document.head || document.documentElement).appendChild(style);
      function update() {
        const root = document.querySelector('#bilibili-player .bpx-player-container') || document.querySelector('.bpx-player-container');
        const video = root?.querySelector('video');
        const enabled = !!root;
        if (root) {
          const host = document.querySelector('#bilibili-player') || root;
          for (let parent = host.parentElement; parent && parent !== document.documentElement; parent = parent.parentElement)
            parent.classList.add('suishi-player-path');
          // Initial discovery only. The existing bounded poll handles later replacement.
          observer.disconnect();
        }
        if (document.documentElement.classList.contains('suishi-player') !== enabled) {
          document.documentElement.classList.toggle('suishi-player', enabled);
          if (enabled) window.scrollTo(0, 0);
          window.dispatchEvent(new Event('resize'));
        }
        // The native viewing canvas owns window placement. Leave the website's
        // automatic sticky mini mode through its real close action, not by
        // falsifying data-screen or forcing hidden controls visible.
        if (root?.dataset.screen === 'mini') root.querySelector('.bpx-player-mini-close')?.click();
        if (!window.__suishiActive) document.querySelectorAll('video,audio').forEach(v => v.pause());
        window.webkit.messageHandlers.suishi.postMessage({
          kind:'state', url:location.href,
          title:(document.querySelector('h1')?.getAttribute('title') || document.querySelector('h1')?.textContent || document.title || '').trim(),
          ready:!!video && root.dataset.screen !== 'mini', time:video && Number.isFinite(video.currentTime) ? video.currentTime : null,
          duration:video && Number.isFinite(video.duration) ? video.duration : 0,
          aspect:video?.videoWidth && video?.videoHeight ? video.videoWidth/video.videoHeight : 16/9,
          paused:!video || video.paused
        });
      }
      document.addEventListener('play', event => {
        if (!window.__suishiActive && event.target instanceof HTMLMediaElement) event.target.pause();
      }, true);
      document.addEventListener('click', event => {
        const label = event.target.textContent?.trim() || '';
        if (/^(登录|立即登录|登录观看)$/.test(label)) {
          event.preventDefault(); event.stopImmediatePropagation();
          window.webkit.messageHandlers.suishi.postMessage({kind:'login', url:location.href});
        }
      }, true);
      const observer = new MutationObserver(() => {
        if (document.querySelector('.bpx-player-container')) update();
      });
      observer.observe(document.documentElement, {childList:true,subtree:true});
      setInterval(update, 1000);
      update();
    })();
    """#
}
