# 운영 매뉴얼

이 시스템을 인계받아 매일 운영하는 사람을 위한 문서.
구축 절차는 [../README.md](../README.md), 개념은 [concepts.md](concepts.md),
왜 이 구조인지는 [security-model.md](security-model.md)를 볼 것.

## 접근 정보

| 대상 | 주소 | 비고 |
|---|---|---|
| NetBird 대시보드 | `https://net.biseo.kr` | 관리자 로그인 |
| 관리서버 (노트북) | 사무실 LAN 내부 IP, 호스트명 `agentrl` | 최후의 복구 경로 |
| Keycloak (stg) | `https://auth.biseo.kr/auth` realm `biseo` | 계정 관리 |
| drive SFTP | `10.10.2.233:38592` | VPN 연결 후에만 접근 가능 |

---

## 일상 운영

### 신규 직원 온보딩

1. 직원이 [사용자 설치 안내서](user-setup-windows.md)대로 설치·로그인
2. 관리자는 대시보드 `Team → Users`에서 **승인 대기 사용자를 승인**
3. 직원이 다시 연결하면 접속됨

> **승인 절차는 의도된 안전장치다.** 이게 없으면 Keycloak `biseo` realm에 계정이 있는
> 사람은 누구나 사내망에 들어온다. 자동 승인으로 바꾸지 말 것.

### 사용자 승인

```
Team → Users → 대기 중인 사용자 → 승인
```

승인 전에 **그 사람이 실제 직원인지, VPN 접근이 필요한 업무인지** 확인할 것.

### 퇴사자 차단

**Keycloak에서 계정을 비활성화하면 끝난다.** NetBird에서 따로 지울 필요 없다.

한 사람이 PC·노트북을 여러 대 쓰더라도 모두 같은 계정에 묶여 있으므로 한 번에 차단된다.
NetBird 대시보드에서 해당 peer들을 삭제하면 목록이 깔끔해진다(선택).

### 자동 그룹 배정 확인

새 직원의 peer가 `office-staff` 그룹에 자동으로 들어가야 한다.

```
Team → Users → 해당 사용자 → Auto-assigned groups → office-staff
```

**이게 비어 있으면 그 사용자의 peer는 그룹 없이 등록되고, 정책에 걸리지 않아
`netbird status`에서 `Networks: -`가 뜬다.** 실제로 여러 번 이 문제로 막혔다.

---

## 장애 대응

### 증상별 진단 순서

#### 전원(全員)이 안 될 때 → 관리서버 또는 회선 문제

```
① 외부에서 https://net.biseo.kr 접속되나?
     └ 안 되면 ②로
② 노트북이 살아 있나? (사무실 LAN에서 SSH, 또는 물리 확인)
     └ 살아 있으면 ③으로
③ 컨테이너 3개 떠 있나?   docker ps
     netbird-traefik / netbird-server / netbird-dashboard
④ 노트북에서 본 공인 IP와 net.biseo.kr의 DNS 응답이 일치하나?
     dig +short A net.biseo.kr
     curl -s https://api.ipify.org        (노트북에서 실행)
     └ 불일치면 공인 IP가 바뀐 것 → DNS A 레코드 수정
⑤ 공유기 포트포워딩 규칙이 남아 있나?
     443/TCP, 3478/UDP → 노트북 내부 IP
```

**오류 메시지로 원인이 갈린다.**

| 증상 | 의미 |
|---|---|
| `ECONNREFUSED` (즉시 거부) | 공유기까지 도달했으나 전달할 곳이 없음 → **포트포워딩 유실** |
| timeout (응답 없음) | 패킷이 도달조차 못 함 → 회선·방화벽·IP 변경 |
| 인증서 오류 | Traefik 문제 또는 갱신 실패 |

#### 특정 직원만 안 될 때 → 그룹·정책 문제

그 PC에서:

```cmd
netbird status
```

| 결과 | 원인 |
|---|---|
| `Management: Connected` 인데 `Networks: -` | **그룹 미배정** 또는 정책에 안 걸림 |
| `Management:` 연결 실패 | Management URL이 기본값(클라우드)일 수 있음 |
| 정상인데 접속만 안 됨 | 아래 SFTP 항목 참고 |

`Networks: -` 해결:

```
① Peers에서 그 PC가 office-staff 그룹에 있는지 확인
② 없으면 배정 → 저장
③ 윈도우에서 netbird down → netbird up
```

③을 빼먹으면 반영이 안 될 수 있다. 그룹 배정과 재접속이 겹치면 네트워크 맵을 놓친다.

#### VPN은 되는데 SFTP만 안 될 때

