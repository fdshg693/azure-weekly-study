<script lang="ts">
  import type { PageData } from './$types';

  let { data }: { data: PageData } = $props();

  let status = $state(data.status);
  let statusError = $state<string | null>(data.statusError);

  let selectedCommand = $state(data.status?.allowed_commands?.[0] ?? '');
  let runResult = $state<unknown>(null);
  let runBusy = $state(false);
  let vmActionBusy = $state(false);

  interface LogItem {
    timestamp_utc: string;
    alias: string;
    status: string;
    caller: string;
    detail: Record<string, unknown>;
  }
  let logs = $state<LogItem[]>([]);
  let logsBusy = $state(false);

  async function refreshStatus() {
    statusError = null;
    const r = await fetch('/api/status');
    const j = await r.json();
    if (!r.ok) {
      statusError = j.error ?? `HTTP ${r.status}`;
      return;
    }
    status = j;
  }

  async function runCommand() {
    if (!selectedCommand) return;
    runBusy = true;
    runResult = null;
    try {
      const r = await fetch('/api/run', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ command: selectedCommand })
      });
      runResult = { httpStatus: r.status, body: await r.json() };
    } finally {
      runBusy = false;
      refreshStatus();
      loadLogs();
    }
  }

  async function vmAction(action: 'start' | 'stop') {
    vmActionBusy = true;
    try {
      const r = await fetch(`/api/${action}`, { method: 'POST' });
      runResult = { httpStatus: r.status, body: await r.json() };
    } finally {
      vmActionBusy = false;
      refreshStatus();
      loadLogs();
    }
  }

  async function loadLogs() {
    logsBusy = true;
    try {
      const r = await fetch('/api/logs?limit=30');
      const j = await r.json();
      logs = j.items ?? [];
    } finally {
      logsBusy = false;
    }
  }

  // 初回ロード
  loadLogs();
</script>

<section class="card">
  <h2>VM Status</h2>
  {#if statusError}
    <p class="error">取得失敗: {statusError}</p>
  {:else if status}
    <dl>
      <dt>VM</dt><dd>{status.vm_name}</dd>
      <dt>Power</dt>
      <dd>
        <span class="badge" data-state={status.power_state}>{status.power_state}</span>
      </dd>
      <dt>Last access (UTC)</dt><dd>{status.last_access_utc ?? '—'}</dd>
      <dt>Idle threshold</dt><dd>{status.idle_minutes_threshold} 分</dd>
    </dl>
  {:else}
    <p>loading…</p>
  {/if}
  <div class="actions">
    <button onclick={refreshStatus} disabled={vmActionBusy}>Refresh</button>
    <button onclick={() => vmAction('start')} disabled={vmActionBusy}>Start VM</button>
    <button onclick={() => vmAction('stop')} disabled={vmActionBusy}>Stop VM</button>
  </div>
</section>

<section class="card">
  <h2>Run Command</h2>
  {#if status?.allowed_commands?.length}
    <label>
      Command:
      <select bind:value={selectedCommand}>
        {#each status.allowed_commands as cmd (cmd)}
          <option value={cmd}>{cmd}</option>
        {/each}
      </select>
    </label>
    <button onclick={runCommand} disabled={runBusy}>{runBusy ? 'Running…' : 'Run'}</button>
  {:else}
    <p>使用可能なコマンドが取得できていません。</p>
  {/if}

  {#if runResult}
    <details open>
      <summary>結果</summary>
      <pre>{JSON.stringify(runResult, null, 2)}</pre>
    </details>
  {/if}
</section>

<section class="card">
  <h2>履歴 <small>(直近 30 件)</small></h2>
  <button onclick={loadLogs} disabled={logsBusy}>{logsBusy ? '読み込み中…' : 'Reload'}</button>
  {#if logs.length === 0 && !logsBusy}
    <p>ログがありません。</p>
  {:else}
    <table>
      <thead>
        <tr><th>時刻 (UTC)</th><th>alias</th><th>status</th><th>caller</th></tr>
      </thead>
      <tbody>
        {#each logs as l (l.timestamp_utc + l.alias)}
          <tr>
            <td>{l.timestamp_utc}</td>
            <td>{l.alias}</td>
            <td><span class="badge" data-state={l.status.toLowerCase()}>{l.status}</span></td>
            <td title={l.caller}>{l.caller ? l.caller.slice(0, 8) + '…' : '—'}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  {/if}
</section>

<style>
  .card {
    background: #fff;
    border-radius: 8px;
    padding: 1.25rem 1.5rem;
    margin-bottom: 1rem;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.06);
  }
  h2 { margin-top: 0; font-size: 1.05rem; }
  dl { display: grid; grid-template-columns: max-content 1fr; gap: 0.25rem 1rem; margin: 0.5rem 0; }
  dt { color: #6b7280; }
  .actions { margin-top: 0.75rem; display: flex; gap: 0.5rem; flex-wrap: wrap; }
  button { padding: 0.4rem 0.9rem; border: 1px solid #c0c4cc; background: #fafafa; border-radius: 4px; cursor: pointer; }
  button:disabled { opacity: 0.5; cursor: not-allowed; }
  label { display: inline-flex; align-items: center; gap: 0.5rem; margin-right: 0.75rem; }
  select { padding: 0.3rem; }
  pre { background: #0f172a; color: #e2e8f0; padding: 0.75rem; border-radius: 6px; overflow-x: auto; font-size: 0.8rem; }
  table { width: 100%; border-collapse: collapse; font-size: 0.85rem; margin-top: 0.5rem; }
  th, td { padding: 0.4rem 0.5rem; border-bottom: 1px solid #eef0f3; text-align: left; }
  th { background: #f0f2f5; }
  .badge {
    display: inline-block;
    padding: 0.05rem 0.5rem;
    border-radius: 999px;
    font-size: 0.75rem;
    background: #e5e7eb;
  }
  .badge[data-state='running'], .badge[data-state='ok'] { background: #d1fae5; color: #047857; }
  .badge[data-state='deallocated'], .badge[data-state='stopped'] { background: #fee2e2; color: #b91c1c; }
  .badge[data-state='starting'], .badge[data-state='vm_starting'], .badge[data-state='deallocating'] { background: #fef3c7; color: #92400e; }
  .badge[data-state='error'], .badge[data-state='start_failed'] { background: #fecaca; color: #991b1b; }
  .error { color: #b91c1c; }
</style>
