# Собирает версию для Telegram Mini App (GitHub Pages).
# Использование: python3 tg/make_tg.py index.html site/index.html
import sys
src=open(sys.argv[1],encoding="utf-8").read()
head='''<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Ясный английский</title>
<script src="https://telegram.org/js/telegram-web-app.js"></script>
<style>:root{color-scheme:light dark}body{margin:0;font:14px system-ui,-apple-system,sans-serif;-webkit-text-size-adjust:100%}img{max-width:100%}[hidden]{display:none!important}</style>
<script>
(function(){
  var tg=window.Telegram&&window.Telegram.WebApp;
  window.__TG=!!(tg&&tg.initData);
  // ИИ через ключ Gemini, как в приложении на телефоне
  window.__NATIVE_APP=true;window.__PACKS_URL="packs/";
  // в браузере событие окончания речи приходит — помечаем озвучку как надёжную
  window.__ttsDone=function(){};
  if(tg){try{tg.ready();tg.expand();if(tg.disableVerticalSwipes)tg.disableVerticalSwipes()}catch(e){}}
})();
</script></head><body>
'''
tail=r'''
<script>
(function(){
  var tg=window.Telegram&&window.Telegram.WebApp;
  /* ---------- Тема и кнопка «Назад» ---------- */
  if(tg){
    try{
      var dark=tg.colorScheme==="dark";document.documentElement.dataset.theme=dark?"dark":"light";
      var bg=getComputedStyle(document.documentElement).getPropertyValue("--bg").trim()||(dark?"#0F1424":"#F1F3F7");
      if(tg.setHeaderColor)tg.setHeaderColor(bg);if(tg.setBackgroundColor)tg.setBackgroundColor(bg);
      tg.onEvent&&tg.onEvent("themeChanged",function(){document.documentElement.dataset.theme=tg.colorScheme==="dark"?"dark":"light"});
      var upd=function(){var r=(location.hash||"#today").slice(1);if(r==="today"||r==="hello")tg.BackButton.hide();else tg.BackButton.show()};
      tg.BackButton.onClick(function(){if(history.length>1)history.back();else location.hash="#today"});
      window.addEventListener("hashchange",upd);upd();
    }catch(e){}
  }
  /* ---------- Синхронизация через облако Telegram ---------- */
  var CLOUD=tg&&window.__TG&&tg.CloudStorage&&tg.isVersionAtLeast&&tg.isVersionAtLeast("6.9")?tg.CloudStorage:null;
  if(!CLOUD)return;
  var CH=3800,lastSent={},timer=null,busy=false,again=false;
  var _label=syncLabel;
  syncLabel=function(){if(SYNC.state==="synced")return"Прогресс сохраняется в облаке Telegram и одинаков на всех твоих устройствах";if(SYNC.state==="loading")return"Загружаю прогресс из Telegram…";if(SYNC.state==="offline"||SYNC.state==="error")return"Нет связи с Telegram — прогресс пока сохраняется на устройстве";return _label()};
  function p(fn){return new Promise(function(res,rej){fn(function(err,val){err?rej(err):res(val)})})}
  function getItem(k){return p(function(cb){CLOUD.getItem(k,cb)})}
  function getItems(ks){return p(function(cb){CLOUD.getItems(ks,cb)})}
  function setItem(k,v){return p(function(cb){CLOUD.setItem(k,v,cb)})}
  function removeItems(ks){return ks.length?p(function(cb){CLOUD.removeItems(ks,cb)}):Promise.resolve()}
  async function pull(){
    var meta=await getItem("st_meta");if(!meta)return null;var m=JSON.parse(meta);
    var keys=[];for(var i=0;i<m.n;i++)keys.push("st_"+i);
    var parts=[];for(var j=0;j<keys.length;j+=50){var got=await getItems(keys.slice(j,j+50));for(var k=j;k<Math.min(j+50,keys.length);k++)parts.push(got[keys[k]]||"")}
    var txt=parts.join("");if(txt.length!==m.len)return null;
    keys.forEach(function(k,i){lastSent[k]=parts[i]});lastSent.n=m.n;
    return JSON.parse(txt);
  }
  async function push(){
    if(busy){again=true;return}busy=true;
    try{
      var txt=JSON.stringify(S),n=Math.ceil(txt.length/CH),jobs=[];
      if(n>1000)throw new Error("too big");
      for(var i=0;i<n;i++){var k="st_"+i,v=txt.slice(i*CH,(i+1)*CH);if(lastSent[k]!==v){jobs.push([k,v])}}
      for(var j=0;j<jobs.length;j+=8){await Promise.all(jobs.slice(j,j+8).map(function(x){return setItem(x[0],x[1]).then(function(){lastSent[x[0]]=x[1]})}))}
      var old=[];for(var q=n;q<(lastSent.n||0);q++){old.push("st_"+q);delete lastSent["st_"+q]}
      await setItem("st_meta",JSON.stringify({n:n,len:txt.length,at:S.updatedAt||Date.now()}));
      await removeItems(old);lastSent.n=n;
      SYNC.state="synced";
    }catch(e){SYNC.state="error"}
    busy=false;syncUI();if(again){again=false;schedule()}
  }
  function schedule(){if(SYNC.state==="loading")return;clearTimeout(timer);timer=setTimeout(push,3000)}
  var _save=save;save=function(){_save.apply(this,arguments);schedule()};
  document.addEventListener("visibilitychange",function(){if(document.hidden&&timer){clearTimeout(timer);push()}});
  SYNC.state="loading";syncUI();
  pull().then(function(remote){
    SYNC.state="synced";
    if(remote){var before=JSON.stringify(S);var fresh=!S.totalAns&&!S.onboarded&&!Object.keys(S.cards||{}).length;
      S=fresh?Object.assign(JSON.parse(JSON.stringify(DEF)),remote):mergeState(S,remote);_save();CS_reset();
      if(S.onboarded&&(location.hash==="#hello"))location.hash="#today";
      else if(JSON.stringify(S)!==before){try{route()}catch(e){}}}
    syncUI();push();
  }).catch(function(){SYNC.state="offline";syncUI()});
  function CS_reset(){try{CS=null;TS=null;LS=null}catch(e){}}
})();
</script>
'''
open(sys.argv[2],"w",encoding="utf-8").write(head+src+tail+"\n</body></html>\n")
