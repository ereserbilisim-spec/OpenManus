# OpenClaw + OpenManus — Kurulum Rehberi v3

Tarih: 2026-09-30
Durum: Faz A-I tamam, Manus seviyesi

## Hızlı Kurulum

curl -fsSL https://raw.githubusercontent.com/ereserbilisim-spec/OpenManus/main/bootstrap/install.sh | bash

Script sana sırayla soracak:
- OpenRouter API key
- NVIDIA NIM API key
- mem0 API key
- Tavily API key
- Daytona API key
- Telegram bot token (opsiyonel)

## Faz Haritası

| Faz | İçerik | Durum |
|-----|--------|-------|
| A | Runtime (Node 24, Python 3.12) | OK |
| B | Orkestratör (OpenClaw + Telegram + Web UI) | OK |
| C | Model (OpenRouter 4x + NVIDIA 2x) | OK |
| D | Araçlar (MCP 6 tool) | OK |
| E | Hafıza (mem0 + USER.md) | OK |
| F | Sandbox (Daytona) | OK |
| G | Otonom (Automations, Subagents, Tasks) | OK |
| H | Dayanıklılık (self-heal, backup) | OK |
| I | Çoklu Ajan (Planner→Executor→Verifier) | OK |
| J | Gerçek Proje | Sırada |

## Kritik Tuzaklar

### 1. MCP Multiprocessing Deadlock
Sorun: python_execute MCP üzerinden timeout veriyordu.
Sebep: multiprocessing.Manager() default fork context kullanır. Asyncio event loop içinde fork = deadlock.
Çözüm: app/tool/python_execute.py içinde:
  _MP_CTX = multiprocessing.get_context('spawn')
  Manager() ve Process() çağrılarını _MP_CTX üzerinden yap

### 2. Model Fallback Zinciri
- Primary: openrouter/nvidia/nemotron-3-ultra-550b-a55b:free
- 4x OpenRouter :free fallback
- 2x NVIDIA NIM bağımsız havuz

### 3. Rol Zinciri (Faz I)
Planner → Executor → Verifier
- Her rol ayrı subagent spawn edilir
- Executor gerçek araçları kullanmalı (yoksa halüsinasyon)
- Verifier kanıt ister

### 4. NVIDIA Key systemd Override ŞART
.bashrc export gateway'e yetmez.
~/.config/systemd/user/openclaw-gateway.service.d/nvidia-env.conf gerekli.

### 5. PATH Override
whisper, opencode, mcporter için systemd'ye PATH eklenmelidir.

### 6. Secrets Store Sıralaması
ÖNCE secrets store set, SONRA secrets configure.

## Dosya Yerleri

| Ne | Nerede |
|----|--------|
| OpenClaw config | ~/.openclaw/openclaw.json |
| Workspace | ~/.openclaw/workspace/ |
| systemd override | ~/.config/systemd/user/openclaw-gateway.service.d/ |
| Backup | ~/backups/ |
| OpenManus | ~/OpenManus/ |

## Self-Heal Sistemi

| Kontrol | Aralık | Ne yapar |
|---------|--------|----------|
| systemd auto-restart | 5 sn | Gateway çökerse restart |
| Self-heal timer | 15 dk | HTTP timeout, browser, RAM guard |
| Backup timer | 03:00 | Full backup + rotasyon |

## Sorun Giderme

| Hata | Çözüm |
|------|-------|
| MCP -32001 timeout | python_execute.py spawn fix |
| chat not found Telegram | Chat ID 10 hane mi? |
| auth error NVIDIA | systemd override'da key var mı? |
| Gateway auto-restart | journalctl --user -u openclaw-gateway.service -n 50 |
| mem0 no API key | openclaw mem0 init |
| Browser not running | openclaw browser start |

## Sistem Gereksinimleri

| Bileşen | Minimum | Öneri |
|---------|---------|-------|
| OS | Ubuntu 22.04 | Ubuntu 24.04 |
| RAM | 4 GB | 16 GB |
| Disk | 40 GB | 100 GB |
| Node.js | 24.16 | 24.x LTS |
| Python | 3.12 | 3.12 |
