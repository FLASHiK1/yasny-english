# Встраивает наборы из packs/ в index.html, чтобы библиотека работала и без сети (в веб-версии).
import json,os,re,sys
root=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
idx=json.load(open(os.path.join(root,"packs","index.json"),encoding="utf-8"))
data={p["id"]:json.load(open(os.path.join(root,"packs",p["file"]),encoding="utf-8")) for p in idx["packs"]}
blob=json.dumps({"packs":idx["packs"],"data":data},ensure_ascii=False,separators=(",",":")).replace("</","<\\/")
p=os.path.join(root,"index.html");s=open(p,encoding="utf-8").read()
s,n=re.subn(r"/\*PACKS\*/.*?/\*END_PACKS\*/",lambda m:"/*PACKS*/"+blob+"/*END_PACKS*/",s,flags=re.S)
if n!=1: sys.exit("marker not found")
open(p,"w",encoding="utf-8").write(s);print("embedded",len(idx["packs"]),"packs,",len(blob),"bytes")
