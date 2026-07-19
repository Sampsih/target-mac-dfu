#!/bin/zsh
set -u
setopt PIPE_FAIL

APP_SUPPORT="$HOME/Library/Application Support/Target Mac DFU"
TOOL="$APP_SUPPORT/macvdmtool"
SRC="$APP_SUPPORT/macvdmtool-src"
DEFAULT_DOWNLOADS="$HOME/Downloads/Target Mac DFU"
CATALOG="$APP_SUPPORT/catalog"
LOG="$HOME/Library/Logs/TargetMacDFU.log"
mkdir -p "$APP_SUPPORT" "$DEFAULT_DOWNLOADS" "$CATALOG" "${LOG:h}"

log(){ print -r -- "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG"; }
fail(){ log "ERROR: $*"; print -u2 -r -- "$*"; }
json_escape(){ /usr/bin/sed 's/\\/\\\\/g;s/"/\\"/g;s/	/\\t/g;s/\r//g;s/$/\\n/' | /usr/bin/tr -d '\n' | /usr/bin/sed 's/\\n$//'; }

find_cfg(){
  local p
  for p in /usr/local/bin/cfgutil /opt/homebrew/bin/cfgutil \
    '/Applications/Apple Configurator.app/Contents/MacOS/cfgutil' \
    '/Applications/Apple Configurator 2.app/Contents/MacOS/cfgutil'; do
    [[ -x "$p" ]] && { print -r -- "$p"; return 0; }
  done
  return 1
}

find_configurator(){
  local p
  for p in '/Applications/Apple Configurator.app' '/Applications/Apple Configurator 2.app'; do
    [[ -d "$p" ]] && { print -r -- "$p"; return 0; }
  done
  return 1
}

capabilities(){
  local cfg='' configurator='' cfg_ok=false configurator_ok=false
  cfg=$(find_cfg 2>/dev/null || true)
  configurator=$(find_configurator 2>/dev/null || true)
  [[ -n "$cfg" ]] && cfg_ok=true
  [[ -n "$configurator" ]] && configurator_ok=true
  cfg=$(print -r -- "$cfg" | json_escape)
  configurator=$(print -r -- "$configurator" | json_escape)
  print -r -- "{\"configuratorInstalled\":$configurator_ok,\"configuratorPath\":\"$configurator\",\"cfgutilInstalled\":$cfg_ok,\"cfgutilPath\":\"$cfg\"}"
}

ensure_tool(){
  [[ -x "$TOOL" ]] && return 0
  if [[ -x /usr/local/bin/macvdmtool ]]; then
    print -r -- 'Найден установленный macvdmtool.'
    /bin/cp /usr/local/bin/macvdmtool "$TOOL" && /bin/chmod 755 "$TOOL"
    return $?
  fi
  [[ "$(/usr/bin/uname -m)" == arm64 ]] || { fail 'Автоматический вход в DFU через macvdmtool требует Host Mac с Apple silicon.'; return 2; }
  /usr/bin/xcode-select -p >/dev/null 2>&1 || { fail 'Требуются Apple Command Line Tools.'; return 2; }
  [[ "$SRC" == "$APP_SUPPORT/macvdmtool-src" ]] || { fail 'Некорректный путь исходников macvdmtool.'; return 2; }
  print -r -- 'macvdmtool не найден — выполняется однократная сборка.'
  /bin/rm -rf "$SRC"
  /usr/bin/git clone --depth 1 https://github.com/AsahiLinux/macvdmtool.git "$SRC" >>"$LOG" 2>&1 || return 3
  /usr/bin/make -C "$SRC" >>"$LOG" 2>&1 || return 4
  /bin/cp "$SRC/macvdmtool" "$TOOL" && /bin/chmod 755 "$TOOL"
}

priv_status(){
  /usr/bin/osascript - "$TOOL" "$1" <<'AS'
on run argv
  set toolPath to item 1 of argv
  set toolCommand to item 2 of argv
  set commandText to quoted form of toolPath & " " & quoted form of toolCommand & "; rc=$?; echo __TARGET_MAC_DFU_RC__${rc}; exit 0"
  return do shell script commandText with administrator privileges
end run
AS
}

