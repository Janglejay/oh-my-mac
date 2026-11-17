#!/usr/bin/env bash
# 复用 Neovim 的 Java 配置串行预热；只在 ServiceReady + 当前文件符号请求成功后计为通过。
# 手动：bash ~/.config/nvim/scripts/prewarm-jdtls.sh
# 可选：NVIM_PREWARM_PROJECTS_DIR=/path/to/projects NVIM_PREWARM_TIMEOUT=1200 bash ...
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"
PROJECTS_DIR="${NVIM_PREWARM_PROJECTS_DIR:-$HOME/Company/JavaProjects}"
WAIT_PER_PROJECT="${NVIM_PREWARM_TIMEOUT:-1200}"
LOG_FILE="${NVIM_PREWARM_LOG:-$HOME/prewarm-jdtls.log}"
NVIM_BIN="${NVIM_PREWARM_NVIM:-$(command -v nvim || true)}"
MAX_JOBS=1  # 不并发争抢 Java 堆和磁盘；串行计数避免旧版计数竞态。
TASK_DIR=""
RUNNER_PID=""
LOCK_OWNED=false
LOCK_DIR="${TMPDIR:-/tmp}/nvim-jdtls-prewarm-${UID}.lock"

case "$WAIT_PER_PROJECT" in ''|*[!0-9]*) echo "预热超时必须为正整数秒" >&2; exit 2;; esac
[ "$WAIT_PER_PROJECT" -gt 0 ] || { echo "预热超时必须大于0" >&2; exit 2; }
[ -x "$NVIM_BIN" ] || { echo "未找到 Neovim" >&2; exit 2; }
if ! JAVA_BACKEND=$("$NVIM_BIN" --headless -u NONE -i NONE -n \
    --cmd "lua io.write(dofile(vim.fn.expand('~/.config/nvim/lua/user/java_backend.lua')).server)" +qa 2>&1); then
  echo "无法读取 Neovim Java 后端配置: $JAVA_BACKEND" >&2
  exit 2
fi
if [ "$JAVA_BACKEND" = lathe ]; then
  echo "当前 Java 后端为 Lathe，跳过 JDT LS 预热。"
  exit 0
fi
[ "$JAVA_BACKEND" = jdtls ] || { echo "未知 Java 后端: $JAVA_BACKEND" >&2; exit 2; }
[ -d "$PROJECTS_DIR" ] || { echo "预热目录不存在: $PROJECTS_DIR" >&2; exit 2; }

# 重叠运行直接退出；不按目录年龄接管，也不关闭其它会话。
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "已有预热锁，跳过本次。确认无预热任务后可手动检查 $LOCK_DIR"
  exit 0
fi
LOCK_OWNED=true
printf '%s\n' "$$" > "$LOCK_DIR/pid"

