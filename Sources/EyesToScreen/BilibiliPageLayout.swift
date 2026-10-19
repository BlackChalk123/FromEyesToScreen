import Foundation

enum BilibiliPageLayout {
    /// Keep the official desktop player and its quality menu. Only presentation
    /// changes; authentication, media selection and playback stay with the site.
    static let script = #"""
    (() => {
      if (!['www.bilibili.com', 'bilibili.com'].includes(location.hostname) || !location.pathname.startsWith('/video/')) return;
      const style = document.createElement('style');
      style.textContent = `
        html.eyes-player-only, html.eyes-player-only body { margin:0!important; padding:0!important; min-width:0!important; overflow:hidden!important; background:#000!important; }
        html.eyes-player-only body * { visibility:hidden!important; }
        html.eyes-player-only #bilibili-player, html.eyes-player-only #bilibili-player * { visibility:visible!important; }
        html.eyes-player-only #bilibili-player { position:fixed!important; inset:0!important; width:100vw!important; height:100vh!important; min-width:0!important; min-height:0!important; margin:0!important; z-index:10000!important; }
        html.eyes-player-only .bpx-player-container { width:100%!important; height:100%!important; }
      `;
      document.documentElement.appendChild(style);
      const update = () => {
        const ready = !!document.querySelector('#bilibili-player .bpx-player-container');
        if (document.documentElement.classList.contains('eyes-player-only') !== ready) {
          document.documentElement.classList.toggle('eyes-player-only', ready);
          window.dispatchEvent(new Event('resize'));
        }
      };
      new MutationObserver(update).observe(document.documentElement, {childList:true, subtree:true});
      update();
    })();
    """#
}
