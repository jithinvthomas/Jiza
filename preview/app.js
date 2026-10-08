'use strict';
const paths = {
  back:'M15 18l-6-6 6-6', forward:'M9 6l6 6-6 6', arrow:'M7 17L17 7M7 7h10v10',
  close:'M6 6l12 12M18 6L6 18', globe:'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0M3 12h18M12 3c5 5 5 13 0 18-5-5-5-13 0-18',
  go:'M5 12h14M13 6l6 6-6 6', reload:'M20 7v5h-5M20 12a8 8 0 1 0-2 6M20 7l-3-3',
  tabs:'M6 6h14v14H6zM3 16V3h13', download:'M12 3v12M7 10l5 5 5-5M4 17v4h16v-4',
  menu:'M5 12h.01M12 12h.01M19 12h.01', shield:'M12 3l8 3v6c0 5-8 9-8 9s-8-4-8-9V6z',
  bookmark:'M6 3h12v18l-6-4-6 4z', copy:'M8 8h12v12H8zM4 16V4h12', share:'M12 16V3M8 7l4-4 4 4M7 11H4v10h16V11h-3',
  private:'M3 3l18 18M10 5h2c7 0 10 7 10 7s-1 3-4 5M7 6c-3 2-5 6-5 6s3 7 10 7h3',
  plus:'M12 4v16M4 12h16', folder:'M3 6h7l2 3h9v11H3z', play:'M8 5l11 7-11 7z', pause:'M8 5v14M16 5v14',
  next:'M5 5l10 7-10 7zM19 5v14', previous:'M19 5L9 12l10 7zM5 5v14', music:'M9 18V5l11-2v13M9 7l11-2M9 18c0 4-7 4-7 1 0-3 7-4 7-1M20 16c0 4-7 4-7 1 0-3 7-4 7-1',
  full:'M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5', shrink:'M9 4v5H4M20 9h-5V4M15 20v-5h5M4 15h5v5',
  lock:'M6 10h12v11H6zM8 10V7a4 4 0 0 1 8 0v3', check:'M5 12l4 4L19 6'
};
const icon = name => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="'+(paths[name]||paths.menu)+'"/></svg>';
const esc = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const button = (action, name, label, extra='') => '<button class="icon-btn '+extra+'" data-action="'+action+'" aria-label="'+label+'" title="'+label+'">'+icon(name)+'</button>';
const brand = '<span class="wordmark" role="img" aria-label="Jiza"></span>';
const screens = ['Home','Music','Video','Browser','Downloads','Trading'];
let saved = {};
try { saved = JSON.parse(sessionStorage.getItem('jiza-preview') || '{}'); } catch {}
let state = {route:screens.includes(saved.route)?saved.route:'Home', dark:!!saved.dark, address:'', page:false, adblock:false, popups:true, tabs:1, bookmarks:[], playingVideo:false};
const app = document.getElementById('app'), overlay = document.getElementById('overlay'), phone = document.getElementById('phone'), audio = document.getElementById('audio');
let toastTimer, hideTimer, longTimer;
function persist(){sessionStorage.setItem('jiza-preview',JSON.stringify({route:state.route,dark:state.dark}));}
function toast(text){const el=document.getElementById('toast');el.textContent=text;el.classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>el.classList.remove('visible'),3500);}
function header(title){return '<header class="topbar">'+(title==='Home'?'<span style="width:44px"></span>':button('home','back','Back to home','glass'))+'<div class="heading">'+(title==='Home'?brand:'')+'</div>'+button(title==='Music'?'music-menu':'locks',title==='Music'?'menu':'shield',title==='Music'?'Music menu':'Privacy and locks','glass')+'</header>';}
function nav(route){state.route=route;state.playingVideo=false;clearTimeout(hideTimer);closeSheet();persist();render();}
function render(){
  phone.classList.toggle('dark',state.dark);document.getElementById('theme').textContent=state.dark?'Switch to light':'Switch to dark';
  document.getElementById('routes').innerHTML=screens.map(s=>'<button data-route="'+s+'" class="'+(state.route===s?'active':'')+'">'+(s==='Downloads'?'Downloader':s)+'</button>').join('');
  if(state.route==='Home') app.innerHTML=header('Home')+'<div class="scroll"><div class="hero"><img src="/assets/symbol.png" alt=""><div><h2>Your space.</h2><p>Listen, watch, explore.</p></div></div><div class="grid">'+[['Music','Songs & playlists','music','Music'],['Video','Films & streams','video','Video'],['Browser','Web & downloads','browser','Browser'],['Downloader','Files & links','browser','Downloads'],['Trading','Your workspace','trading','Trading']].map(([name,detail,img,route])=>'<button class="space-card glass press" data-action="route-'+route+'"><div><img src="/assets/'+img+'.png" alt="">'+icon('arrow')+'</div><strong class="space-title">'+name+'</strong><small>'+detail+'</small></button>').join('')+'</div></div>';
  if(state.route==='Browser') renderBrowser();
  if(state.route==='Music') renderMusic();
  if(state.route==='Video') app.innerHTML=header('Video')+'<div class="scroll"><div class="video-library glass"><img src="/assets/video.png" alt=""><h2>Your cinema, anywhere.</h2><p class="caption">Files, folders and direct streams.</p>'+row('open-video','play','Play sample video')+row('choose-file','folder','Open video')+row('choose-file','folder','Choose video folder')+row('stream','globe','Open network stream')+'</div><h3>Your videos</h3><p class="caption">Use the sample to try full-screen playback and controls that hide after five seconds.</p></div>';
  if(state.route==='Downloads'){app.innerHTML=header('Downloads')+'<div class="scroll">'+torrentContent()+downloadContent()+'</div>';}
  if(state.route==='Trading')app.innerHTML=header('Trading')+'<div class="empty"><img src="/assets/trading.png" alt=""><h2>Your trading workspace</h2><p>Open Jiza Trading securely through Cloudflare Access.</p><a class="primary trading-link" href="https://trade.jiza.app" target="_blank" rel="noopener noreferrer">Open Jiza Trading</a><p class="notice">Protected domain: trade.jiza.app</p><a class="text-button" href="https://github.com/jithinvthomas/Jiza-Trading" target="_blank" rel="noopener noreferrer">Jiza Trading repository</a></div>';
}
function row(action, glyph, title, suffix=''){return '<button class="menu-row" data-action="'+action+'">'+icon(glyph)+'<span>'+title+'</span>'+suffix+'</button>';}
function renderBrowser(){
  app.innerHTML=header('Browser')+'<div class="address glass">'+icon('globe')+'<input id="address" placeholder="Search or enter website" aria-label="Website address" value="'+esc(state.address)+'">'+button('go','go','Open website')+'<span id="clear-slot">'+(state.address?button('clear-address','close','Clear address'):'')+'</span></div><div class="browser-content" id="browser-content">'+(state.page?'<article class="demo-page"><small>JIZA SAMPLE PAGE</small><h2>Try your browser.</h2><p>Long-press or right-click a link to open the Jiza actions menu.</p><a href="#" data-sample-link="Example page">Example page</a><a href="#" data-sample-link="Sample video.mp4">Sample video.mp4</a><p id="refresh-time">Pull down or use the reload button below.</p><p class="notice">This is a design preview. Website access and downloads run in the iPhone app.</p></article>':'<div class="empty"><img src="/assets/browser.png" alt=""><h2>Explore with Jiza</h2><p>Search, open websites, and keep your favourite pages together.</p><button class="text-button" data-action="sample">Open sample page</button></div>')+'</div><div class="browser-dock glass">'+button('browser-back','back','Back')+button('browser-forward','forward','Forward')+button('refresh','reload','Reload page')+button('tabs','tabs','Tabs')+button('downloads','download','Downloads')+button('browser-menu','menu','Browser menu')+'</div>';
  const field=document.getElementById('address');field.addEventListener('input',()=>{state.address=field.value;document.getElementById('clear-slot').innerHTML=field.value?button('clear-address','close','Clear address'):'';});field.addEventListener('keydown',e=>{if(e.key==='Enter')openPage();});
  const surface=document.getElementById('browser-content');let startY;
  surface.addEventListener('pointerdown',e=>{startY=surface.scrollTop===0?e.clientY:undefined;});
  surface.addEventListener('pointerup',e=>{if(startY!==undefined&&e.clientY-startY>80)refresh();startY=undefined;});
}
function openPage(){state.address=document.getElementById('address')?.value||state.address;state.page=true;renderBrowser();toast('Preview page opened. Real websites run in the iPhone app.');}
function refresh(){const label=document.getElementById('refresh-time');if(label)label.textContent='Refreshed at '+new Date().toLocaleTimeString();toast(state.page?'Sample page refreshed':'Open a page first');}
function sheet(title, content){overlay.innerHTML='<div class="sheet-backdrop"><section class="sheet" role="dialog" aria-modal="true" aria-label="'+esc(title)+'"><div class="handle"></div><div class="sheet-heading"><h2>'+title+'</h2>'+button('close-sheet','close','Close panel')+'</div>'+content+'</section></div>';overlay.querySelector('button')?.focus();}
function closeSheet(){overlay.innerHTML='';}
let selectedTorrent = null;
function torrentContent(){
  return '<section class="download-row glass"><h3 style="margin-top:0">Download from torrent</h3><p class="caption">Open a .torrent file from your device.</p><button class="primary" data-action="open-torrent">Open .torrent file</button><input id="torrent-file" type="file" accept=".torrent,application/x-bittorrent" hidden><div id="torrent-selection" aria-live="polite">'+torrentSelection()+'</div></section>';
}
function torrentSelection(){
  // Encode the user-controlled filename before rendering HTML; never upload the file.
  return selectedTorrent?'<p style="overflow-wrap:anywhere"><strong>'+esc(selectedTorrent.name)+'</strong><br><small>'+Math.ceil(selectedTorrent.size/1024)+' KB metadata file selected</small></p><button class="primary" disabled aria-describedby="torrent-status">Start download</button><p id="torrent-status" class="notice">Torrent engine not connected in this preview. No download has started.</p>'+row('remove-torrent','close','Remove file'):'<p class="notice">File selection works here. Torrent transfers are not connected yet.</p>';
}
function chooseTorrent(){document.getElementById('torrent-file').click();}
document.addEventListener('change',e=>{
  if(e.target.id!=='torrent-file')return;
  const file=e.target.files?.[0];
  if(!file)return;
  if(!/\.torrent$/i.test(file.name)||file.size===0||file.size>20*1024*1024){
    e.target.value='';toast('Choose a non-empty .torrent file smaller than 20 MB.');return;
  }
  selectedTorrent={name:file.name,size:file.size};
  document.getElementById('torrent-selection').innerHTML=torrentSelection();
});
function downloadContent(){return '<h3>Add download</h3><input aria-label="Direct file URL" placeholder="Direct file URL" style="width:100%;padding:13px;border:1px solid #8393b550;border-radius:13px;background:var(--glass);color:var(--ink)"><button class="primary" data-action="preview-download" style="margin-top:12px">Download URL</button><p class="notice">Preview only — transfers aren’t connected.</p>'+row('choose-file','folder','Choose download folder')+'<h3>Downloads</h3><div class="download-row glass"><strong>Sample video.mp4</strong><div class="progress"><span></span></div><small>Example of an active download · 42%</small><div style="display:flex;gap:10px;margin-top:10px"><button class="text-button" data-action="pause-demo">Pause</button><button class="text-button" data-action="cancel-demo">Cancel</button></div></div><p class="notice">Torrent importing and parallel-connection downloads are planned engine work. This preview does not imply they are implemented.</p>';}
function renderMusic(){app.innerHTML=header('Music')+'<div class="scroll"><img class="music-art" src="/assets/music.png" alt="Jiza music"><h2 class="song-title">A little room for music.</h2><p class="song-subtitle">Local sample · preview audio</p><div class="transport glass"><input id="audio-seek" type="range" min="0" max="100" value="0" aria-label="Playback position"><div class="time-row"><span id="audio-time">0:00</span><span>Sample</span></div><div class="transport-row">'+button('shuffle','arrow','Shuffle')+button('audio-back','previous','Previous track')+'<button class="play" data-action="audio-play" aria-label="Play or pause sample audio">'+icon(audio.paused?'play':'pause')+'</button>'+button('audio-next','next','Next track')+button('repeat','reload','Repeat')+'</div></div><div class="library-head"><h3>Your library</h3><small>Sample</small></div><div class="track">'+icon('music')+'<div>Jiza sample audio<small>Tap play to hear the local fixture</small></div></div><button class="text-button" data-action="choose-file">Choose music folder</button></div>';document.getElementById('audio-seek').oninput=e=>{if(Number.isFinite(audio.duration))audio.currentTime=Number(e.target.value)/100*audio.duration;};}
function renderVideo(){
  state.playingVideo=true;audio.pause();app.innerHTML='<div class="video-player" id="video-player"><video id="video" src="/assets/sample.mp4" playsinline loop></video><div class="video-chrome">'+button('leave-video','back','Close video')+brand+'<strong>Sample video</strong>'+button('cinema','full','Enter full screen')+'</div><div class="video-controls"><input type="range" id="video-seek" min="0" max="100" value="0" aria-label="Video position"><div class="transport-row">'+button('video-back','previous','Back ten seconds')+button('video-play','play','Play or pause video')+button('video-next','next','Forward ten seconds')+'</div><div class="video-tools"><button data-action="speed">1×</button><button data-action="fit">Fit</button><button data-action="subtitles">Subtitles</button></div></div></div>';
  const video=document.getElementById('video');video.onplay=()=>document.querySelector('[data-action="video-play"]').innerHTML=icon('pause');video.onpause=()=>document.querySelector('[data-action="video-play"]').innerHTML=icon('play');video.ontimeupdate=()=>{document.getElementById('video-seek').value=Number.isFinite(video.duration)?video.currentTime/video.duration*100:0;};document.getElementById('video-seek').oninput=e=>{if(Number.isFinite(video.duration))video.currentTime=Number(e.target.value)/100*video.duration;revealVideo();};video.play().catch(()=>toast('Tap play to start the sample.'));
}
function revealVideo(){const player=document.getElementById('video-player');if(!player)return;player.classList.remove('hidden-controls');clearTimeout(hideTimer);if(player.classList.contains('cinema'))hideTimer=setTimeout(()=>player.classList.add('hidden-controls'),5000);}
const actions={
  home:()=>nav('Home'), sample:()=>{state.address='https://example.com';state.page=true;renderBrowser();}, go:openPage,
  'clear-address':()=>{state.address='';const el=document.getElementById('address');el.value='';document.getElementById('clear-slot').innerHTML='';el.focus();},
  refresh, 'browser-back':()=>{state.page=false;state.address='';renderBrowser();},'browser-forward':()=>{state.page=true;renderBrowser();},
  downloads:()=>sheet('Downloads',torrentContent()+downloadContent()),'close-sheet':closeSheet,
  'open-torrent':chooseTorrent,
  'remove-torrent':()=>{selectedTorrent=null;document.getElementById('torrent-file').value='';document.getElementById('torrent-selection').innerHTML=torrentSelection();},
  'browser-menu':()=>sheet('Browser menu',row('new-tab','plus','New tab')+row('private-tab','private','New private tab')+row('bookmarks','bookmark','Bookmarks')+row('protection','shield','Ad blocker & pop-ups')+row('locks','lock','Privacy & locks')),
  tabs:()=>sheet('Tabs',row('new-tab','plus','New tab')+row('private-tab','private','New private tab')+Array.from({length:state.tabs},(_,i)=>row('close-sheet','globe','Tab '+(i+1))).join('')),
  'new-tab':()=>{state.tabs++;state.address='';state.page=false;closeSheet();nav('Browser');toast('New tab');},
  'private-tab':()=>{state.tabs++;nav('Browser');toast('Private-tab layout preview. Native privacy isolation is tested on iPhone.');},
  bookmarks:()=>sheet('Bookmarks',state.bookmarks.length?state.bookmarks.map(n=>row('open-bookmark','bookmark',esc(n))).join(''):'<p class="caption">Long-press the sample page link and choose Save bookmark.</p>'),
  'open-bookmark':()=>{closeSheet();state.page=true;renderBrowser();},
  protection:()=>sheet('Browser protection',row('toggle-ads','shield','Ad blocker','<span class="toggle '+(state.adblock?'on':'')+'"></span>')+row('toggle-popups','private','Block pop-up windows','<span class="toggle '+(state.popups?'on':'')+'"></span>')+'<p class="notice">These switches demonstrate the settings UI. Actual blocking runs in Jiza’s native browser.</p>'),
  'toggle-ads':()=>{state.adblock=!state.adblock;actions.protection();},'toggle-popups':()=>{state.popups=!state.popups;actions.protection();},
  locks:()=>sheet('Privacy & locks',row('native-only','shield','Face ID / iPhone passcode')+row('native-only','lock','Set browser PIN')+'<p class="notice">Authentication is available only in the native iPhone app. This preview never requests or stores your PIN.</p>'),
  'native-only':()=>toast('Available in the native iPhone app.'),'choose-file':()=>toast('Files picker preview. Open local files in the iPhone app.'),
  'preview-download':()=>toast('Download action preview — no transfer has started.'),'pause-demo':()=>toast('Paused · visual demonstration only'),'cancel-demo':()=>toast('Cancelled · visual demonstration only'),
  'music-menu':()=>sheet('Music',row('choose-file','folder','Choose folder')+row('choose-file','music','Open audio file')+row('theme','shield','Switch appearance')+'<p class="notice">The frequency-spectrum display is planned. This preview uses sample audio.</p>'),
  theme:()=>{state.dark=!state.dark;persist();render();closeSheet();},
  'audio-play':()=>{audio.paused?audio.play().catch(()=>toast('Audio could not start.')):audio.pause();},'audio-back':()=>{audio.currentTime=0;},'audio-next':()=>{audio.currentTime=0;toast('One sample track in this preview');},shuffle:()=>toast('Shuffle control preview'),repeat:()=>toast('Sample audio repeats'),
  'open-video':renderVideo,'leave-video':()=>nav('Video'),
  cinema:()=>{const p=document.getElementById('video-player');p.classList.toggle('cinema');const b=p.querySelector('[data-action="cinema"]');b.innerHTML=icon(p.classList.contains('cinema')?'shrink':'full');b.setAttribute('aria-label',p.classList.contains('cinema')?'Exit full screen':'Enter full screen');revealVideo();},
  'video-play':()=>{const v=document.getElementById('video');v.paused?v.play():v.pause();revealVideo();},
  'video-back':()=>{const v=document.getElementById('video');v.currentTime=Math.max(0,v.currentTime-10);revealVideo();},'video-next':()=>{const v=document.getElementById('video');v.currentTime=Math.min(v.duration||0,v.currentTime+10);revealVideo();},
  speed:()=>{const v=document.getElementById('video');v.playbackRate=v.playbackRate===1?1.5:1;document.querySelector('[data-action="speed"]').textContent=v.playbackRate+'×';revealVideo();},
  fit:()=>{const v=document.getElementById('video');v.style.objectFit=v.style.objectFit==='cover'?'contain':'cover';revealVideo();},subtitles:()=>toast('Subtitle picker is available in the native app.'),stream:()=>sheet('Network stream','<input placeholder="https://…" aria-label="Video URL"><button class="primary" data-action="native-only">Open video link</button>'),
  'link-tab':()=>{state.tabs++;closeSheet();toast('Opened in a new tab · preview');},'link-private':()=>{state.tabs++;closeSheet();toast('Opened in a private tab · preview');},
  'link-download':()=>actions.downloads(),'link-save':()=>{state.bookmarks=['Example page'];closeSheet();toast('Bookmark saved in this preview');},
  'link-copy':()=>{navigator.clipboard?.writeText('https://example.com').then(()=>toast('Sample link copied')).catch(()=>toast('Sample link: https://example.com'));closeSheet();},'link-share':()=>toast('Share sheet is available in the native app.')
};
function linkMenu(){sheet('Link actions',row('link-tab','tabs','Open in new tab')+row('link-private','private','Open in private tab')+row('link-download','download','Download link')+row('link-save','bookmark','Save bookmark')+row('link-copy','copy','Copy link')+row('link-share','share','Share link'));}
document.addEventListener('click',e=>{const target=e.target.closest('[data-action]');if(target){e.preventDefault();const action=target.dataset.action;if(action.startsWith('route-'))nav(action.slice(6));else actions[action]?.();return;}const route=e.target.closest('[data-route]');if(route){nav(route.dataset.route);return;}if(e.target.classList.contains('sheet-backdrop'))closeSheet();if(e.target.closest('[data-sample-link]')){e.preventDefault();toast('Long-press or right-click for link actions.');}if(e.target.closest('#video-player'))revealVideo();});
document.addEventListener('contextmenu',e=>{if(e.target.closest('[data-sample-link]')){e.preventDefault();linkMenu();}});
document.addEventListener('pointerdown',e=>{if(e.target.closest('[data-sample-link]'))longTimer=setTimeout(linkMenu,550);});
for(const event of ['pointerup','pointercancel','pointermove'])document.addEventListener(event,()=>clearTimeout(longTimer));
document.addEventListener('pointermove',e=>{const el=e.target.closest('.glass');if(el){const r=el.getBoundingClientRect();el.style.setProperty('--mx',(e.clientX-r.left)+'px');el.style.setProperty('--my',(e.clientY-r.top)+'px');}});
document.addEventListener('keydown',e=>{if(e.key==='Escape')closeSheet();});
document.getElementById('theme').onclick=actions.theme;
document.getElementById('rotate').onclick=()=>{const el=document.getElementById('device');el.classList.toggle('landscape');document.getElementById('rotate').textContent=el.classList.contains('landscape')?'Portrait':'Landscape';};
audio.ontimeupdate=()=>{const slider=document.getElementById('audio-seek');if(slider&&Number.isFinite(audio.duration)){slider.value=audio.currentTime/audio.duration*100;document.getElementById('audio-time').textContent=Math.floor(audio.currentTime/60)+':'+String(Math.floor(audio.currentTime%60)).padStart(2,'0');}};
audio.onplay=audio.onpause=()=>{const b=document.querySelector('[data-action="audio-play"]');if(b)b.innerHTML=icon(audio.paused?'play':'pause');};
render();
let version;
async function checkVersion(){try{const response=await fetch('/version',{cache:'no-store'});if(!response.ok)throw Error('offline');const next=await response.text();document.getElementById('connection').textContent='connected';if(version&&version!==next){persist();location.reload();}version=next;}catch{document.getElementById('connection').textContent='reconnecting';}}
checkVersion();setInterval(checkVersion,1200);
