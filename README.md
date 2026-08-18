# nicenomu-netbird-server

사내 NetBird(셀프호스팅 VPN) 관리서버 구성. 다른 PC에 처음부터 재구축할 때 이 저장소만 있으면 된다.

## 배경

> **왜 이 구조를 골랐는지**는 [docs/security-model.md](docs/security-model.md)에 정리했다.
> **Peer·Network·Group·Policy가 뭔지 모르겠다면** [docs/concepts.md](docs/concepts.md)부터 읽을 것.
> 설치 절차만 필요하면 아래를 읽으면 된다.


443 외 공인 포트를 모두 닫는 보안 정책에 따라, drive의 SFTP와 내부 관리 도구(Databasus 등)를
공인망에 노출하지 않고 VPN 뒤에서만 접근하도록 전환하는 것이 목적이다.

고객 주민등록번호 등 고유식별정보를 취급하므로 컨트롤 플레인이 외부 SaaS에 남으면 안 된다.
그래서 Tailscale(SaaS) / Headscale(공식 FAQ에서 스스로 "not enterprise software, 홈랩용"이라 명시)
대신 **NetBird 자체 호스팅**을 선택했다.

## 현재 구성

| 항목 | 값 |
|---|---|
| 관리서버 도메인 | `net.biseo.kr` |
| 관리서버 호스트 | 사무실 노트북 `agentrl` (Ubuntu 24.04) |
| 내부 IP / 공인 IP | `10.20.0.121` / `220.118.187.219` |
| 리버스 프록시 | Traefik (NetBird 내장) |
| IdP | NetBird 내장 Dex (→ Keycloak 전환 예정) |
| 라우팅 peer | stg `swarm-manager` (`10.10.2.9`) → `10.10.2.0/24` |

## 설치 절차

### 1. 손으로 해야 하는 것 (파일로 담을 수 없음)

- [ ] **DNS A 레코드** — Cloudflare `biseo.kr`에 `net` → 공인 IP, **프록시 끔(회색 구름)**
- [ ] **공유기 포트포워딩** — 아래 2개를 관리서버 내부 IP로
  - `443/TCP`
  - `3478/UDP`
- [ ] **호스트 준비** — `scripts/00-prepare-host.sh` 실행

### 2. NetBird 설치

```bash
curl -fsSL -o nb.sh https://github.com/netbirdio/netbird/releases/latest/download/getting-started.sh
sed -i 's|< /dev/tty||g' nb.sh          # 프롬프트를 stdin에서 읽도록 (비대화형 실행용)
printf '0\n<이메일>\nN\n' | sudo NETBIRD_DOMAIN=net.biseo.kr bash nb.sh
```

응답 3개의 의미: `0` = 내장 Traefik 사용 / 이메일 = Let's Encrypt 알림용 / `N` = NetBird Proxy 미사용

설치가 끝나면 `docker-compose.yml`, `config.yaml`, `dashboard.env`가 홈 디렉토리에 생성된다.
이 저장소의 `*.example` 파일은 그 결과물에서 시크릿만 가린 것이다.

### 3. 라우팅 peer 추가 (접근 대상 네트워크마다)

대시보드에서 Setup Key를 발급한 뒤, 그 네트워크 안의 서버에서:

```bash
curl -fsSL https://pkgs.netbird.io/install.sh | sudo sh
sudo netbird up --management-url https://net.biseo.kr --setup-key <KEY>
```

그다음 대시보드 `Network Routing → Networks`에서 서브넷 리소스와 라우팅 peer를 연결한다.

## 이 환경에서 겪은 함정 (중요)

재구축할 때 같은 삽질을 반복하지 않도록 남긴다.

### `*.iptime.org`로는 HTTPS 서비스를 못 한다

```
$ dig +short CAA iptime.org
0 issue ";"
0 issuewild ";"
```