cleanup() {
  if [ -n "$RUNNER_PID" ]; then
    kill -TERM "$RUNNER_PID" 2>/dev/null || true
    # runner 自己会有界回收本次独立进程组；shell 也不进行无界 wait。
    for ((i=0; i<15; i++)); do
      kill -0 "$RUNNER_PID" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$RUNNER_PID" 2>/dev/null; then
      # ticket 只在本次私有目录，由 runner 创建独立 session 后写入。
      "$PYTHON_BIN" "$TASK_DIR/runner.py" --stop-ticket "$TASK_DIR/owner.json" "$RUNNER_PID" || true
      kill -KILL "$RUNNER_PID" 2>/dev/null || true
    fi
    for ((i=0; i<3; i++)); do
      kill -0 "$RUNNER_PID" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$RUNNER_PID" 2>/dev/null; then
      echo "预热进程未退出，保留本次资源记录: $TASK_DIR" >&2
      return
    fi
    wait "$RUNNER_PID" 2>/dev/null || true
    RUNNER_PID=""
  fi
  if [ -n "$TASK_DIR" ] && [ -d "$TASK_DIR" ]; then rm -rf "$TASK_DIR"; fi
  if [ "$LOCK_OWNED" = true ]; then
    rm -f "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

TASK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nvim-jdtls-prewarm.XXXXXX")
: > "$LOG_FILE"
log() {
  printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG_FILE"
  if [ -t 1 ]; then printf '%s\n' "$*"; fi
}
notify() {
  if [ "${NVIM_PREWARM_NOTIFY:-1}" = 1 ] && [ -x /opt/homebrew/bin/terminal-notifier ]; then
    /opt/homebrew/bin/terminal-notifier -title "JDT 预热" -message "$1" >/dev/null 2>&1 || true
  fi
}

# Mason 的启动器执行 python3。使用本次任务私有 PATH，避免 cron 回落到不可用的系统 Python。
PYTHON_BIN=""
for candidate in /opt/homebrew/anaconda3/bin/python3 /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.11; do
  if [ -x "$candidate" ] && "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 9))' >/dev/null 2>&1; then
    PYTHON_BIN="$candidate"
    break
  fi
done
if [ -z "$PYTHON_BIN" ]; then
  candidate=$(command -v python3 || true)
  if [ -n "$candidate" ] && "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 9))' >/dev/null 2>&1; then
    PYTHON_BIN="$candidate"
  fi
fi
[ -n "$PYTHON_BIN" ] || { log "失败：未找到可用的 Python 3.9+"; exit 2; }
mkdir "$TASK_DIR/bin"
ln -s "$PYTHON_BIN" "$TASK_DIR/bin/python3"
export PATH="$TASK_DIR/bin:$PATH"

cat > "$TASK_DIR/check.lua" <<'LUA'
local uv = vim.uv or vim.loop
local result_path = assert(vim.env.NVIM_PREWARM_RESULT)
local timeout = tonumber(vim.env.NVIM_PREWARM_TIMEOUT_MS) or 1200000
local started = uv.now()
local finished, checking, service_ready = false, false, false
local tasks, ready_roots = {}, {}
local function current_client()
  local bufnr = vim.api.nvim_get_current_buf()
  local list = vim.lsp.get_clients({ name = "jdtls", bufnr = bufnr })
  return list[1], bufnr
end
local function finish(status, reason, symbol_count)
  if finished then return end
  finished = true
  local data = { status = status, reason = reason, elapsed_ms = uv.now() - started,
    symbols = symbol_count, check = "ServiceReady + current-file documentSymbol" }
  local f = assert(io.open(result_path, "w"))
  f:write(vim.json.encode(data)); f:close()
  -- 正常退出客户端后才关闭本次 headless 编辑器；不会操作其它编辑器的服务。
  local owned = vim.lsp.get_clients({ name = "jdtls" })
  for _, client in ipairs(owned) do client:stop() end
  local stop_started = uv.now()
  local function close()
    for _, client in ipairs(owned) do
      if not client:is_stopped() and uv.now() - stop_started < 10000 then
        vim.defer_fn(close, 100)
        return
      end
    end
    if status == "ok" then vim.cmd("qa!") else vim.cmd("cquit 1") end
  end
  close()
end
local function check()
  if finished or checking then return end
  local client, bufnr = current_client()
  if not client or not client.initialized then vim.defer_fn(check, 250); return end
  local status = (_G.nvim_java_status or {})[client.config.root_dir]
  service_ready = ready_roots[client.config.root_dir] or (status and status.type == "ServiceReady")
  if not service_ready then vim.defer_fn(check, 250); return end
  if next(tasks[client.id] or {}) then vim.defer_fn(check, 250); return end
  if not client:supports_method("textDocument/documentSymbol", bufnr) then
    finish("failed", "document_symbols_not_supported"); return
  end
  checking = true
  local sent = client:request("textDocument/documentSymbol", {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
  }, function(err, result)
    if err or type(result) ~= "table" then finish("failed", "document_symbol_request_failed"); return end
    finish("ok", "service_and_current_file_responded", #result)
  end, bufnr)
  if not sent then finish("failed", "document_symbol_request_not_sent") end
end
vim.api.nvim_create_autocmd("User", {
  pattern = "JdtlsStatus",
  callback = function(ev)
    local data = ev.data or {}
    if data.type == "ServiceReady" and data.root then
      ready_roots[data.root] = true
      vim.defer_fn(check, 250)
    elseif data.type == "Error" then
      local client = current_client()
      if client and client.config.root_dir == data.root then finish("failed", "language_status_error") end
    end
  end,
})
vim.api.nvim_create_autocmd("LspProgress", {
  callback = function(ev)
    local data = ev.data or {}
    local client = vim.lsp.get_client_by_id(data.client_id)
    if not client or client.name ~= "jdtls" then return end
    local params = data.params or {}
    local value = params.value or {}
    tasks[client.id] = tasks[client.id] or {}
    if value.kind == "begin" then tasks[client.id][tostring(params.token)] = true
    elseif value.kind == "end" then tasks[client.id][tostring(params.token)] = nil end
    if service_ready then vim.defer_fn(check, 250) end
  end,
})
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.defer_fn(function()
      local client = current_client()
      local status = client and (_G.nvim_java_status or {})[client.config.root_dir]
      if status and status.type == "ServiceReady" then service_ready = true end
      check()
    end, 250)
  end,
})
vim.defer_fn(function() finish("failed", "timeout_waiting_for_service_or_navigation") end, timeout)
LUA

# 子编辑器有自己的 session/进程组。只回收这一确证归属的组，覆盖正常退出后遗留的 JDT。
cat > "$TASK_DIR/runner.py" <<'PYRUN'
import json, os, signal, subprocess, sys, time

def alive(group):
    try:
        os.killpg(group, 0)
        return True
    except ProcessLookupError:
        return False

def stop_group(group):
    # 仅接受由本 runner 的 start_new_session 创建并记录的正 group ID。
    if group <= 1 or group == os.getpgrp():
        raise RuntimeError("invalid owned group")
    for sig, seconds in ((signal.SIGTERM, 3), (signal.SIGKILL, 2)):
        if not alive(group):
            return
        os.killpg(group, sig)
        end = time.monotonic() + seconds
        while alive(group) and time.monotonic() < end:
            time.sleep(0.1)

