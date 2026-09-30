# CAMEL-AI MCP Server

Hibrit mimari: OpenManus'un yanında rol simülasyonu sunar.

## Kurulum

    cd ~/OpenManus/camel-mcp
    python3 -m venv .venv
    source .venv/bin/activate
    pip install camel-ai "mcp==1.5.0"

## OpenClaw'a Ekle

    openclaw mcp add camel \
      --command "$HOME/OpenManus/camel-mcp/run.sh"

## Tool'lar

- **role_play**: İki ajan arasında rol simülasyonu
- **brainstorm**: Çoklu perspektif beyin fırtınası
- **debate**: İki taraf arasında tartışma
