# OpenClaw + OpenManus — Kurulum Rehberi v4

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

---

# FAZ I — Hibrit Sistem (CAMEL-AI + OpenManus)

## Neden Hibrit?

Tek framework yeterli değil. Her birinin güçlü olduğu alan farklı:

| Framework | Güçlü Olduğu Alan |
|---|---|
| OpenManus | Kod, dosya, sandbox, planlama |
| CAMEL-AI | Rol simülasyonu, beyin fırtınası, tartışma |

## Kurulum

### 1. Ayrı Venv + CAMEL Kurulumu

    mkdir -p ~/camel-mcp && cd ~/camel-mcp
    python3 -m venv .venv
    source .venv/bin/activate
    pip install camel-ai "mcp==1.5.0"

NOT: mcp==1.5.0 kritik. Daha yeni sürümler CAMEL ile uyumsuz (FastMCP import hatası).

### 2. OpenRouter Bağlantısı

Ayrı bir OpenRouter key kullan (farklı key = farklı rate limit havuzu).

    echo 'export OPENROUTER_API_KEY="sk-or-v1-..."' >> ~/.bashrc
    source ~/.bashrc

Key'in 5$ limiti olmalı - free modeller için harcanmaz ama rate limit fallback tamponu olarak lazım.

### 3. MCP Server Wrapper

OpenClaw MCP server başlatırken .bashrc'yi okumaz. Wrapper script şart:

    cat > ~/camel-mcp/run.sh <<'EOF'
    #!/bin/bash
    export OPENROUTER_API_KEY="$(grep '^export OPENROUTER_API_KEY' ~/.bashrc | head -1 | cut -d'"' -f2)"
    exec ~/camel-mcp/.venv/bin/python ~/camel-mcp/camel_mcp_server.py 2>>/tmp/camel_stderr.log
    EOF
    chmod +x ~/camel-mcp/run.sh

### 4. OpenClaw'a Ekle

    openclaw mcp add camel --command "$HOME/camel-mcp/run.sh"

### 5. Doğrulama

    timeout 60 openclaw mcp probe camel

Beklenen: `camel: 3 tools, resources, prompts, ...`

## Kritik Tuzaklar

### 1. MCP Sürümü Uyumsuzluğu
- camel-ai, mcp>=1.3.0 bekliyor ama yeni sürümlerde (2.x) FastMCP API değişti
- Çözüm: `pip install "mcp==1.5.0"`

### 2. args:[""] Hatası
- openclaw mcp add bazen boş arg ekler
- Çözüm: config'i elle düzelt - args ve cwd kaldır, sadece command kalsın

### 3. Startup Timeout
- CAMEL-AI 500+ paket import eder -> 30-40 sn startup
- Çözüm 1: Lazy import (tool çağrılana kadar bekle)
- Çözüm 2: Eager load + timeout 180000ms

### 4. Rate Limit Yönetimi
- 6 farklı :free model sırayla dene
- Her deneme arası 3 sn bekle
- 2 turn = 4 LLM çağrısı -> rate limit riski
- 1 turn = 2 LLM çağrısı -> güvenli

### 5. openrouter/auto Alias'ı
- Bu alias ücretli model havuzuna yönlendirir
- Rate limit sonrası 0.1$ limitli key'i tüketebilir
- Çözüm: `openclaw config unset agents.defaults.models`

## Hibrit Kullanım Reçetesi

### Rol Simülasyonu (CAMEL)

    camel__role_play kullanarak:
    - task: "..."
    - assistant_role: "..."
    - user_role: "..."
    - turns: 1

### Beyin Fırtınası (CAMEL)

    camel__brainstorm kullanarak:
    - topic: "..."
    - perspectives: "Ekonomist, Teknisyen, Etik Uzmanı"
    - rounds: 1

### Tartışma (CAMEL)

    camel__debate kullanarak:
    - topic: "..."
    - side_a: "..."
    - side_b: "..."
    - rounds: 2

### Kod (OpenManus)

    sandbox_python_execute kullanarak ... çalıştır

## Kanıtlanmış Hibrit Senaryo

Bkz. `examples/hibrit-test/README.md`:

1. CAMEL ile PM + Dev diyalogu -> MVP planı
2. OpenManus ile Flask API yazıldı -> sandbox'ta test
3. Host'ta doğrulandı -> 200/201/200/204

Full chain: Plan (CAMEL) -> Code (OpenManus) -> Test (sandbox) -> Verify (host).

## Sistem Durumu

Toplam MCP Tool: 9
- openmanus: bash, python_execute, sandbox_python_execute, planning, str_replace_editor, terminate
- camel: role_play, brainstorm, debate

## Bugünün Özeti (Faz I)

- MCP deadlock fix (spawn context)
- CAMEL-AI kurulumu + entegrasyon
- Hibrit sistem kanıtı (plan -> kod -> test)
- Heartbeat sessizleştirme
- openrouter/auto alias temizliği