parse_cfgutil(){
  /usr/bin/awk '
    BEGIN { type=""; ecid="" }
    {
      line=$0
      if (type=="" && match(line, /(Mac|MacBookPro|MacBookAir|Macmini|iMac|iMacPro|MacPro)[0-9]+,[0-9]+/)) type=substr(line, RSTART, RLENGTH)
      if (ecid=="" && match(line, /ECID:[[:space:]]*(0x)?[0-9A-Fa-f]+/)) {
        value=substr(line, RSTART, RLENGTH); sub(/^ECID:[[:space:]]*/, "", value); ecid=value
      }
      if (type!="" && ecid!="") { print type "\t" ecid; exit }
    }
  '
}

parse_cfgutil_json_file(){
  /usr/bin/osascript -l JavaScript - "$1" <<'JS'
ObjC.import('Foundation');
function text(v){ return v === null || v === undefined ? '' : String(v); }
function value(o,names){ for (const n of names) if (o && o[n] !== undefined) return text(o[n]); return ''; }
function walk(v){
  if (!v || typeof v !== 'object') return null;
  if (!Array.isArray(v)) {
    const type=value(v,['deviceType','DeviceType','device_type','ProductType','productType']);
    const ecid=value(v,['ECID','ecid','EcID']);
    if (/^(Mac|MacBookPro|MacBookAir|Macmini|iMac|iMacPro|MacPro)[0-9]+,[0-9]+$/.test(type) && ecid) return [type,ecid];
  }
  for (const k in v) { const found=walk(v[k]); if (found) return found; }
  return null;
}
function run(a){
  const data=$.NSData.dataWithContentsOfFile(a[0]); if (!data) return '';
  const source=ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data,$.NSUTF8StringEncoding));
  let root; try { root=JSON.parse(source); } catch(e) { return ''; }
  const found=walk(root); return found ? found[0]+'\t'+found[1] : '';
}
JS
}

dfu_presence(){
  if [[ "${TARGET_MAC_DFU_FAKE:-0}" == 1 ]]; then
    print -r -- '{"detected":true,"via":"demo"}'
    return 0
  fi
  local cfg out usb
  cfg=$(find_cfg 2>/dev/null || true)
  if [[ -n "$cfg" ]]; then
    out=$("$cfg" list 2>&1 || true)
    if [[ -n "$(print -r -- "$out" | parse_cfgutil)" ]]; then
      print -r -- '{"detected":true,"via":"cfgutil"}'
      return 0
    fi
  fi
  usb=$(/usr/sbin/system_profiler SPUSBDataType 2>/dev/null || true)
  if print -r -- "$usb" | /usr/bin/grep -Eiq 'Mac DFU Mode|Apple Mobile Device.*DFU|DFU Mode'; then
    print -r -- '{"detected":true,"via":"usb"}'
  else
    print -r -- '{"detected":false,"via":"none"}'
  fi
}