if len(sys.argv) > 1 and sys.argv[1] == "--stop-ticket":
    try:
        with open(sys.argv[2]) as f:
            ticket = json.load(f)
        if ticket["runner"] == int(sys.argv[3]) and ticket["private_session"] is True:
            stop_group(ticket["group"])
    except (FileNotFoundError, ProcessLookupError):
        pass
    raise SystemExit(0)

child = None
owned_group = None
owner, project, log_path, nvim, java_file = sys.argv[1:]

def interrupted(_sig, _frame):
    raise InterruptedError("prewarm interrupted")

signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
code = 1
try:
    with open(log_path, "wb") as log:
        child = subprocess.Popen([nvim, "--headless", "-i", "NONE", "--cmd",
            "lua dofile(vim.env.NVIM_PREWARM_SCRIPT)", java_file], cwd=project,
            stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        if os.getpgid(child.pid) != child.pid:
            raise RuntimeError("private session was not created")
        owned_group = child.pid
        with open(owner, "w") as f:
            json.dump({"runner": os.getpid(), "group": child.pid, "private_session": True}, f)
        timeout = int(os.environ["NVIM_PREWARM_TIMEOUT"]) + int(os.environ.get("NVIM_PREWARM_EXIT_GRACE", "20"))
        code = child.wait(timeout=timeout)
except (subprocess.TimeoutExpired, InterruptedError):
    code = 1
finally:
    # 后续信号不打断清理；TERM/KILL 和 wait 均有上限。
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    if child is not None:
        if owned_group is not None:
            stop_group(owned_group)
        elif child.poll() is None:
            child.kill()
        try:
            child.wait(timeout=2)
        except subprocess.TimeoutExpired:
            code = 1
    try:
        os.unlink(owner)
    except FileNotFoundError:
        pass
raise SystemExit(code if 0 <= code < 126 else 1)
PYRUN

export NVIM_PREWARM_SCRIPT="$TASK_DIR/check.lua"
export NVIM_PREWARM_TIMEOUT_MS=$((WAIT_PER_PROJECT * 1000))
total=0; warmed=0; skipped=0; failed=0
log "开始串行预热（并发 ${MAX_JOBS}）；通过仅表示服务就绪且当前文件符号请求成功，不代表全部业务导航已验收。"

for project_dir in "$PROJECTS_DIR"/*/; do
  [ -d "$project_dir" ] || continue
  if [ ! -f "$project_dir/pom.xml" ] && [ ! -f "$project_dir/build.gradle" ]; then continue; fi
  total=$((total + 1))
  project_name=$(basename "$project_dir")
  java_file=""
  while IFS= read -r -d '' candidate; do java_file="$candidate"; break; done < <(
    find "$project_dir" -type f -name '*.java' -not -path '*/target/*' -not -path '*/build/*' \
      -not -path '*/.git/*' -not -path '*/node_modules/*' -print0 2>/dev/null)
  if [ -z "$java_file" ]; then
    skipped=$((skipped + 1)); log "跳过 ${project_name}：无 Java 源文件"; continue
  fi
  result_file="$TASK_DIR/result-$total.json"
  export NVIM_PREWARM_RESULT="$result_file"
  log "检查 ${project_name}（最多 ${WAIT_PER_PROJECT}s）"
  export NVIM_PREWARM_TIMEOUT="$WAIT_PER_PROJECT"
  "$PYTHON_BIN" "$TASK_DIR/runner.py" "$TASK_DIR/owner.json" "$project_dir" \
    "$TASK_DIR/nvim-$total.log" "$NVIM_BIN" "$java_file" &
  RUNNER_PID=$!
  exit_code=0
  wait "$RUNNER_PID" || exit_code=$?
  RUNNER_PID=""
  elapsed=0
  if [ -f "$result_file" ]; then
    elapsed=$(
      "$PYTHON_BIN" -c \
        'import json,sys; print(round(json.load(open(sys.argv[1])).get("elapsed_ms",0)/1000))' \
        "$result_file" 2>/dev/null || echo 0
    )
  fi
  if [ "$exit_code" -eq 0 ] && [ -f "$result_file" ] && "$PYTHON_BIN" - "$result_file" <<'PY'
import json,sys
with open(sys.argv[1]) as f:
    result=json.load(f)
raise SystemExit(0 if result.get('status') == 'ok' else 1)
PY
  then
    warmed=$((warmed + 1)); log "通过 ${project_name}：ServiceReady + 当前文件符号查询（${elapsed}s）"
  else
    failed=$((failed + 1)); log "失败 ${project_name}：未获得完整通过证据（${elapsed}s，退出码 ${exit_code}）"
  fi
done

log "结束：项目 ${total}，通过 ${warmed}，跳过 ${skipped}，失败 ${failed}。旧缓存保留。"
notify "项目 ${total}，通过 ${warmed}，跳过 ${skipped}，失败 $failed"
[ "$failed" -eq 0 ]
