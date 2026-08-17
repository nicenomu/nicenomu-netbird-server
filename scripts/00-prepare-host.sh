#!/bin/bash
# NetBird 관리서버 호스트 사전 준비
# 이 망 특유의 문제(아웃바운드 80 가로채기, 80포트 점유)를 해소한다.
set -euo pipefail

echo "== 1. apt를 https로 전환 =="
# 이 망은 아웃바운드 80을 192.168.255.1/netdetect.cgi 로 가로채므로 apt가 깨진다
if grep -q "http://" /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null; then
  cp /etc/apt/sources.list.d/ubuntu.sources "/etc/apt/sources.list.d/ubuntu.sources.bak-$(date +%Y%m%d)"
  sed -i 's|http://|https://|g' /etc/apt/sources.list.d/ubuntu.sources
  echo "   전환 완료 (백업 생성됨)"
else
  echo "   이미 https"
fi
apt-get update -qq

echo "== 2. 80/443 포트 점유 해제 =="
# Traefik이 80과 443을 써야 한다. 우분투 기본 apache2가 깔려 있으면 80을 잡는다.
if systemctl is-active --quiet apache2 2>/dev/null; then
  echo "   apache2가 80을 점유 중 -> 중지"
  systemctl disable --now apache2
fi
ss -tln | grep -E ':(80|443) ' && { echo "   !! 아직 점유 중. 위 프로세스를 정리할 것"; exit 1; } || echo "   80/443 비어있음"

echo "== 3. 필수 도구 확인 =="
for c in docker curl; do
  command -v "$c" >/dev/null || { echo "   !! $c 없음"; exit 1; }
done
docker compose version >/dev/null || { echo "   !! docker compose 없음"; exit 1; }
echo "   OK"

echo "== 4. 외부 도달성 확인 =="
echo "   아래는 반드시 '외부 회선(휴대폰 테더링 등)'에서 확인할 것."
echo "   같은 공유기 뒤에서 테스트하면 헤어핀 NAT 때문에 결과가 무의미하다."
echo "     - <도메인>:443/TCP 도달"
echo "     - <도메인>:3478/UDP 도달"

echo ""
echo "준비 완료. README의 '2. NetBird 설치'로 진행할 것."
