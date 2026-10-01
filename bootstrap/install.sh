#!/usr/bin/env bash
# ================================================================
# OpenClaw + OpenManus Bootstrap — Tek Komutla Kurulum
# ================================================================
# Kullanım:
#   curl -fsSL https://raw.githubusercontent.com/<KULLANICI>/OpenManus/main/bootstrap/install.sh | bash
# veya:
#   bash install.sh
# ================================================================
set -euo pipefail

# ---------- Renkler ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
err()  { echo -e "${RED}✗${NC} $*"; exit 1; }

# ---------- Değişkenler ----------
USER_HOME="$HOME"
USER_NAME="$(whoami)"
OPENMANUS_FORK="https://github.com/ereserbilisim-spec/OpenManus.git"
BACKUP_DIR="$USER_HOME/backups"
ENV_DIR="$USER_HOME/.config/systemd/user/openclaw-gateway.service.d"

# ================================================================
# 0. ÖN KONTROL
# ================================================================
log "Ön kontrol yapılıyor..."
[[ "$EUID" -eq 0 ]] && err "Root olarak çalıştırma! Normal kullanıcı ile çalıştır."
[[ ! -d "/etc/systemd/user" ]] && [[ ! -d "/usr/lib/systemd/user" ]] && err "systemd user bulunamadı."
command -v sudo >/dev/null || err "sudo bulunamadı. Ubuntu gerekli."
ok "Sistem kontrolü tamam."

# ================================================================
# 1. KEY'LERİ TOPLA (maskeli input)
# ================================================================
log "Key'leri topluyorum. Girdiler gizli olacak (yazarken görünmez)."
echo ""

read_secret() {
  local prompt="$1" varname="$2"
  local value=""
  while [ -z "$value" ]; do
    read -s -p "  $prompt: " value < /dev/tty; echo
    [ -z "$value" ] && warn "Boş bırakma, tekrar dene."
  done
  printf -v "$varname" '%s' "$value"
}

read_optional() {
  local prompt="$1" varname="$2"
  local value=""
  read -s -p "  $prompt (boş bırakabilirsin): " value < /dev/tty; echo
  printf -v "$varname" '%s' "$value"
}

read_secret "OpenRouter API Key (sk-or-v1-...)" OR_KEY
read_secret "NVIDIA NIM API Key (nvapi-...)" NV_KEY
read_secret "mem0 API Key (m0-...)" MEM0_KEY
read_secret "Tavily API Key (tvly-...)" TAVILY_KEY
read_secret "Daytona API Key (68 karakter)" DAYTONA_KEY
read_optional "Telegram Bot Token (boş = atla)" TG_TOKEN
if [ -n "$TG_TOKEN" ]; then
  read_secret "Telegram Chat ID (örn: 5434937726)" TG_CHATID
fi
echo ""
ok "Tüm key'ler alındı."

# ================================================================
# 2. SİSTEM PAKETLERİ
# ================================================================
log "Sistem paketleri kuruluyor (sudo gerekecek)..."
sudo apt update -qq
sudo apt install -y -qq \
  curl wget git build-essential \
  python3-pip python3-venv python3-dev \
  libssl-dev libffi-dev \
  ffmpeg tmux pipx jq \
  gh software-properties-common
ok "Temel paketler kuruldu."

# Node.js 24 LTS
if ! node --version 2>/dev/null | grep -q "^v24"; then
  log "Node.js 24 LTS kuruluyor..."
  curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - >/dev/null 2>&1
  sudo apt install -y -qq nodejs >/dev/null
fi
ok "Node.js: $(node --version)"

# npm prefix
if [ ! -d "$USER_HOME/.npm-global" ]; then
  mkdir -p "$USER_HOME/.npm-global"
  npm config set prefix "$USER_HOME/.npm-global"
fi
if ! grep -q "npm-global" "$USER_HOME/.bashrc"; then
  echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$USER_HOME/.bashrc"
fi
export PATH="$HOME/.npm-global/bin:$PATH"
ok "npm prefix hazır."

