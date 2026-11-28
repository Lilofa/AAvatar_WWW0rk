#!/usr/bin/env bash
# Ставит Entire CLI и включает чекпоинты в ЭТОМ репозитории в БЕЗОПАСНОМ режиме:
# переписка с агентом остаётся только на вашем компьютере (репозиторий публичный).
# Подробности: docs/entire.md
#
#   ./scripts/entire-setup.sh                       # локально, ничего не пушится
#   ./scripts/entire-setup.sh github:owner/private  # чекпоинты в ПРИВАТНЫЙ репозиторий
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
private_remote="${1:-}"

if ! command -v entire >/dev/null 2>&1; then
  echo "→ Ставлю Entire CLI…"
  if command -v brew >/dev/null 2>&1; then
    brew install --cask entireio/tap/entire
  elif command -v go >/dev/null 2>&1; then
    go install github.com/entireio/cli/cmd/entire@latest
    export PATH="$(go env GOPATH)/bin:$PATH"
  else
    curl -fsSL https://entire.com/install.sh | bash
  fi
fi
entire version

# Включаем и сразу задаём режим хранения — до любого push, так что наружу ничего не уйдёт.
entire enable

if [[ -n "$private_remote" ]]; then
  if [[ "$private_remote" == *"AAvatar_WWW0rk"* ]]; then
    echo "✗ Это публичный репозиторий проекта. Нужен отдельный ПРИВАТНЫЙ." >&2
    exit 1
  fi
  echo "→ Чекпоинты будут уходить в $private_remote"
  entire configure --local --checkpoint-remote "$private_remote"
else
  echo "→ Чекпоинты только на этом компьютере (--skip-push-sessions)"
  entire configure --local --skip-push-sessions
fi

entire status || true

echo
echo "Готово. Перед каждым push проверяйте: entire checkpoint list --outgoing"
