const API = window.HUB_API_BASE || 'http://localhost:8787';
const installCmd = `git clone https://github.com/connormatthewdouglas/CursiveOS.git 2>/dev/null; git -C ~/CursiveOS pull --ff-only 2>/dev/null || echo "Local changes detected"; chmod +x ~/CursiveOS/cursiveos-full-test-v1.4.sh; cd ~/CursiveOS && bash cursiveos-full-test-v1.4.sh`;

document.getElementById('installCmd').textContent = installCmd;

async function jget(path) {
  const res = await fetch(`${API}${path}`);
  return res.json();
}

async function jpost(path, body) {
  const res = await fetch(`${API}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {})
  });
  return res.json();
}

function rows(id, data, render, colspan = 4) {
  document.getElementById(id).innerHTML = (data || []).map(render).join('') || `<tr><td colspan='${colspan}'>No data</td></tr>`;
}

async function load() {
  const [cycle, machines, ledger, contrib, appeals, balances] = await Promise.all([
    jget('/hub/cycle/latest'),
    jget('/hub/machines'),
    jget('/hub/rewards/ledger?limit=20'),
    jget('/hub/contributions'),
    jget('/hub/governance/appeals'),
    jget('/hub/rewards/balances')
  ]);

  const c = cycle.data;
  document.getElementById('cycleCard').textContent = c
    ? `Cycle: ${c.cycle_id} · Status: ${c.status} · Pool: ${c.pool_close ?? c.pool_open}`
    : 'Cycle: -- · Status: -- · Pool: --';

  rows('machinesBody', machines.data, m => `<tr><td>${m.machine_id}</td><td>${m.plan}</td><td>${m.fast_cycle_fee}</td><td>${m.last_burn_cycle_id ?? '-'}</td></tr>`);
  rows('ledgerBody', ledger.data, e => `<tr><td>${e.event_type}</td><td>${e.bucket}</td><td>${e.amount}</td><td>${e.cycle_id}</td></tr>`);
  rows('contribBody', contrib.data, s => `<tr><td>${s.submission_hash}</td><td>${s.class}</td><td>${s.state}</td><td>${s.verdict ?? '-'}</td></tr>`);
  rows('appealsBody', appeals.data, a => `<tr><td>${a.appeal_id}</td><td>${a.submission_id}</td><td>${a.state}</td><td>${a.deadline_at ?? '-'}</td></tr>`);

  const pool = balances.pool?.incentive_pool_balance ?? '--';
  const burn = balances.pool?.burn_sink_total ?? '--';
  document.getElementById('rewardsSummary').innerHTML = `
    <div class='card'><b>Rail</b><div>internal_credits</div></div>
    <div class='card'><b>Incentive Pool</b><div>${pool}</div></div>
    <div class='card'><b>Burn Sink Total</b><div>${burn}</div></div>
    <div class='card'><b>Cycle Status</b><div>${c?.status ?? '--'}</div></div>
  `;
}

// Actions

document.getElementById('runCycleBtn').addEventListener('click', async () => {
  const cycle_id = Number(document.getElementById('cycleIdInput').value);
  const pool_open = Number(document.getElementById('poolOpenInput').value || 1000);
  const result = await jpost('/hub/cycle/run', { cycle_id, pool_open });
  document.getElementById('runCycleResult').textContent = JSON.stringify(result.data || result, null, 0);
  await load();
});

document.getElementById('setPlanBtn').addEventListener('click', async () => {
  const machineId = document.getElementById('planMachineId').value.trim();
  const plan = document.getElementById('planValue').value;
  const result = await jpost(`/hub/machines/${encodeURIComponent(machineId)}/plan`, { plan });
  document.getElementById('setPlanResult').textContent = result.ok ? 'Plan updated' : `Error: ${result.error}`;
  await load();
});

document.getElementById('createContribBtn').addEventListener('click', async () => {
  const payload = {
    account_id: document.getElementById('contribAccount').value.trim(),
    submission_hash: document.getElementById('contribHash').value.trim(),
    title: document.getElementById('contribTitle').value.trim(),
    class_name: document.getElementById('contribClass').value
  };
  const result = await jpost('/hub/contributions', payload);
  document.getElementById('createContribResult').textContent = result.ok ? 'Submission created/updated' : `Error: ${result.error}`;
  await load();
});

document.getElementById('openAppealBtn').addEventListener('click', async () => {
  const payload = {
    submission_id: document.getElementById('appealSubmissionId').value.trim(),
    opened_by_account_id: document.getElementById('appealAccountId').value.trim(),
    reason: document.getElementById('appealReason').value.trim()
  };
  const result = await jpost('/hub/governance/appeals', payload);
  document.getElementById('openAppealResult').textContent = result.ok ? JSON.stringify(result.data || {}) : `Error: ${result.error}`;
  await load();
});

load().catch(err => {
  document.getElementById('cycleCard').textContent = `API error: ${err.message}`;
});

document.querySelectorAll('#tabs button').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('#tabs button').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    const tab = btn.dataset.tab;
    document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
    document.getElementById(tab).classList.add('active');
  });
});