# ================================================================
# 3. OPENCLAW KURULUMU
# ================================================================
if ! command -v openclaw >/dev/null 2>&1; then
  log "OpenClaw kuruluyor..."
  npm install -g openclaw@latest >/dev/null 2>&1
fi
ok "OpenClaw: $(openclaw --version 2>&1 | head -1)"

# ================================================================
# 4. OPENMANUS FORK CLONE
# ================================================================
if [ ! -d "$USER_HOME/OpenManus" ]; then
  log "OpenManus fork'u klonlanıyor..."
  git clone "$OPENMANUS_FORK" "$USER_HOME/OpenManus"
fi
cd "$USER_HOME/OpenManus"
git remote add upstream https://github.com/FoundationAgents/OpenManus.git 2>/dev/null || true
ok "OpenManus hazır."

# venv + requirements
if [ ! -d "$USER_HOME/OpenManus/.venv" ]; then
  log "Python venv oluşturuluyor..."
  python3 -m venv .venv
fi
source .venv/bin/activate
pip install --upgrade -q pip setuptools wheel
log "Bağımlılıklar kuruluyor (5-10 dk)..."
pip install -q -r requirements.txt
pip install -q daytona

# config.toml
if [ ! -f config/config.toml ]; then
  cp config/config.example.toml config/config.toml
fi
# [daytona] yoksa ekle
if ! grep -q "^\[daytona\]" config/config.toml; then
  echo "" >> config/config.toml
  echo "[daytona]" >> config/config.toml
  echo "daytona_api_key = \"$DAYTONA_KEY\"" >> config/config.toml
fi
deactivate
ok "OpenManus bağımlılıkları kuruldu."

# ================================================================
# 5. SYSTEMD ENV OVERRIDE'LAR
# ================================================================
mkdir -p "$ENV_DIR"
chmod 700 "$ENV_DIR"

cat > "$ENV_DIR/nvidia-env.conf" <<EOF
[Service]
Environment="NVIDIA_API_KEY=$NV_KEY"
EOF
chmod 600 "$ENV_DIR/nvidia-env.conf"

cat > "$ENV_DIR/mem0-env.conf" <<EOF
[Service]
Environment="MEM0_API_KEY=$MEM0_KEY"
EOF
chmod 600 "$ENV_DIR/mem0-env.conf"

cat > "$ENV_DIR/tavily-env.conf" <<EOF
[Service]
Environment="TAVILY_API_KEY=$TAVILY_KEY"
EOF
chmod 600 "$ENV_DIR/tavily-env.conf"

cat > "$ENV_DIR/path.conf" <<EOF
[Service]
Environment="PATH=$USER_HOME/.local/bin:$USER_HOME/.npm-global/bin:$USER_HOME/.opencode/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF
chmod 600 "$ENV_DIR/path.conf"

# .bashrc env'leri
{
  echo ""
  echo "# OpenClaw env (bootstrap)"
  echo "export NVIDIA_API_KEY=\"$NV_KEY\""
  echo "export MEM0_API_KEY=\"$MEM0_KEY\""
  echo "export TAVILY_API_KEY=\"$TAVILY_KEY\""
  echo "export OPENROUTER_API_KEY=\"$OR_KEY\""
} >> "$USER_HOME/.bashrc"

# OPENROUTER_API_KEY systemd override (CAMEL + diğer MCP server'lar için)
cat > "$ENV_DIR/openrouter-env.conf" <<EOF
[Service]
Environment="OPENROUTER_API_KEY=$OR_KEY"
EOF
chmod 600 "$ENV_DIR/openrouter-env.conf"

systemctl --user daemon-reload
ok "systemd env override'ları hazır."

# ================================================================
# 6. OPENCLAW CONFIG
# ================================================================
log "OpenClaw yapılandırılıyor..."

# Ana config dizini
mkdir -p "$USER_HOME/.openclaw"
mkdir -p "$USER_HOME/.openclaw/workspace"