detect(){
  if [[ "${TARGET_MAC_DFU_FAKE:-0}" == 1 ]]; then
    print -r -- '{"type":"Mac14,7","ecid":"0xDEMO123456","mode":"DFU"}'
    return 0
  fi
  local cfg out row type ecid tmp
  cfg=$(find_cfg) || { fail 'cfgutil не найден. Установите Apple Configurator и Automation Tools.'; return 5; }
  out=$("$cfg" list 2>&1 || true)
  log "cfgutil list output:\n$out"
  row=$(print -r -- "$out" | parse_cfgutil)
  if [[ -z "$row" ]]; then
    tmp=$(/usr/bin/mktemp "$APP_SUPPORT/cfgutil.XXXXXX.json") || return 6
    "$cfg" --foreach get deviceType ECID --format JSON >"$tmp" 2>>"$LOG" || true
    row=$(parse_cfgutil_json_file "$tmp" 2>/dev/null || true)
    /bin/rm -f "$tmp"
  fi
  [[ -n "$row" ]] || return 6
  type=${row%%$'\t'*}
  ecid=${row#*$'\t'}
  type=$(print -r -- "$type" | json_escape)
  ecid=$(print -r -- "$ecid" | json_escape)
  print -r -- "{\"type\":\"$type\",\"ecid\":\"$ecid\",\"mode\":\"DFU\"}"
}

wait_for_dfu(){
  local timeout=${1:-60} elapsed=0 result
  while (( elapsed < timeout )); do
    if result=$(detect 2>/dev/null); then print -r -- "$result"; return 0; fi
    /bin/sleep 2
    (( elapsed += 2 ))
  done
  fail "Mac не появился в DFU в течение ${timeout} секунд. Проверьте USB-C кабель, DFU-порт и Apple Configurator Automation Tools."
  return 8
}

enter_dfu(){
  if [[ "${TARGET_MAC_DFU_FAKE:-0}" == 1 ]]; then /bin/sleep 1; return 0; fi
  [[ "$(/usr/bin/uname -m)" == arm64 ]] || { fail 'Кнопка автоматического DFU работает только на Host Mac с Apple silicon.'; return 2; }
  ensure_tool || return $?
  local output rc
  print -r -- 'Отправляю аппаратную команду DFU…'
  output=$(priv_status dfu 2>&1) || { fail "$output"; return 9; }
  log "macvdmtool dfu output:\n$output"
  rc=$(print -r -- "$output" | /usr/bin/sed -n 's/.*__TARGET_MAC_DFU_RC__\([0-9][0-9]*\).*/\1/p' | /usr/bin/tail -1)
  [[ -n "$rc" ]] || rc=1
  (( rc != 0 && rc != 255 )) && log "macvdmtool returned $rc; verifying actual DFU state"
  wait_for_dfu 60 >/dev/null
  print -r -- 'DFU обнаружен.'
}

normalize_catalog(){
  local file="$1" type="$2" include_beta="${3:-0}"
  /usr/bin/osascript -l JavaScript - "$file" "$type" "$include_beta" <<'JS'
ObjC.import('Foundation');
function str(v){ return v === null || v === undefined ? '' : String(v); }
function arr(v){ return Array.isArray(v) ? v : []; }
function run(a){
  const data=$.NSData.dataWithContentsOfFile(a[0]);
  if (!data) throw new Error('Не удалось прочитать ответ API.');
  const text=ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data,$.NSUTF8StringEncoding));
  let root; try { root=JSON.parse(text); } catch(e) { throw new Error('API вернул некорректный JSON: '+e.message); }
  let device=root;
  if (Array.isArray(root)) device=root.find(x=>x && (x.identifier===a[1] || x.type===a[1])) || root[0] || {};
  if (root && root.device) device=root.device;
  if (root && Array.isArray(root.devices)) device=root.devices.find(x=>x && (x.identifier===a[1] || x.type===a[1])) || root.devices[0] || {};
  if (root && root.devices && !Array.isArray(root.devices) && root.devices[a[1]]) device=root.devices[a[1]];
  if (root && Array.isArray(root.catalog)) device=root.catalog.find(x=>x && (x.identifier===a[1] || x.type===a[1])) || {};
  let list=arr(device.firmwares);
  if (!list.length && root && Array.isArray(root.firmwares)) list=root.firmwares;
  const includeBeta=a[2] === '1';
  const normalized=list.map(x=>{
    const version=str(x.version || x.osVersion);
    const build=str(x.buildid || x.build || x.buildId);
    const url=str(x.url || x.downloadUrl);
    const filename=str(x.filename || (url.split('/').pop() || '').split('?')[0]);
    const marker=(version+' '+build+' '+filename).toLowerCase();
    const explicitBeta=(x.beta === true || x.beta === 1 || x.beta === 'true' || x.prerelease === true);
    const inferredBeta=/beta|seed|release[ _-]?candidate/.test(marker) || /[0-9]{3,}[a-z]$/i.test(build);
    return {
      version:version, build:build,
      date:str(x.releasedate || x.releaseDate || x.uploadDate || x.date).slice(0,10),
      size:Number(x.filesize || x.fileSize || x.size || 0), url:url,
      sha1:str(x.sha1sum || x.sha1 || x.hash), filename:filename,
      signed:(x.signed === true || x.signed === 1 || x.signed === 'true'),
      beta:(explicitBeta || inferredBeta)
    };
  }).filter(x=>x.signed && x.url && x.version && x.build && x.filename && (includeBeta || !x.beta))
     .sort((x,y)=>String(y.date).localeCompare(String(x.date)) || String(y.build).localeCompare(String(x.build)));
  return JSON.stringify({name:str(device.name || device.productName || device.identifier || a[1]), identifier:str(device.identifier || device.type || a[1]), firmwares:normalized});
}
JS
}

