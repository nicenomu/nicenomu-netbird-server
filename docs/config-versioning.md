# 계정 설정 버전 관리

NetBird 서버 구축 코드(`docker-compose.yml` 등)와 별개로, **계정 안의 설정**
(그룹·정책·네트워크·peer)은 관리 콘솔에서 만들어지며 `store.db`에만 남는다.
서버를 이전하거나 설정이 어떻게 바뀌어왔는지 추적하려면 별도 관리가 필요하다.

Keycloak realm export와 같은 방식으로, API에서 JSON을 내보내 커밋한다.

## 사용법

```bash
NETBIRD_TOKEN=nbp_xxxxx ./scripts/export-config.sh
git diff config/          # 무엇이 바뀌었는지 확인
git add config/ && git commit -m "chore(netbird): 설정 스냅샷"
```

API 토큰은 대시보드 `Team → Users → (본인) → Access Tokens` 에서 발급한다.
**작업용으로 짧게(1일) 발급하고 쓰고 버리는 것을 권장한다** — 만료된 토큰은
재활성화가 불가능하며(`hashed_token`으로만 저장), 새로 발급해야 한다.

## 내보내는 항목

| 파일 | 내용 |
|---|---|
| `groups.json` | 그룹 |
| `policies.json` | 접근 제어 정책 |
| `setup-keys.json` | setup key (**값은 마스킹되어 내려옴**) |
| `peers.json` | 등록된 peer |
| `networks.json` | 네트워크 |
| `network-<id>-resources.json` | 네트워크가 배포하는 대역 |
| `network-<id>-routers.json` | 라우팅을 담당하는 peer |
| `routes.json` | 구형 라우트 |
| `dns-nameservers.json` | DNS |
| `accounts.json` | 계정 설정 |

## 커밋해도 안전한 이유

API 응답에는 비밀정보가 포함되지 않는다. setup key 값은 마스킹되고,
peer는 공개키·연결상태만 담긴다. **반면 `store.db`는 커밋하면 안 된다** —
토큰 해시와 peer 키가 들어있고, 바이너리라 diff도 무의미하며,
접속 시각 같은 상태값 때문에 설정을 안 바꿔도 파일이 매번 달라진다.

## 이것으로 대체되지 않는 것

이 스냅샷은 **변경 이력 추적**이 목적이다. 서버 장애 복구용으로는
`store.db` 백업이 따로 필요하다 (`sqlite3 store.db ".backup out.db"` — 
쓰기 중 `cp`는 깨진 사본이 나올 수 있다).

## Terraform 을 쓰지 않는 이유

공식 provider(`netbirdio/netbird`)가 존재하나 2026-03 기준 v0.0.9로 초기
단계이며, 신규 Networks 기능 지원 여부가 불확실하다. 일부만 코드로 관리되는
상태가 오히려 혼란을 키우므로, 성숙해진 뒤 재검토한다.
