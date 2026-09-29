import asyncio
import base64
from typing import Dict

from app.config import config
from app.tool.base import BaseTool


class SandboxPythonExecute(BaseTool):
    """Executes Python code in an isolated Daytona cloud sandbox."""

    name: str = "sandbox_python_execute"
    description: str = (
        "Executes Python code in an ISOLATED CLOUD SANDBOX (Daytona). "
        "USE THIS WHEN: you need to install packages (pip), read/write files, "
        "access the internet, run long computations (>10s), or execute untrusted code. "
        "WARNING: Sandbox creation takes 30-60 seconds. "
        "For quick calculations (<10s), use python_execute instead (much faster). "
        "Only print() outputs are visible."
    )
    parameters: dict = {
        "type": "object",
        "properties": {
            "code": {
                "type": "string",
                "description": "The Python code to execute in the sandbox.",
            },
            "timeout": {
                "type": "integer",
                "description": "Execution timeout in seconds (default: 300).",
            },
        },
        "required": ["code"],
    }

    async def execute(self, code: str, timeout: int = 300) -> Dict:
        if not config.daytona.daytona_api_key:
            return {
                "observation": "Daytona API key not configured. Set [daytona] daytona_api_key in config.toml.",
                "success": False,
            }

        try:
            from daytona import Daytona, DaytonaConfig, CreateSandboxFromImageParams

            dt = Daytona(DaytonaConfig(api_key=config.daytona.daytona_api_key))

            # 1) Sandbox oluştur
            sandbox = await asyncio.to_thread(
                dt.create,
                CreateSandboxFromImageParams(
                    image="python:3.12-slim",
                    language="python",
                ),
            )

            try:
                # 2) Kodu base64 ile gönder (quoting sorunlarından kaçınmak için)
                encoded = base64.b64encode(code.encode("utf-8")).decode("ascii")
                result = await asyncio.to_thread(
                    sandbox.process.exec,
                    f"echo {encoded} | base64 -d | python3",
                )

                return {
                    "observation": result.result or "(no output)",
                    "success": result.exit_code == 0,
                }
            finally:
                # 3) Her durumda sandbox'ı sil
                try:
                    await asyncio.to_thread(dt.delete, sandbox)
                except Exception:
                    pass

        except Exception as e:
            return {
                "observation": f"Sandbox execution failed: {type(e).__name__}: {e}",
                "success": False,
            }