```
ping 10.10.2.233     → 성공해야 함
```

성공하는데 SFTP만 실패하면 **인증 문제**다. 순서대로 검사된다.

```
1. Keycloak 비밀번호 검증
2. 소속 회사가 sftp.allowed-company-uuids 4곳에 포함되는가
3. 스토리지 활성 상태인가
```

2번이 흔하다. **비밀번호가 맞아도 허용된 회사 소속이 아니면 거부된다.**
실패 사유는 drive 컨테이너 로그에 남는다.

```bash
docker service logs stg_drive-app | grep -i sftp
```

### 관리서버 DB 직접 조회

대시보드보다 정확하다. peer·그룹·정책의 실제 상태를 볼 수 있다.

```bash
ssh nice@<노트북>  'docker run --rm -v nice_netbird_data:/d:ro alpine cat /d/store.db' > nb.db
python3   # sqlite3로 조회
```

핵심 테이블: `peers`, `groups`, `group_peers`, `policies`, `policy_rules`,
`network_resources`, `network_routers`, `users`(auto_groups 확인)

**읽기만 할 것.** 변경은 반드시 대시보드를 통해서.

---

## 겪은 장애 사례

기록해두지 않으면 다음 사람이 같은 시간을 쓴다.

### 공유기 포트포워딩 규칙이 사라짐

증상: 외부에서 `net.biseo.kr` 접속 시 `ECONNREFUSED`. 노트북과 컨테이너는 모두 정상.

원인: 공유기 재부팅 또는 펌웨어 갱신으로 포트포워딩 규칙 유실.

판별: `ECONNREFUSED`(즉시 거부)와 timeout(무응답)은 다르다. 전자는 공유기까지는
도달했다는 뜻이므로 회선이 아니라 전달 규칙 문제다.

### 로그인 계정을 바꾸니 접속 불가

증상: 같은 PC인데 계정만 바꿨더니 `Networks: -`.

원인: **NetBird는 계정이 다르면 다른 기기로 취급한다.** 새 peer가 생성되고,
새 peer는 어떤 그룹에도 자동 배정되지 않는다(auto_groups 미설정 시).

대책: 사용자별 `Auto-assigned groups` 설정. 이걸 해두면 재발하지 않는다.

### 진단용 ping이 정책에 막혀 오진

증상: `ping 100.105.6.203`(라우팅 peer 직접)이 실패해서 VPN 자체가 고장난 줄 앎.

원인: 라우팅 peer에 **직접** 붙는 것은 별도 peer-to-peer 정책이 필요하다.
통과 트래픽(10.10.2.x)과는 무관하다.

대책: 진단 편의를 위해 라우팅 peer 접근 정책의 source에 `office-staff`를 넣어둘 것.

---

## 정기 점검

| 주기 | 항목 |
|---|---|
| 월 1회 | 인증서 만료일 확인 (`openssl s_client -connect net.biseo.kr:443 ...`) |
| 월 1회 | 공유기 포트포워딩 규칙 존재 확인 |
| 월 1회 | 퇴사자 계정이 Keycloak에서 비활성화됐는지 |
| 분기 1회 | 사용하지 않는 peer 정리 |
| 분기 1회 | 접근 정책이 필요 이상으로 넓지 않은지 |

인증서는 Traefik이 만료 30일 전 자동 갱신한다. **단 갱신도 외부에서 443 도달이 가능해야
성공한다.** 공인 IP가 바뀐 채 방치되면 조용히 실패하고 90일 뒤 전면 정지된다.

---

## 해서는 안 되는 것

- **Exit Node 켜기** — 모든 인터넷 트래픽이 관리서버를 거치게 된다
- **넓은 대역 등록** (`0.0.0.0/0` 등) — exit node를 안 켜도 같은 결과
- **신규 사용자 자동 승인** — realm에 계정 있는 사람이 전부 들어온다
- **SSH 포트를 공인망에 열기** — 이 프로젝트의 목적이 무너진다
- **관리자 계정을 직원과 공유** — 각자 Keycloak 계정으로 로그인시킬 것
- **관리서버 DB 직접 수정** — 읽기만

## 알려진 미완료 항목

- **DDNS 미설정** — 공인 IP가 바뀌면 전원 접속 불가 + 인증서 갱신 실패
- **라우팅 peer 단일** — `swarm-manager` 재부팅 시 전원 접속 불가
- **정책 포트 범위가 ALL** — SFTP(38592)만 허용하도록 좁힐 것
- **`netbird` Keycloak 클라이언트가 realm JSON에 미반영** — Keycloak DB 재생성 시 소실
