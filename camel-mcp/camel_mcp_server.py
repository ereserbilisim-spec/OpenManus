#!/usr/bin/env python3
import warnings
warnings.filterwarnings("ignore")

"""
CAMEL-AI MCP Server
Rol simülasyonu, beyin fırtınası ve tartışma araçlarını MCP üzerinden sunar.
"""
import os
import sys
import asyncio
from typing import Any, Dict, List

from mcp.server.fastmcp import FastMCP

from camel.models import ModelFactory
from camel.types import ModelPlatformType
from camel.agents import ChatAgent
from camel.messages import BaseMessage

# ---------- Config ----------
OPENROUTER_KEY = os.environ.get("OPENROUTER_API_KEY", "")
if not OPENROUTER_KEY:
    print("ERROR: OPENROUTER_API_KEY not set", file=sys.stderr)
    sys.exit(1)

# Fallback listesi
DEFAULT_MODELS = [
    "nvidia/nemotron-3-ultra-550b-a55b:free",
    "thinkingmachines/inkling:free",
    "qwen/qwen3.8-27b:free",
    "google/gemma-4-31b-it:free",
]

# ---------- Model factory ----------
def make_model(model_id: str):
    return ModelFactory.create(
        model_platform=ModelPlatformType.OPENAI_COMPATIBLE_MODEL,
        model_type=model_id,
        url="https://openrouter.ai/api/v1",
        api_key=OPENROUTER_KEY,
    )

# ---------- MCP Server ----------
mcp = FastMCP("camel-ai")

# Eager load: CAMEL'i sunucu başlarken yükle (MCP client beklemez)
# Timeout olmasın diye sunucu hazır olmadan CAMEL import edilir
print("CAMEL-AI yükleniyor...", file=__import__("sys").stderr)
from camel.models import ModelFactory
from camel.types import ModelPlatformType
from camel.agents import ChatAgent
from camel.messages import BaseMessage
print("CAMEL-AI hazır", file=__import__("sys").stderr)

def try_with_fallback(sys_msg: str, user_content: str, role_name: str = "User", models: List[str] = None):
    """Model fallback ile agent.step çağır"""
    models = models or DEFAULT_MODELS
    for model_id in models:
        try:
            agent = ChatAgent(system_message=sys_msg, model=make_model(model_id))
            msg = BaseMessage.make_user_message(role_name=role_name, content=user_content)
            response = agent.step(msg)
            if response and response.msgs and response.msgs[0].content:
                return response.msgs[0].content, model_id
        except Exception:
            continue
    return None, None


@mcp.tool()
async def role_play(
    task: str,
    assistant_role: str,
    user_role: str,
    turns: int = 2,
    assistant_system: str = "",
    user_system: str = "",
) -> Dict[str, Any]:
    """
    İki ajan arasında rol simülasyonu yapar.
    
    Args:
        task: Görev tanımı (örn: "Bir e-ticaret sitesi için sprint planı yap")
        assistant_role: Asistan rolü (örn: "Proje Yöneticisi")
        user_role: Kullanıcı rolü (örn: "Kıdemli Geliştirici")
        turns: Kaç tur konuşacaklar (default: 2)
        assistant_system: Asistan için özel system message (opsiyonel)
        user_system: Kullanıcı için özel system message (opsiyonel)
    
    Returns:
        Dict: {"dialogue": [...], "models_used": [...]}
    """
    sys_assistant = assistant_system or f"Sen {assistant_role} rolündesin. Kısa, net, profesyonel konuş. Her cevabın 2-3 cümle."
    sys_user = user_system or f"Sen {user_role} rolündesin. Teknik detayları sor, realist yaklaş. Her cevabın 2-3 cümle."
    
    dialogue = []
    models_used = set()
    current_msg = task
    
    for turn in range(min(turns, 1)):  # max 1 turn for timeout safety
        # Assistant cevabı
        assistant_answer, model1 = try_with_fallback(sys_assistant, current_msg, user_role)
        if not assistant_answer:
            return {"error": "Assistant rolü cevap veremedi (tüm modeller başarısız)"}
        models_used.add(model1)
        dialogue.append({"role": assistant_role, "content": assistant_answer, "turn": turn + 1})
        
        pass  # no sleep
        
        # User cevabı
        user_answer, model2 = try_with_fallback(sys_user, assistant_answer, assistant_role)
        if not user_answer:
            return {"error": "User rolü cevap veremedi (tüm modeller başarısız)"}
        models_used.add(model2)
        dialogue.append({"role": user_role, "content": user_answer, "turn": turn + 1})
        
        current_msg = user_answer
        pass  # no sleep
    
    return {
        "task": task,
        "dialogue": dialogue,
        "models_used": sorted(models_used),
        "total_turns": turns,
    }


@mcp.tool()
async def brainstorm(
    topic: str,
    perspectives: str,
    rounds: int = 1,
) -> Dict[str, Any]:
    """
    Birden fazla perspektiften beyin fırtınası yapar.
    
    Args:
        topic: Tartışılacak konu
        perspectives: Virgülle ayrılmış perspektif listesi (örn: "Ekonomist, Teknisyen, Etik Uzmanı")
        rounds: Kaç tur tartışacaklar
    
    Returns:
        Dict: Her perspektifin görüşü
    """
    perspective_list = [p.strip() for p in perspectives.split(",")]
    opinions = []
    
    for p in perspective_list:
        sys_msg = f"Sen {p} rolündesin. Konuyu kendi uzmanlık açından kısaca değerlendir (2-3 cümle)."
        answer, model = try_with_fallback(sys_msg, topic)
        if answer:
            opinions.append({"perspective": p, "opinion": answer, "model": model})
        await asyncio.sleep(2)
    
    return {
        "topic": topic,
        "perspectives": perspective_list,
        "opinions": opinions,
    }


@mcp.tool()
async def debate(
    topic: str,
    side_a: str,
    side_b: str,
    rounds: int = 2,
) -> Dict[str, Any]:
    """
    İki taraf arasında tartışma simülasyonu.
    
    Args:
        topic: Tartışma konusu
        side_a: Birinci tarafın pozisyonu (örn: "Remote çalışmayı savun")
        side_b: İkinci tarafın pozisyonu (örn: "Ofis çalışmasını savun")
        rounds: Kaç tur tartışacaklar
    
    Returns:
        Dict: Diyalog listesi
    """
    sys_a = f"Sen tartışmacısın. Şu pozisyonu savun: {side_a}. Kısa, iddialı konuş (2-3 cümle)."
    sys_b = f"Sen tartışmacısın. Şu pozisyonu savun: {side_b}. Kısa, iddialı konuş (2-3 cümle)."
    
    dialogue = []
    current_msg = topic
    
    for turn in range(rounds):
        a_answer, _ = try_with_fallback(sys_a, current_msg, "B")
        if not a_answer:
            break
        dialogue.append({"side": "A", "position": side_a, "content": a_answer, "round": turn + 1})
        
        pass  # no sleep
        
        b_answer, _ = try_with_fallback(sys_b, a_answer, "A")
        if not b_answer:
            break
        dialogue.append({"side": "B", "position": side_b, "content": b_answer, "round": turn + 1})
        
        current_msg = b_answer
        pass  # no sleep
    
    return {"topic": topic, "side_a": side_a, "side_b": side_b, "dialogue": dialogue}


if __name__ == "__main__":
    mcp.run(transport="stdio")