# Fallback zinciri + memory
openclaw config set memory.search.enabled false 2>/dev/null || true
openclaw config set memory.search.rememberAcrossConversations false 2>/dev/null || true

# Primary + fallbacks (OpenRouter)
PROFILE_PLACEHOLDER="setup-bootstrap"
openclaw config set agents.defaults.model.primary \
  "openrouter/nvidia/nemotron-3-ultra-550b-a55b:free@openrouter:$PROFILE_PLACEHOLDER" 2>/dev/null || true

openclaw config set agents.defaults.model.fallbacks '[
  "openrouter/thinkingmachines/inkling:free@openrouter:'"$PROFILE_PLACEHOLDER"'",
  "openrouter/qwen/qwen3.8-27b:free@openrouter:'"$PROFILE_PLACEHOLDER"'",
  "openrouter/google/gemma-4-31b-it:free@openrouter:'"$PROFILE_PLACEHOLDER"'",
  "openrouter/nvidia/nemotron-3-super-120b-a12b:free@openrouter:'"$PROFILE_PLACEHOLDER"'",
  "nvidia/nvidia/nemotron-3-ultra-550b-a55b",
  "nvidia/nvidia/nemotron-3-super-120b-a12b"
]' 2>/dev/null || true

# NVIDIA provider
openclaw config set models.providers.nvidia '{
  "baseUrl": "https://integrate.api.nvidia.com/v1",
  "api": "openai-completions"
}' 2>/dev/null || true
openclaw config set models.providers.nvidia.models '[]' 2>/dev/null || true

# Subagent/agent limitleri (RAM'e göre)
TOTAL_RAM_GB=$(free -g | awk '/^Bellek:|^Mem:/{print $2}')
if [ "$TOTAL_RAM_GB" -ge 14 ]; then
  openclaw config set agents.defaults.subagents.maxConcurrent 16 2>/dev/null || true
  openclaw config set agents.defaults.maxConcurrent 32 2>/dev/null || true
else
  openclaw config set agents.defaults.subagents.maxConcurrent 8 2>/dev/null || true
  openclaw config set agents.defaults.maxConcurrent 16 2>/dev/null || true
fi

ok "OpenClaw yapılandırıldı."

# ================================================================
# 7. MCP KÖPRÜSÜ (OpenManus)
# ================================================================
log "OpenManus MCP köprüsü kuruluyor..."
if ! openclaw mcp list 2>/dev/null | grep -q openmanus; then
  openclaw mcp add openmanus \
    --command "$USER_HOME/OpenManus/.venv/bin/python" \
    --arg "run_mcp_server.py" \
    --arg "--transport" \
    --arg "stdio" \
    --cwd "$USER_HOME/OpenManus" 2>/dev/null || warn "MCP ekleme başarısız, elle ekle: openclaw mcp add openmanus ..."
fi
ok "MCP köprüsü hazır."

# ================================================================
# 7.5 CAMEL-AI MCP KÖPRÜSÜ (rol simülasyonu, beyin fırtınası)
# ================================================================
log "CAMEL-AI MCP kuruluyor..."

CAMEL_DIR="$USER_HOME/OpenManus/camel-mcp"
CAMEL_WRAPPER="$USER_HOME/.local/bin/camel-mcp-run.sh"
mkdir -p "$USER_HOME/.local/bin"

if [ ! -f "$CAMEL_DIR/camel_mcp_server.py" ]; then
    warn "camel_mcp_server.py fork'ta bulunamadı — CAMEL kurulumu atlanıyor"
else
    # venv
    if [ ! -d "$CAMEL_DIR/.venv" ]; then
        log "CAMEL-AI venv oluşturuluyor..."
        python3 -m venv "$CAMEL_DIR/.venv"
    fi
    
    # Bağımlılıklar (camel-ai + mcp 1.5.0 — FastMCP uyumlu sürüm)
    "$CAMEL_DIR/.venv/bin/pip" install --upgrade -q pip setuptools wheel
    log "CAMEL-AI + MCP paketleri kuruluyor (3-5 dk sürebilir)..."
    "$CAMEL_DIR/.venv/bin/pip" install -q "camel-ai" "mcp==1.5.0"
    
    # Wrapper script — HOME ve CAMEL_DIR runtime'da genişler
    cat > "$CAMEL_WRAPPER" <<'WRAPPER_EOF'