normalize_ipswbeta_catalog(){
  local file="$1" type="$2"
  /usr/bin/osascript -l JavaScript - "$file" "$type" <<'JS'
ObjC.import('Foundation');
function str(v){ return v === null || v === undefined ? '' : String(v); }
function run(a){
  const data=$.NSData.dataWithContentsOfFile(a[0]);
  if (!data) throw new Error('Не удалось прочитать ответ IPSWBeta.dev.');
  const text=ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data,$.NSUTF8StringEncoding));
  let root; try { root=JSON.parse(text); } catch(e) { throw new Error('IPSWBeta.dev вернул некорректный JSON.'); }
  if (!root || typeof root !== 'object') return JSON.stringify({name:a[1], identifier:a[1], firmwares:[]});
  const list=Array.isArray(root.firmwares) ? root.firmwares : [];
  const normalized=list.map(x=>{
    const version=str(x.version);
    const build=str(x.buildid || x.build);
    const url=str(x.url);
    let date=str(x.releasedate || x.date);
    const months={January:'01',February:'02',March:'03',April:'04',May:'05',June:'06',July:'07',August:'08',September:'09',October:'10',November:'11',December:'12'};
    const match=date.match(/^([A-Za-z]+)\s+(\d{1,2}),\s+(\d{4})$/);
    if (match && months[match[1]]) date=match[3]+'-'+months[match[1]]+'-'+String(match[2]).padStart(2,'0'); else date=date.slice(0,10);
    const filename=(url.split('/').pop() || '').split('?')[0];
    const officialAppleCDN=/^https:\/\/(updates\.cdn-apple\.com|secure-appldnld\.apple\.com)\//i.test(url);
    return {version:version, build:build, date:date, size:0, url:url, sha1:'', filename:filename, beta:true, officialAppleCDN:officialAppleCDN};
  }).filter(x=>x.officialAppleCDN && x.version && x.build && x.filename)
    .map(x=>{ delete x.officialAppleCDN; return x; })
    .sort((x,y)=>String(y.date).localeCompare(String(x.date)) || String(y.build).localeCompare(String(x.build)));
  return JSON.stringify({name:str(root.name || a[1]), identifier:str(root.identifier || a[1]), firmwares:normalized});
}
JS
}

