#!/bin/bash
export OPENROUTER_API_KEY="$(grep '^export OPENROUTER_API_KEY' ~/.bashrc | head -1 | cut -d'"' -f2)"
exec /home/ereser/camel-mcp/.venv/bin/python /home/ereser/camel-mcp/camel_mcp_server.py 2>>/tmp/camel_stderr.log