#!/bin/bash
export OPENROUTER_API_KEY="$(grep '^export OPENROUTER_API_KEY' "$HOME/.bashrc" | head -1 | cut -d'"' -f2)"
exec "${CAMEL_DIR:-$HOME/OpenManus/camel-mcp}/.venv/bin/python" "${CAMEL_DIR:-$HOME/OpenManus/camel-mcp}/camel_mcp_server.py" 2>>/tmp/camel_stderr.log
WRAPPER_EOF
    chmod +x "$CAMEL_WRAPPER"
    
    # Wrapper'a CAMEL_DIR'i inject et
    sed -i "s|\${CAMEL_DIR:-\$HOME/OpenManus/camel-mcp}|$CAMEL_DIR|g" "$CAMEL_WRAPPER"
    
    # OpenClaw'a MCP olarak ekle
    if ! openclaw mcp list 2>/dev/null | grep -q "\bcamel\b"; then
        openclaw mcp add camel --command "$CAMEL_WRAPPER" 2>/dev/null || \
            warn "CAMEL MCP ekleme başarısız — elle: openclaw mcp add camel --command $CAMEL_WRAPPER"
    fi
    ok "CAMEL-AI MCP hazır."
fi

# ================================================================
# 8. TELEGRAM KANALI
# ================================================================
if [ -n "$TG_TOKEN" ]; then
  log "Telegram kanalı ekleniyor..."
  openclaw channels add --channel telegram --token "$TG_TOKEN" 2>/dev/null || warn "Telegram eklenemedi, elle dene"
  
  if [ -n "$TG_CHATID" ]; then
    openclaw config set commands.ownerAllowFrom "[\"telegram:$TG_CHATID\"]" 2>/dev/null || true
  fi
  ok "Telegram hazır."
fi

# ================================================================
# 9. SKILLS
# ================================================================
log "Skills kuruluyor..."
sudo apt install -y -qq tmux >/dev/null 2>&1 || true
npm install -g -q mcporter >/dev/null 2>&1 || true
pipx install -q openai-whisper 2>/dev/null || true
pipx ensurepath 2>/dev/null || true

# OpenCode (ücretsiz coding-agent)
if ! command -v opencode >/dev/null 2>&1; then
  curl -fsSL https://opencode.ai/install | bash >/dev/null 2>&1 || true
fi

openclaw config set skills.entries.coding-agent.enabled true 2>/dev/null || true
ok "Skills hazır."

# ================================================================
# 10. SELF-HEAL + BACKUP TIMER
# ================================================================
log "Self-heal ve backup timer'ları kuruluyor..."
mkdir -p "$BACKUP_DIR"

# self-heal.sh
cat > "$BACKUP_DIR/self-heal.sh" <<'SELFHEAL'
#!/bin/bash
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/.opencode/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
LOG="$HOME/backups/self-heal.log"
echo "$(date '+%F %T') self-heal başladı" >> $LOG
if ! systemctl --user is-active --quiet openclaw-gateway.service; then
    echo "$(date '+%F %T') Gateway down, restart..." >> $LOG
    systemctl --user restart openclaw-gateway.service; sleep 30
fi
if ! curl -s --max-time 10 http://127.0.0.1:18789/ -o /dev/null; then
    echo "$(date '+%F %T') HTTP timeout, restart..." >> $LOG
    systemctl --user restart openclaw-gateway.service; sleep 30
fi
if ! openclaw browser status 2>&1 | grep -q "running: true"; then
    echo "$(date '+%F %T') Browser down, başlatılıyor..." >> $LOG
    openclaw browser start >> $LOG 2>&1
fi
echo "$(date '+%F %T') self-heal tamamlandı" >> $LOG
SELFHEAL
chmod +x "$BACKUP_DIR/self-heal.sh"