firmwares(){
  local type="$1" source_kind="${2:-ipswMe}" source_value="${3:-}" include_beta="${4:-0}"
  local safe_type tmp cache source_file catalog_url
  safe_type=$(print -r -- "$type" | /usr/bin/tr -cd 'A-Za-z0-9,._-')
  [[ "$safe_type" =~ '^(Mac|MacBookPro|MacBookAir|Macmini|iMac|iMacPro|MacPro)[0-9]+,[0-9]+$' ]] || { fail "Некорректный идентификатор модели: $safe_type"; return 10; }
  if [[ "${TARGET_MAC_DFU_FAKE:-0}" == 1 ]]; then
    if [[ "$source_kind" == ipswBeta ]]; then
      print -r -- '{"name":"MacBook Pro (Demo)","identifier":"Mac14,7","firmwares":[{"version":"27.0 beta 3","build":"26A5378n","date":"2026-07-13","size":0,"url":"https://updates.cdn-apple.com/demo/UniversalMac_Demo_Beta_Restore.ipsw","sha1":"","filename":"UniversalMac_Demo_Beta_Restore.ipsw","beta":true}]}'
    elif [[ "$include_beta" == 1 ]]; then
      print -r -- '{"name":"MacBook Pro (Demo)","identifier":"Mac14,7","firmwares":[{"version":"27.0 beta 3","build":"26A5378n","date":"2026-07-13","size":1024,"url":"https://example.invalid/UniversalMac_Demo_Beta_Restore.ipsw","sha1":"","filename":"UniversalMac_Demo_Beta_Restore.ipsw","beta":true},{"version":"26.5","build":"25F84","date":"2026-05-20","size":1024,"url":"https://example.invalid/UniversalMac_Demo_Restore.ipsw","sha1":"","filename":"UniversalMac_Demo_Restore.ipsw","beta":false}]}'
    else
      print -r -- '{"name":"MacBook Pro (Demo)","identifier":"Mac14,7","firmwares":[{"version":"26.5","build":"25F84","date":"2026-05-20","size":1024,"url":"https://example.invalid/UniversalMac_Demo_Restore.ipsw","sha1":"","filename":"UniversalMac_Demo_Restore.ipsw","beta":false}]}'
    fi
    return 0
  fi
  case "$source_kind" in
    ipswMe)
      catalog_url="https://api.ipsw.me/v4/device/${safe_type}?type=ipsw"
      cache="$CATALOG/ipswme-$safe_type.json"
      ;;
    ipswBeta)
      local beta_index beta_major
      beta_index=$(/usr/bin/curl -fsSL --proto '=https' --tlsv1.2 --retry 2 --connect-timeout 15 --max-time 30 \
        -A 'Target-Mac-DFU/4.2' 'https://ipswbeta.dev/macos/' 2>/dev/null || true)
      beta_major=$(print -r -- "$beta_index" | /usr/bin/sed -n 's#.*href="/macos/\([0-9][0-9]*\)\.x/".*#\1#p' | /usr/bin/sort -nr | /usr/bin/head -1)
      [[ -n "$beta_major" ]] || beta_major=27
      catalog_url="https://ipswbeta.dev/api/device.php?platform=macos&version=${beta_major}&id=${safe_type}"
      cache="$CATALOG/ipswbeta-$safe_type.json"
      ;;
    customURL)
      [[ "$source_value" == https://* ]] || { fail 'Собственный каталог должен использовать HTTPS.'; return 24; }
      catalog_url="$source_value"
      local source_hash
      source_hash=$(print -rn -- "$source_value" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print substr($1,1,12)}')
      cache="$CATALOG/custom-$source_hash-$safe_type.json"
      ;;
    localCatalog|bundled)
      [[ -f "$source_value" ]] || { fail "JSON-каталог не найден: $source_value"; return 25; }
      source_file="$source_value"
      ;;
    *) fail "Неизвестный источник IPSW: $source_kind"; return 26 ;;
  esac
  if [[ -n "${catalog_url:-}" ]]; then
    tmp=$(/usr/bin/mktemp "$APP_SUPPORT/firmwares.XXXXXX.json") || return 11
    log "Requesting $source_kind IPSW catalog for $safe_type"
    if /usr/bin/curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 15 --max-time 60 \
        "$catalog_url" -o "$tmp"; then
      /bin/cp "$tmp" "$cache"
      source_file="$tmp"
    elif [[ -s "$cache" ]]; then
      log "Network catalog unavailable; using cached $source_kind catalog for $safe_type"
      source_file="$cache"
    else
      /bin/rm -f "$tmp"
      fail 'Не удалось получить список IPSW и локальный кэш отсутствует.'
      return 7
    fi
  fi
  local result rc
  if [[ "$source_kind" == ipswBeta ]]; then
    result=$(normalize_ipswbeta_catalog "$source_file" "$safe_type")
  else
    result=$(normalize_catalog "$source_file" "$safe_type" "$include_beta")
  fi
  rc=$?
  [[ -n "${tmp:-}" ]] && /bin/rm -f "$tmp"
  (( rc == 0 )) || { fail 'Не удалось обработать каталог IPSW.'; return $rc; }
  print -r -- "$result"
}

download_legacy(){
  local url="$1" filename="$2" directory="${3:-$DEFAULT_DOWNLOADS}" dest
  filename="${filename:t}"
  [[ -n "$filename" ]] || { fail 'API не вернул имя IPSW-файла.'; return 12; }
  mkdir -p "$directory" || return 12
  dest="$directory/$filename"
  /usr/bin/curl -L --fail --retry 3 -C - --progress-bar -o "$dest.part" "$url" && /bin/mv "$dest.part" "$dest" || return 13
  print -r -- "$dest"
}

