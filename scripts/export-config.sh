#!/bin/bash
# NetBird 설정을 JSON으로 내보내 버전관리한다.
# 사용법: NETBIRD_TOKEN=nbp_xxx ./export.sh
set -e

API="${NETBIRD_API:-https://net.biseo.kr/api}"
TOKEN="${NETBIRD_TOKEN:?NETBIRD_TOKEN 환경변수가 필요합니다}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/config"

get() { curl -sS --max-time 20 -H "Authorization: Token $TOKEN" "$API/$1"; }
save() { python3 -m json.tool --sort-keys > "$OUT/$1"; echo "  $1"; }

mkdir -p "$OUT"
echo "NetBird 설정 내보내기 → $OUT"

get groups           | save groups.json
get policies         | save policies.json
get setup-keys       | save setup-keys.json
get peers            | save peers.json
get networks         | save networks.json
get routes           | save routes.json
get dns/nameservers  | save dns-nameservers.json
get accounts         | save accounts.json

# Networks 하위 리소스/라우터는 네트워크별로 조회해야 한다
for nid in $(get networks | python3 -c "import sys,json;[print(n['id']) for n in json.load(sys.stdin)]"); do
  get "networks/$nid/resources" | save "network-${nid}-resources.json"
  get "networks/$nid/routers"   | save "network-${nid}-routers.json"
done

echo "완료: $(ls -1 "$OUT" | wc -l | tr -d ' ')개 파일"