# backup script
cat > "$BACKUP_DIR/openclaw-yedekle.sh" <<'BACKUPSCRIPT'
#!/bin/bash
set -e
DATE=$(date +%F_%H%M)
DEST=$HOME/backups/openclaw-$DATE
mkdir -p "$DEST"
tar -czf "$DEST/openclaw.tar.gz" -C $HOME .openclaw 2>/dev/null || true
tar -czf "$DEST/systemd.tar.gz" -C $HOME .config/systemd/user/openclaw-gateway.service.d .config/systemd/user/openclaw-gateway.service .config/environment.d/openclaw.conf 2>/dev/null || true
cd $HOME/OpenManus 2>/dev/null && git diff > "$DEST/openmanus.patch" 2>/dev/null || true
cp $HOME/OpenManus/config/config.toml "$DEST/openmanus-config.toml" 2>/dev/null || true
find $HOME/backups -maxdepth 1 -type d -name "openclaw-*" -mtime +30 -exec rm -rf {} \; 2>/dev/null || true
echo "✓ Yedek: $DEST"
BACKUPSCRIPT
chmod +x "$BACKUP_DIR/openclaw-yedekle.sh"

# systemd timers
mkdir -p "$USER_HOME/.config/systemd/user"

cat > "$USER_HOME/.config/systemd/user/openclaw-backup.service" <<EOF
[Unit]
Description=OpenClaw daily backup
[Service]
Type=oneshot
ExecStart=$BACKUP_DIR/openclaw-yedekle.sh
EOF

cat > "$USER_HOME/.config/systemd/user/openclaw-backup.timer" <<EOF
[Unit]
Description=Run OpenClaw backup daily at 03:00
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF

cat > "$USER_HOME/.config/systemd/user/openclaw-selfheal.service" <<EOF
[Unit]
Description=OpenClaw self-heal check
[Service]
Type=oneshot
ExecStart=$BACKUP_DIR/self-heal.sh
EOF

cat > "$USER_HOME/.config/systemd/user/openclaw-selfheal.timer" <<EOF
[Unit]
Description=Run OpenClaw self-heal every 15 minutes
[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now openclaw-backup.timer 2>/dev/null || true
systemctl --user enable --now openclaw-selfheal.timer 2>/dev/null || true
ok "Timer'lar aktif."

# ================================================================
# 11. GATEWAY BAŞLAT
# ================================================================
log "Gateway başlatılıyor..."
systemctl --user restart openclaw-gateway.service
sleep 45
systemctl --user is-active openclaw-gateway.service

# ================================================================
# 12. DOĞRULAMA
# ================================================================
echo ""
echo "════════════════════════════════════════════"
echo "  KURULUM TAMAMLANDI — ÖZET"
echo "════════════════════════════════════════════"
echo ""
echo "Gateway:        $(systemctl --user is-active openclaw-gateway.service)"
echo "OpenClaw:       $(openclaw --version 2>&1 | head -1)"
echo "Node:           $(node --version)"
echo "Python:         $(python3 --version)"
echo "RAM:            $(free -h | awk '/^Bellek:|^Mem:/{print $2, "toplam,", $7, "boş"}')"
echo "OpenManus:      $USER_HOME/OpenManus"
echo "Workspace:      $USER_HOME/.openclaw/workspace"
echo "Backup dir:     $BACKUP_DIR"
echo ""
echo "Model zinciri:"
openclaw models status 2>&1 | grep -E "Default|Fallbacks" | head -2
echo ""
echo "MCP:"
timeout 30 openclaw mcp probe openmanus 2>&1 | tail -2
echo ""
echo "Timer'lar:"
systemctl --user list-timers --no-pager 2>/dev/null | grep -E "openclaw|NEXT" | head -3
echo ""
ok "Sistem hazır! TUI başlatmak için: openclaw"
echo ""
echo "Not: İlk seferde onboarding'i tamamlamak için:"
echo "  openclaw onboard --install-daemon"
echo ""