recover(){
  local operation="$1" ecid="$2" ipsw="$3" cfg current current_ecid
  [[ "$operation" == restore ]] || { fail "В этой версии доступен только Restore."; return 15; }
  [[ -f "$ipsw" ]] || { fail "IPSW-файл не найден: $ipsw"; return 14; }
  if [[ "${TARGET_MAC_DFU_FAKE:-0}" == 1 ]]; then
    local percent
    for percent in 5 12 20 35 48 61 74 86 95 100; do print -r -- "${operation}: ${percent}%"; /bin/sleep 0.12; done
    return 0
  fi
  cfg=$(find_cfg) || { fail 'cfgutil не найден.'; return 5; }
  current=$(detect) || { fail 'Устройство исчезло перед началом операции.'; return 16; }
  current_ecid=$(print -r -- "$current" | /usr/bin/sed -n 's/.*"ecid":"\([^"]*\)".*/\1/p')
  [[ "$current_ecid" == "$ecid" ]] || { fail 'ECID подключённого устройства изменился. Операция заблокирована.'; return 17; }
  if ! "$cfg" help "$operation" >/dev/null 2>&1; then
    fail "Установленная версия cfgutil не публикует команду '$operation'. Используйте соответствующее действие в Apple Configurator; автоматический запуск заблокирован."
    return 18
  fi
  log "Starting cfgutil $operation for masked ECID ****${ecid[-6,-1]}"
  "$cfg" -e "$ecid" --progress "$operation" -I "$ipsw"
}

support_bundle(){
  local destination="$1" temp history launcher_log
  [[ "$destination" == *.zip ]] || destination="${destination}.zip"
  temp=$(/usr/bin/mktemp -d "$APP_SUPPORT/support.XXXXXX") || return 19
  history="$APP_SUPPORT/history.json"
  launcher_log="$APP_SUPPORT/launcher.log"
  {
    print -r -- "Target Mac DFU support bundle"
    print -r -- "Generated: $(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
    /usr/bin/sw_vers
    print -r -- "Architecture: $(/usr/bin/arch)"
    print -r -- "cfgutil: $(find_cfg 2>/dev/null || print 'not installed')"
  } >"$temp/system.txt"
  for pair in "$LOG:backend.log" "$launcher_log:launcher.log" "$history:history.json"; do
    local source=${pair%%:*} target=${pair#*:}
    [[ -f "$source" ]] || continue
    /usr/bin/sed -E "s/(ECID[\"' :]*)(0x)?[0-9A-Fa-f]+/\1<masked>/g; s|$HOME|<home>|g" "$source" >"$temp/$target"
  done
  /bin/rm -f "$destination"
  /usr/bin/ditto -c -k --sequesterRsrc "$temp" "$destination" || { /bin/rm -rf "$temp"; return 20; }
  /bin/rm -rf "$temp"
  print -r -- "$destination"
}

self_test(){
  local escaped
  escaped=$(print -r -- 'a"b\c' | json_escape)
  [[ "$escaped" == 'a\"b\\c' ]] || { fail 'json_escape self-test failed'; return 21; }
  TARGET_MAC_DFU_FAKE=1 detect >/dev/null || return 22
  TARGET_MAC_DFU_FAKE=1 firmwares 'Mac14,7' >/dev/null || return 23
  print -r -- '{"ok":true,"tests":3}'
}

case "${1:-}" in
  capabilities) capabilities ;;
  dfu-presence) dfu_presence ;;
  ensure-tool) ensure_tool ;;
  nop)
    if [[ "${TARGET_MAC_DFU_FAKE:-0}" == 1 ]]; then exit 0; fi
    ensure_tool || exit $?
    result=$(priv_status nop 2>&1) || { fail "$result"; exit 9; }
    rc=$(print -r -- "$result" | /usr/bin/sed -n 's/.*__TARGET_MAC_DFU_RC__\([0-9][0-9]*\).*/\1/p' | /usr/bin/tail -1)
    [[ "${rc:-1}" == 0 ]] || { fail "macvdmtool nop завершился с кодом ${rc:-1}."; exit "${rc:-1}"; }
    ;;
  dfu) enter_dfu ;;
  detect) detect ;;
  wait-dfu) wait_for_dfu "${2:-60}" ;;
  firmwares) firmwares "$2" "${3:-ipswMe}" "${4:-}" "${5:-0}" ;;
  download) download_legacy "$2" "$3" "${4:-$DEFAULT_DOWNLOADS}" ;;
  recover) recover "$2" "$3" "$4" ;;
  restore) recover restore "$2" "$3" ;;
  support-bundle) support_bundle "$2" ;;
  self-test) self_test ;;
  *) fail 'unknown command'; exit 64 ;;
esac
