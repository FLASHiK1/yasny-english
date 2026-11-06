# Оборачивает страницу артефакта в полноценный HTML-документ для приложения.
# Использование: python3 make_assets.py index.html out.html [android|ios]
import sys
src=open(sys.argv[1],encoding="utf-8").read()
platform=sys.argv[3] if len(sys.argv)>3 else "android"
bridge={
"android":'''
  if(!window.AndroidTTS)return;
  var speak=function(u){try{AndroidTTS.speak(u.text,u.rate||1,u.lang||"en-US")}catch(e){}};
  var stop=function(){try{AndroidTTS.stop()}catch(e){}};''',
"ios":'''
  var h=window.webkit&&window.webkit.messageHandlers;if(!h||!h.tts)return;
  var speak=function(u){try{h.tts.postMessage({text:u.text,rate:u.rate||1,lang:u.lang||"en-US"})}catch(e){}};
  var stop=function(){try{h.tts.postMessage({cmd:"stop"})}catch(e){}};
  if(h.store){var _set=Storage.prototype.setItem;Storage.prototype.setItem=function(k,v){_set.call(this,k,v);if(k==="yasny-eng-v1"){try{h.store.postMessage(String(v))}catch(e){}}}}'''
}[platform]
head='''<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<style>:root{color-scheme:light;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0;font:14px system-ui,-apple-system,sans-serif;-webkit-text-size-adjust:100%}img{max-width:100%}[hidden]{display:none!important}</style>
<script>
window.__NATIVE_APP=true;
(function(){'''+bridge+'''
  function U(t){this.text=String(t||"");this.lang="en-US";this.rate=1;this.voice=null}
  var synth={speak:speak,cancel:stop,getVoices:function(){return[]},onvoiceschanged:null,speaking:false};
  try{Object.defineProperty(window,"speechSynthesis",{value:synth,configurable:true,writable:true})}catch(e){window.speechSynthesis=synth}
  try{Object.defineProperty(window,"SpeechSynthesisUtterance",{value:U,configurable:true,writable:true})}catch(e){window.SpeechSynthesisUtterance=U}
})();
</script></head><body>
'''
open(sys.argv[2],"w",encoding="utf-8").write(head+src+"\n</body></html>\n")
