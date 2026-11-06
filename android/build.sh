#!/bin/bash
# Сборка APK без Gradle: aapt2 + javac + d8 + apksigner.
# SDK=путь к папке с plat/android-35 и bt/android-15
set -e
cd "$(dirname "$0")"
# Либо SDK=папка с plat/android-35 и bt/android-15, либо JAR и BT напрямую (как в GitHub Actions)
JAR="${JAR:-$SDK/plat/android-35/android.jar}"; BT="${BT:-$SDK/bt/android-15}"
[ -f "$JAR" ] || { echo "Не найден android.jar: $JAR"; exit 1; }
rm -rf build && mkdir -p build/gen build/obj build/dex assets
python3 make_assets.py ../index.html assets/index.html android
"$BT/aapt2" compile --dir res -o build/res.zip
"$BT/aapt2" link -o build/app.unsigned.apk -I "$JAR" --manifest AndroidManifest.xml -A assets \
  --java build/gen build/res.zip --min-sdk-version 24 --target-sdk-version 34 \
  --version-code ${VERSION_CODE:-1} --version-name ${VERSION_NAME:-1.0}
javac -nowarn -Xlint:-options -source 8 -target 8 -encoding UTF-8 -bootclasspath "$JAR" -classpath "$JAR" -d build/obj \
  $(find src build/gen -name '*.java')
"$BT/d8" --release --min-api 24 --lib "$JAR" --output build/dex $(find build/obj -name '*.class')
(cd build/dex && zip -q -j ../app.unsigned.apk classes.dex)
"$BT/zipalign" -p -f 4 build/app.unsigned.apk build/app.aligned.apk
if [ -n "$KEYSTORE_B64" ]; then echo "$KEYSTORE_B64" | base64 -d > release.keystore; fi
[ -f release.keystore ] || keytool -genkeypair -keystore release.keystore -alias yasny -keyalg RSA -keysize 2048 \
  -validity 10000 -storepass yasnypass -keypass yasnypass -dname "CN=Yasny English" >/dev/null 2>&1
"$BT/apksigner" sign --ks release.keystore --ks-pass pass:${KS_PASS:-yasnypass} --key-pass pass:${KS_PASS:-yasnypass} \
  --out build/yasny-english.apk build/app.aligned.apk
"$BT/apksigner" verify build/yasny-english.apk && echo "APK: $(pwd)/build/yasny-english.apk"