ipTIME이 CAA 레코드로 **모든 인증기관의 발급을 원천 차단**해 놨다. Let's Encrypt든 ZeroSSL이든
전부 거부된다. CAA는 CNAME을 따라가도록 규정(RFC 8659)되어 있어 `net.biseo.kr → biseo.iptime.org`
CNAME 우회도 막힌다. **반드시 A 레코드로 IP를 직접 지정해야 한다.**

### 외부 80 포트를 못 쓴다

공유기의 외부 80은 `DEV-gateway`가 이미 점유 중이다. 다행히 NetBird의 Traefik은 기본이
`tlschallenge=true`(TLS-ALPN-01)라 **443만으로 인증서 발급과 갱신이 모두 된다.** 별도 설정 불필요.

certbot은 TLS-ALPN-01을 지원하지 않으므로(이슈 #6724, 수년째 미해결) 수동 발급이 필요하면
`acme.sh --alpn`을 써야 한다.

### 아웃바운드 80이 가로채기당한다

이 망은 나가는 80 트래픽을 `192.168.255.1/nd-bin/netdetect.cgi`로 리다이렉트한다(302).
apt가 깨지므로 sources를 https로 바꿔야 한다. `scripts/00-prepare-host.sh`가 처리한다.

### Tailscale과 IP 대역이 겹친다

NetBird가 할당한 `100.105.x.x`는 Tailscale의 CGNAT 대역(`100.64.0.0/10`) 안에 들어간다.
현재는 우연히 충돌하지 않지만, 두 VPN을 한 기계에 같이 쓸 계획이면 대역을 조정해야 한다.

### 서브넷은 명시적 A 레코드로 덮어써야 한다

`*.biseo.kr` 와일드카드가 stg 서버(`211.178.147.238`)를 가리키고 있어서, 새 서브도메인을
그냥 두면 stg로 간다. 반드시 개별 A 레코드를 만들어야 한다.

## 시크릿과 백업

`config.yaml`과 `dashboard.env`의 실제 값은 **커밋하지 않는다**(`.gitignore` 처리).

`config.yaml`에 세 개의 시크릿이 있다.

| 키 | 역할 |
|---|---|
| `server.authSecret` | 내부 컴포넌트 간 인증 |
| `server.auth.sessionCookieEncryptionKey` | 대시보드 세션 쿠키 암호화 |
| `server.store.encryptionKey` | **내부 DB 암호화** |

이전 방식이 두 가지로 갈린다.

| | 필요한 것 | peer 재등록 |
|---|---|---|
| 새로 시작 | 이 저장소만 | 필요 (전부 다시) |
| 완전 이전 | 저장소 + 시크릿 + `netbird_data` 볼륨 | 불필요 |

`store.encryptionKey`가 없으면 기존 DB를 읽을 수 없다. peer 목록·정책·계정을 그대로 옮기려면
시크릿과 데이터 볼륨을 함께 백업해야 한다.

## 운영 메모

- **인증서 자동갱신**: Traefik이 만료 30일 전 자동 처리. 다운타임 없음. cron 불필요.
  단, 갱신도 외부에서 `net.biseo.kr:443`에 도달 가능해야 하므로 **공인 IP가 바뀌면 실패**한다.
- **관리서버가 죽어도** 이미 연결된 peer 간 통신은 유지된다. 신규 등록·정책 변경만 막힌다.
- **최후의 복구 경로**: 사무실 LAN에서 관리서버 내부 IP로 직접 SSH. 노트북을 사무실 밖으로
  옮기면 안 된다(등록된 Wi-Fi SSID가 하나뿐이라 다른 곳에서는 인터넷 자체가 끊긴다).

## 남은 작업

- [ ] 유동 IP 대응 DDNS (Cloudflare API) — 공인 IP 고정 여부 미확인
- [ ] Keycloak 연동 (현재 내장 Dex) — 직원이 기존 biseo 계정으로 로그인
- [ ] 윈도우에서 SFTP 접속 검증
- [ ] 라우팅 peer 이중화
