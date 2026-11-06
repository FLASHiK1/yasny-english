# Оборачивает страницу артефакта в полноценный HTML-документ для приложения.
# Использование: python3 make_assets.py index.html out.html [android|ios] [адрес библиотеки]
import sys, json
src=open(sys.argv[1],encoding="utf-8").read()
platform=sys.argv[3] if len(sys.argv)>3 else "android"
packs=sys.argv[4] if len(sys.argv)>4 else ""
bridge={
"android":'''
  if(!window.AndroidTTS)return;
  var speak=function(u){try{window.__ttsCur=u;if(u.pitch&&u.pitch!==1&&AndroidTTS.speakP)AndroidTTS.speakP(u.text,u.rate||1,u.lang||"en-US",u.pitch);else AndroidTTS.speak(u.text,u.rate||1,u.lang||"en-US")}catch(e){}};
  window.__ttsDone=function(){var u=window.__ttsCur;window.__ttsCur=null;if(u&&u.onend)try{u.onend()}catch(e){}};
  var stop=function(){window.__ttsCur=null;try{AndroidTTS.stop()}catch(e){}};
  var hasMic=false;try{hasMic=!!AndroidTTS.hasSpeech()}catch(e){}
  window.NativeApp={platform:"android",
    speech:hasMic?{start:function(l){AndroidTTS.startListening(l||"en-US")},stop:function(){AndroidTTS.stopListening()}}:null,
    reminder:{set:function(h,m,on){AndroidTTS.setReminder(h|0,m|0,!!on)}}};''',
"ios":'''
  var h=window.webkit&&window.webkit.messageHandlers;if(!h||!h.tts)return;
  var speak=function(u){try{h.tts.postMessage({text:u.text,rate:u.rate||1,lang:u.lang||"en-US",pitch:u.pitch||1})}catch(e){}};
  var stop=function(){try{h.tts.postMessage({cmd:"stop"})}catch(e){}};
  window.NativeApp={platform:"ios",
    speech:h.speech?{start:function(l){h.speech.postMessage({cmd:"start",lang:l||"en-US"})},stop:function(){h.speech.postMessage({cmd:"stop"})}}:null,
    reminder:h.reminder?{set:function(hh,mm,on){h.reminder.postMessage({hour:hh|0,minute:mm|0,on:!!on})}}:null};
  if(h.store){var _set=Storage.prototype.setItem;Storage.prototype.setItem=function(k,v){_set.call(this,k,v);if(k==="yasny-eng-v1"){try{h.store.postMessage(String(v))}catch(e){}}}}'''
}[platform]
head='''<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<style>:root{color-scheme:light;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0;font:14px system-ui,-apple-system,sans-serif;-webkit-text-size-adjust:100%}img{max-width:100%}[hidden]{display:none!important}</style>
<script>
window.__NATIVE_APP=true;window.__PACKS_URL='''+json.dumps(packs)+''';
window.__nativeSpeech=function(ev){var f=window.NativeApp&&window.NativeApp.onSpeech;if(f)f(ev)};
(function(){'''+bridge+'''
  function U(t){this.text=String(t||"");this.lang="en-US";this.rate=1;this.pitch=1;this.voice=null;this.onend=null}
  var synth={speak:speak,cancel:stop,getVoices:function(){return[]},onvoiceschanged:null,speaking:false};
  try{Object.defineProperty(window,"speechSynthesis",{value:synth,configurable:true,writable:true})}catch(e){window.speechSynthesis=synth}
  try{Object.defineProperty(window,"SpeechSynthesisUtterance",{value:U,configurable:true,writable:true})}catch(e){window.SpeechSynthesisUtterance=U}
})();
</script></head><body>
'''
open(sys.argv[2],"w",encoding="utf-8").write(head+src+"\n</body></html>\n")
