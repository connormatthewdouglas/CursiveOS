const API = window.HUB_API_BASE || 'http://localhost:8787';

// ── State ────────────────────────────────────────────────────────────────────
let SESSION_TOKEN = null;
let ACCOUNT_ID    = null;
let ACCOUNT_ROLE  = null;
let USERNAME      = null;
let ALL_ACCOUNTS  = [];
let OPEN_CYCLE_ID = null;
let WALLET_CHALLENGE = null;

// ── API helpers ──────────────────────────────────────────────────────────────
const authH = () => SESSION_TOKEN ? { 'x-session-token': SESSION_TOKEN } : {};

async function api(method, path, body) {
  const opts = {
    method,
    headers: { 'Content-Type': 'application/json', ...authH() },
  };
  if (body !== undefined) opts.body = JSON.stringify(body);
  const r = await fetch(`${API}${path}`, opts);
  return r.json();
}

const get  = path       => api('GET',  path);
const post = (path, b)  => api('POST', path, b || {});

// ── UI helpers ───────────────────────────────────────────────────────────────
function msg(id, text, type = 'ok') {
  const el = document.getElementById(id);
  if (!el) return;
  el.className = `form-msg ${type}`;
  el.textContent = text;
}
function clearMsg(id) {
  const el = document.getElementById(id);
  if (el) { el.className = 'form-msg'; el.textContent = ''; }
}

function shortId(id) { return id ? id.slice(0, 8) + '…' : '–'; }

function friendlyRole(role) {
  return { mixed: 'Admin', validator: 'Validator', contributor: 'Contributor', consumer: 'Fast User' }[role] || role;
}

function accountLabel(a) {
  return a?.username ? `${a.username} (${friendlyRole(a.role)})` : `${friendlyRole(a.role)} · ${shortId(a?.account_id)}`;
}

function badgeHtml(text, cls) {
  return `<span class="badge ${cls}">${text}</span>`;
}

function submissionBadge(state) {
  const map = {
    stake_locked: ['Pending Review', 'badge-review'],
    accepted:     ['Accepted',       'badge-accepted'],
    rejected:     ['Rejected',       'badge-rejected'],
    settled:      ['Settled',        'badge-accepted'],
    pending:      ['Pending',        'badge-pending'],
  };
  const [label, cls] = map[state] || [state, 'badge-pending'];
  return badgeHtml(label, cls);
}

function emptyRow(colspan, icon, text) {
  return `<tr><td colspan="${colspan}">
    <div class="empty-state">
      <div class="empty-icon">${icon}</div>
      <p>${text}</p>
    </div>
  </td></tr>`;
}

function isAdmin()     { return ACCOUNT_ROLE === 'mixed'; }
function isValidator() { return ACCOUNT_ROLE === 'validator' || isAdmin(); }
function isContributor(){ return ACCOUNT_ROLE === 'contributor' || isAdmin(); }

// ── Login Flow ───────────────────────────────────────────────────────────────
async function tryLogin(accountId) {
  const r = await post('/hub/session/create', { account_id: accountId });
  if (!r.ok) throw new Error(r.error === 'account_not_found' ? 'Account not found. Check your ID and try again.' : r.error);
  SESSION_TOKEN = r.session_token;
  ACCOUNT_ID    = accountId;
}

async function loadAccountInfo() {
  const boot = await fetch(`${API}/hub/session/bootstrap`).then(r => r.json());
  ALL_ACCOUNTS = boot.accounts || [];
  const mine = ALL_ACCOUNTS.find(a => a.account_id === ACCOUNT_ID);
  ACCOUNT_ROLE = mine?.role || null;
  USERNAME     = mine?.username || null;
}

function saveSession() {
  localStorage.setItem('hub_account_id', ACCOUNT_ID);
}

function clearSession() {
  SESSION_TOKEN = null; ACCOUNT_ID = null; ACCOUNT_ROLE = null; USERNAME = null;
  localStorage.removeItem('hub_account_id');
}

async function bootApp() {
  await loadAccountInfo();
  renderHeader();
  renderNav();
  await loadBalance();
  await loadPanel('overview');
  document.getElementById('loginScreen').style.display = 'none';
  document.getElementById('app').style.display = 'block';
}

// ── Header ───────────────────────────────────────────────────────────────────
function renderHeader() {
  const name = USERNAME || friendlyRole(ACCOUNT_ROLE);
  document.getElementById('userName').textContent = name;
  document.getElementById('userAvatar').textContent = (name[0] || '?').toUpperCase();

  const roleMap = {
    mixed: ['Admin', 'rb-admin'],
    validator: ['Validator', 'rb-validator'],
    contributor: ['Contributor', 'rb-contributor'],
    consumer: ['Fast User', 'rb-consumer'],
  };
  const [label, cls] = roleMap[ACCOUNT_ROLE] || [ACCOUNT_ROLE, 'rb-consumer'];
  const badge = document.getElementById('userRoleBadge');
  badge.textContent = label;
  badge.className = `role-badge ${cls}`;
}

// ── Nav ───────────────────────────────────────────────────────────────────────
const NAV_ITEMS = [
  { id: 'overview',  label: 'Overview',     roles: ['mixed','validator','contributor','consumer'] },
  { id: 'submit',    label: 'Submit Work',  roles: ['contributor','mixed'] },
  { id: 'vote',      label: 'Vote',         roles: ['validator','mixed'] },
  { id: 'pool',      label: 'Pool',         roles: ['mixed','validator','contributor','consumer'] },
  { id: 'earnings',  label: 'Earnings',     roles: ['mixed','validator','contributor','consumer'] },
  { id: 'settings',  label: 'Settings',     roles: ['mixed','validator','contributor','consumer'] },
  { id: 'admin',     label: 'Admin',        roles: ['mixed'] },
];

function renderNav() {
  const nav = document.getElementById('appNav');
  const visible = NAV_ITEMS.filter(n => n.roles.includes(ACCOUNT_ROLE));
  nav.innerHTML = visible.map(n =>
    `<button data-panel="${n.id}" class="${n.id === 'overview' ? 'active' : ''}">${n.label}</button>`
  ).join('');
  nav.querySelectorAll('button').forEach(btn => {
    btn.addEventListener('click', () => switchPanel(btn.dataset.panel));
  });
}

// ── Panel switching ───────────────────────────────────────────────────────────
let activePanel = 'overview';

async function switchPanel(id) {
  document.querySelectorAll('#appNav button').forEach(b => b.classList.toggle('active', b.dataset.panel === id));
  document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
  document.getElementById(`panel-${id}`)?.classList.add('active');
  activePanel = id;
  await loadPanel(id);
}

async function loadPanel(id) {
  switch (id) {
    case 'overview':  return loadOverview();
    case 'submit':    return loadSubmissions();
    case 'vote':      return loadVote();
    case 'pool':      return loadPool();
    case 'earnings':  return loadEarnings();
    case 'settings':  return loadSettings();
    case 'admin':     return loadAdmin();
  }
}

// ── Balance strip ─────────────────────────────────────────────────────────────
async function loadBalance() {
  try {
    const b = await get('/hub/rewards/my-balance');
    const strip = document.getElementById('balanceStrip');
    if (b.ok && Number(b.balance_btc) > 0) {
      strip.style.display = 'flex';
      strip.innerHTML = `
        <span class="bl">Balance</span>
        <span class="bv">${Number(b.balance_btc).toFixed(8)} BTC</span>
        <span class="bl">~$${b.balance_usd}</span>
        <div class="bs"></div>
        <span class="bl">Total earned</span>
        <span class="bv">${Number(b.total_earned_btc).toFixed(8)} BTC</span>
        <span class="bl">~$${b.total_earned_usd}</span>`;
    } else {
      strip.style.display = 'none';
    }
  } catch (_) {}
}

// ── Overview ──────────────────────────────────────────────────────────────────
async function loadOverview() {
  const [poolData, contrib, balance, lifetime] = await Promise.all([
    get('/hub/pool/state').catch(() => ({})),
    get('/hub/contributions').catch(() => ({ data: [] })),
    get('/hub/rewards/my-balance').catch(() => ({})),
    get('/hub/contributors/lifetime-votes').catch(() => ({})),
  ]);

  const cur = poolData.current_cycle;
  if (cur?.status === 'open') OPEN_CYCLE_ID = cur.cycle_id;

  const greet = USERNAME ? `Hey, ${USERNAME}.` : 'Welcome.';
  document.getElementById('overviewHeading').textContent = greet;

  const myLifetime = lifetime.data?.find(r => r.account_id === ACCOUNT_ID);
  const btcPrice = cur?.btc_price_usd || 85000;

  let content = '';

  // ── Cycle status banner
  if (cur) {
    const isOpen = cur.status === 'open';
    content += `<div class="cta-banner ${isOpen ? 'green' : ''}">
      <div class="cta-text">
        <h3>${isOpen ? `Cycle ${cur.cycle_id} is open` : `Cycle ${cur.cycle_id} is closed`}</h3>
        <p>${isOpen
          ? `Payout pot: ${Number(cur.payout_pot_btc).toFixed(8)} BTC (~$${(Number(cur.payout_pot_btc)*btcPrice).toFixed(2)}) · Pool: $${(Number(cur.pool_principal_btc)*btcPrice).toFixed(0)} locked`
          : 'No open cycle. The admin will open a new one soon.'
        }</p>
      </div>
      ${isOpen && isValidator() ? `<button class="btn-primary" onclick="switchPanel('vote')">Go Vote →</button>` : ''}
      ${isOpen && isContributor() ? `<button class="btn-primary green" onclick="switchPanel('submit')">Submit Work →</button>` : ''}
    </div>`;
  } else {
    content += `<div class="cta-banner"><div class="cta-text"><h3>No cycles yet</h3><p>The admin hasn't opened a cycle yet.</p></div></div>`;
  }

  // ── Stats row
  const balanceBtc = Number(balance.balance_btc || 0);
  const totalEarned = Number(balance.total_earned_btc || 0);
  const ltvShare   = myLifetime?.lifetime_share_pct || '0.00';
  const poolUsd    = cur ? (Number(cur.pool_principal_btc) * btcPrice).toFixed(0) : '0';

  content += `<div class="stats-row">
    <div class="stat-card sc-green">
      <div class="stat-label">Your Balance</div>
      <div class="stat-value">${balanceBtc.toFixed(8)}</div>
      <div class="stat-sub">BTC · ~$${(balanceBtc * btcPrice).toFixed(2)}</div>
    </div>
    <div class="stat-card sc-blue">
      <div class="stat-label">Total Earned</div>
      <div class="stat-value">${totalEarned.toFixed(8)}</div>
      <div class="stat-sub">BTC all time</div>
    </div>
    <div class="stat-card sc-purple">
      <div class="stat-label">Pool Size</div>
      <div class="stat-value">$${poolUsd}</div>
      <div class="stat-sub">locked principal</div>
    </div>
    <div class="stat-card sc-amber">
      <div class="stat-label">Your Yield Share</div>
      <div class="stat-value">${ltvShare}%</div>
      <div class="stat-sub">of pool yield, forever</div>
    </div>
  </div>`;

  // ── Role-specific action section
  if (isAdmin()) {
    content += `<p class="section-label">Quick Actions</p>
    <div style="display:flex;gap:10px;flex-wrap:wrap">
      <button class="btn-primary" onclick="switchPanel('admin')">Open / Close Cycle</button>
      <button class="btn-primary" style="background:var(--surface2);border:1px solid var(--border);color:var(--text2)" onclick="switchPanel('pool')">View Pool</button>
    </div>`;
  }

  if (isValidator() && !isAdmin()) {
    const myVote = ''; // could check if already voted this cycle
    content += `<p class="section-label">Your Role</p>
    <div class="cta-banner blue">
      <div class="cta-text">
        <h3>You're a Validator</h3>
        <p>When a cycle is open, go to Vote and distribute your 100 points across accepted submissions. Validators who vote get a full refund of their $2 fee.</p>
      </div>
      ${OPEN_CYCLE_ID ? `<button class="btn-primary" onclick="switchPanel('vote')">Go Vote →</button>` : ''}
    </div>`;
  }

  if (isContributor() && !isAdmin()) {
    const mySubmissions = (contrib.data || []).filter(s => s.account_id === ACCOUNT_ID);
    const pending = mySubmissions.filter(s => s.state === 'stake_locked').length;
    const accepted = mySubmissions.filter(s => s.state === 'accepted').length;
    content += `<p class="section-label">Your Contributions</p>
    <div class="cta-banner">
      <div class="cta-text">
        <h3>${mySubmissions.length} submission${mySubmissions.length !== 1 ? 's' : ''}</h3>
        <p>${accepted} accepted · ${pending} pending review${myLifetime ? ` · ${myLifetime.lifetime_votes} lifetime votes` : ''}</p>
      </div>
      <button class="btn-primary green" onclick="switchPanel('submit')">Submit Work →</button>
    </div>`;
  }

  document.getElementById('overviewContent').innerHTML = content;
  document.getElementById('overviewSub').textContent =
    `${friendlyRole(ACCOUNT_ROLE)} · ${ACCOUNT_ID ? shortId(ACCOUNT_ID) : ''}`;
}

// ── Submissions ───────────────────────────────────────────────────────────────
async function loadSubmissions() {
  const c = await get('/hub/contributions').catch(() => ({ data: [] }));
  const mine = (c.data || []).filter(s => s.account_id === ACCOUNT_ID);
  const tbody = document.getElementById('submitHistory');
  if (!mine.length) {
    tbody.innerHTML = emptyRow(4, '📝', 'No submissions yet. Share your first improvement above.');
    return;
  }
  tbody.innerHTML = mine.map(s => `<tr>
    <td>
      <strong style="font-size:13px">${s.title}</strong>
      ${s.description ? `<div style="font-size:12px;color:var(--text3);margin-top:2px">${s.description.slice(0,100)}${s.description.length>100?'…':''}</div>` : ''}
    </td>
    <td class="td-dim">${s.class}</td>
    <td>${submissionBadge(s.state)}</td>
    <td style="text-align:right">${s.verdict ? `<span style="color:var(--text2);font-size:12px">${s.verdict}</span>` : '–'}</td>
  </tr>`).join('');
}

document.getElementById('submitBtn').addEventListener('click', async () => {
  const title = document.getElementById('submitTitle').value.trim();
  const description = document.getElementById('submitDescription').value.trim();
  const hash = document.getElementById('submitHash').value.trim();
  const class_name = document.getElementById('submitType').value;

  clearMsg('submitMsg');
  if (!title) { msg('submitMsg', 'Give your submission a title.', 'err'); return; }
  if (!description) { msg('submitMsg', 'Add a description so validators know what to review.', 'err'); return; }

  const btn = document.getElementById('submitBtn');
  btn.disabled = true; btn.textContent = 'Submitting…';
  try {
    const r = await post('/hub/contributions', { title, description, submission_hash: hash || undefined, class_name });
    if (r.ok) {
      msg('submitMsg', 'Submitted! Validators will review it soon.', 'ok');
      document.getElementById('submitTitle').value = '';
      document.getElementById('submitDescription').value = '';
      document.getElementById('submitHash').value = '';
      await loadSubmissions();
    } else {
      msg('submitMsg', r.error || 'Something went wrong.', 'err');
    }
  } catch (e) { msg('submitMsg', e.message, 'err'); }
  finally { btn.disabled = false; btn.textContent = 'Submit for Review'; }
});

// ── Vote ──────────────────────────────────────────────────────────────────────
async function loadVote() {
  const el = document.getElementById('voteContent');
  el.innerHTML = `<div class="empty-state"><div class="spinner"></div></div>`;

  const [pool, contrib] = await Promise.all([
    get('/hub/pool/state').catch(() => ({})),
    get('/hub/contributions').catch(() => ({ data: [] })),
  ]);

  const cur = pool.current_cycle;
  if (cur?.status === 'open') OPEN_CYCLE_ID = cur.cycle_id;

  if (!OPEN_CYCLE_ID || !cur || cur.status !== 'open') {
    el.innerHTML = `<div class="empty-state">
      <div class="empty-icon">🗳️</div>
      <p class="hint">No open cycle right now.</p>
      <p>Come back when the admin opens a new cycle.</p>
    </div>`;
    return;
  }

  const accepted = (contrib.data || []).filter(s => s.state === 'accepted' || s.state === 'stake_locked');
  if (!accepted.length) {
    el.innerHTML = `<div class="cta-banner amber"><div class="cta-text">
      <h3>Cycle ${OPEN_CYCLE_ID} is open</h3>
      <p>No accepted submissions yet. Wait for the admin to accept contributions before voting.</p>
    </div></div>`;
    return;
  }

  const btcPrice = cur.btc_price_usd || 85000;
  el.innerHTML = `
    <div class="cta-banner green">
      <div class="cta-text">
        <h3>Cycle ${OPEN_CYCLE_ID} — ${accepted.length} submission${accepted.length!==1?'s':''} to review</h3>
        <p>Payout pot: ${Number(cur.payout_pot_btc).toFixed(8)} BTC (~$${(Number(cur.payout_pot_btc)*btcPrice).toFixed(2)})</p>
      </div>
    </div>
    <div class="form-section">
      <h3>Allocate Your 100 Points</h3>
      <p style="color:var(--text2);font-size:13px;margin-bottom:16px">
        You don't have to use all 100 points. Any submission getting less than 1% of total votes won't receive a payout.
      </p>
      <div id="voteRows">${accepted.map(s => `
        <div class="vote-row">
          <div class="vote-info">
            <strong>${s.title}</strong>
            <span>${s.class}${s.submission_hash && !s.submission_hash.startsWith('auto:') ? ` · <code>${s.submission_hash.slice(0,12)}</code>` : ''}</span>
            ${s.description ? `<div class="vote-desc">${s.description.slice(0,160)}${s.description.length>160?'…':''}</div>` : ''}
          </div>
          <input type="number" class="vote-input" data-subid="${s.submission_id}" min="0" max="100" step="1" value="0" />
          <span style="color:var(--text3);font-size:12px">pts</span>
        </div>`).join('')}
      </div>
      <div class="vote-budget-row">
        <span>Points used</span>
        <span class="vote-budget-num" id="voteBudgetNum">0 / 100</span>
      </div>
      <div class="vote-bar"><div class="vote-bar-fill" id="voteBudgetFill" style="width:0%"></div></div>
      <button class="btn-primary" id="submitVoteBtn">Submit Vote</button>
      <div class="form-msg" id="voteMsg"></div>
    </div>`;

  document.querySelectorAll('.vote-input').forEach(inp => inp.addEventListener('input', updateVoteBudget));
  document.getElementById('submitVoteBtn').addEventListener('click', submitVote);
}

function updateVoteBudget() {
  const inputs = document.querySelectorAll('.vote-input');
  const used = Array.from(inputs).reduce((s, i) => s + Number(i.value || 0), 0);
  const numEl = document.getElementById('voteBudgetNum');
  const fillEl = document.getElementById('voteBudgetFill');
  if (numEl) numEl.textContent = `${used} / 100`;
  if (numEl) numEl.className = `vote-budget-num${used > 100 ? ' over' : ''}`;
  if (fillEl) {
    fillEl.style.width = `${Math.min(used, 100)}%`;
    fillEl.className = `vote-bar-fill${used > 100 ? ' over' : ''}`;
  }
}

async function submitVote() {
  const inputs = document.querySelectorAll('.vote-input');
  const allocations = Array.from(inputs)
    .map(i => ({ submission_id: i.dataset.subid, points: Number(i.value || 0) }))
    .filter(a => a.points > 0);
  const total = allocations.reduce((s, a) => s + a.points, 0);
  if (total > 100.001) { msg('voteMsg', `Total is ${total} — reduce to 100 or less.`, 'err'); return; }
  if (!allocations.length) { msg('voteMsg', 'Allocate at least some points before submitting.', 'err'); return; }

  const btn = document.getElementById('submitVoteBtn');
  btn.disabled = true; btn.textContent = 'Submitting…';
  try {
    const r = await post('/hub/contributions/votes', { cycle_id: OPEN_CYCLE_ID, allocations });
    if (r.ok) msg('voteMsg', `Vote submitted. You used ${r.total_points_used} of 100 points.`, 'ok');
    else      msg('voteMsg', r.error || 'Error submitting vote.', 'err');
  } catch (e) { msg('voteMsg', e.message, 'err'); }
  finally { btn.disabled = false; btn.textContent = 'Submit Vote'; }
}

// ── Pool ──────────────────────────────────────────────────────────────────────
async function loadPool() {
  const [state, hist] = await Promise.all([
    get('/hub/pool/state').catch(() => ({})),
    get('/hub/pool/cycles').catch(() => ({ data: [] })),
  ]);

  const cur = state.current_cycle;
  const cfg = state.config || {};
  if (cur?.status === 'open') OPEN_CYCLE_ID = cur.cycle_id;
  const bp = cur?.btc_price_usd || 85000;

  const statsEl = document.getElementById('poolStats');
  statsEl.innerHTML = `
    <div class="stat-card sc-purple">
      <div class="stat-label">Pool Principal</div>
      <div class="stat-value">$${cur ? (Number(cur.pool_principal_btc)*bp).toFixed(0) : '–'}</div>
      <div class="stat-sub">${cur ? Number(cur.pool_principal_btc).toFixed(8)+' BTC locked' : 'no cycles yet'}</div>
    </div>
    <div class="stat-card sc-blue">
      <div class="stat-label">Payout Pot</div>
      <div class="stat-value">${cur ? Number(cur.payout_pot_btc).toFixed(8) : '–'}</div>
      <div class="stat-sub">BTC this cycle</div>
    </div>
    <div class="stat-card sc-amber">
      <div class="stat-label">Cycle Yield</div>
      <div class="stat-value">${cur ? Number(cur.cycle_yield_btc).toFixed(8) : '–'}</div>
      <div class="stat-sub">BTC this cycle</div>
    </div>
    <div class="stat-card sc-green">
      <div class="stat-label">Effective Yield</div>
      <div class="stat-value">${cfg.effective_per_cycle_yield ? (cfg.effective_per_cycle_yield*100).toFixed(3)+'%' : '0.27%'}</div>
      <div class="stat-sub">per cycle (~3.25% annual)</div>
    </div>`;

  const cycles = hist.data || (cur ? [cur] : []);
  const tbody = document.getElementById('poolHistory');
  if (!cycles.length) {
    tbody.innerHTML = emptyRow(7, '🌊', 'No cycles run yet.');
    return;
  }
  tbody.innerHTML = cycles.map(r => `<tr>
    <td>${r.cycle_id}</td>
    <td>${r.fast_user_count}</td>
    <td>$${Number(r.fast_revenue_usd).toFixed(2)}</td>
    <td class="td-dim">${Number(r.payout_pot_btc).toFixed(8)}</td>
    <td class="td-dim">${Number(r.pool_principal_btc).toFixed(8)}</td>
    <td class="td-dim">${Number(r.cycle_yield_btc).toFixed(8)}</td>
    <td>${badgeHtml(r.status, r.status==='open' ? 'badge-open' : 'badge-closed')}</td>
  </tr>`).join('');
}

// ── Earnings ──────────────────────────────────────────────────────────────────
async function loadEarnings() {
  const [balance, lifetime, ledger] = await Promise.all([
    get('/hub/rewards/my-balance').catch(() => ({})),
    get('/hub/contributors/lifetime-votes').catch(() => ({ data: [] })),
    get('/hub/rewards/ledger?limit=20').catch(() => ({ data: [] })),
  ]);

  const btcPrice = Number(process?.env?.BTC_PRICE_USD || 85000);
  const balBtc   = Number(balance.balance_btc || 0);
  const earnedBtc= Number(balance.total_earned_btc || 0);
  const allLTV   = Number(lifetime.all_lifetime_votes || 0);
  const mine     = lifetime.data?.find(r => r.account_id === ACCOUNT_ID);

  document.getElementById('earningsStats').innerHTML = `
    <div class="stat-card sc-green">
      <div class="stat-label">Balance</div>
      <div class="stat-value">${balBtc.toFixed(8)}</div>
      <div class="stat-sub">BTC · ~$${(balBtc*85000).toFixed(2)}</div>
    </div>
    <div class="stat-card sc-blue">
      <div class="stat-label">Total Earned</div>
      <div class="stat-value">${earnedBtc.toFixed(8)}</div>
      <div class="stat-sub">BTC all time</div>
    </div>
    <div class="stat-card sc-purple">
      <div class="stat-label">Lifetime Votes</div>
      <div class="stat-value">${mine ? Number(mine.lifetime_votes).toFixed(0) : '0'}</div>
      <div class="stat-sub">of ${allLTV.toFixed(0)} total</div>
    </div>
    <div class="stat-card sc-amber">
      <div class="stat-label">Yield Share</div>
      <div class="stat-value">${mine?.lifetime_share_pct || '0.00'}%</div>
      <div class="stat-sub">permanent royalty share</div>
    </div>`;

  const acctMap = Object.fromEntries(ALL_ACCOUNTS.map(a => [a.account_id, a.username || friendlyRole(a.role)]));
  const ltvTbody = document.getElementById('earningsLedger');
  const ltvRows = lifetime.data || [];
  ltvTbody.innerHTML = ltvRows.length
    ? ltvRows.map(r => `<tr ${r.account_id === ACCOUNT_ID ? 'style="background:rgba(91,141,239,.06)"' : ''}>
        <td><strong>${acctMap[r.account_id] || shortId(r.account_id)}</strong>
          ${r.account_id === ACCOUNT_ID ? ' <span style="font-size:11px;color:var(--blue)">(you)</span>' : ''}</td>
        <td>${Number(r.lifetime_votes).toFixed(1)}</td>
        <td>${r.lifetime_share_pct}%</td>
        <td class="td-dim">${Number(r.total_payout_btc||0).toFixed(8)}</td>
        <td class="td-dim">${Number(r.total_royalty_btc||0).toFixed(8)}</td>
      </tr>`).join('')
    : emptyRow(5, '📊', 'No contributors yet.');

  const eventLabels = {
    test_dispense:       'Test funds added',
    fast_burn:           'Fast plan fee',
    contributor_payout:  'Contribution payout',
    contributor_royalty: 'Yield royalty',
  };
  const histTbody = document.getElementById('earningsHistory');
  const histRows = ledger.data || [];
  histTbody.innerHTML = histRows.length
    ? histRows.map(e => `<tr>
        <td>${eventLabels[e.event_type] || e.event_type}</td>
        <td class="td-dim">${Number(e.amount).toFixed(8)} BTC</td>
        <td class="td-dim">${e.cycle_id || '–'}</td>
      </tr>`).join('')
    : emptyRow(3, '📋', 'No activity yet.');
}

// ── Settings ──────────────────────────────────────────────────────────────────
function loadSettings() {
  document.getElementById('settingsAccountId').textContent = ACCOUNT_ID || '';
  if (USERNAME) document.getElementById('settingsUsername').value = USERNAME;
  document.getElementById('settingsInstallCmd').textContent =
    `git clone https://github.com/connormatthewdouglas/CursiveOS.git 2>/dev/null\ngit -C ~/CursiveOS pull --ff-only 2>/dev/null\nchmod +x ~/CursiveOS/cursiveos-full-test-v1.4.sh\nbash ~/CursiveOS/cursiveos-full-test-v1.4.sh`;
}

document.getElementById('settingsUsernameBtn').addEventListener('click', async () => {
  const username = document.getElementById('settingsUsername').value.trim();
  if (!username) { msg('settingsUsernameMsg', 'Enter a name first.', 'err'); return; }
  const r = await post('/hub/accounts/username', { username });
  if (r.ok) {
    USERNAME = r.username;
    renderHeader();
    msg('settingsUsernameMsg', `Name saved as "${r.username}".`, 'ok');
  } else {
    msg('settingsUsernameMsg', r.error || 'Error saving name.', 'err');
  }
});

document.getElementById('settingsBindWalletBtn').addEventListener('click', async () => {
  const wallet_address = document.getElementById('settingsWalletAddress').value.trim();
  const chain_id = document.getElementById('settingsWalletChain').value.trim() || 'evm:1';
  if (!wallet_address) { msg('settingsBindMsg', 'Enter your wallet address.', 'err'); return; }
  const r = await post('/hub/identity/wallet/bind', { account_id: ACCOUNT_ID, wallet_address, chain_id });
  msg('settingsBindMsg', r.ok ? 'Wallet saved. Now generate a challenge and verify.' : r.error || 'Error.', r.ok ? 'ok' : 'err');
});

document.getElementById('settingsChallengeBtn').addEventListener('click', async () => {
  const r = await post('/hub/identity/wallet/challenge', { account_id: ACCOUNT_ID });
  if (r.ok) {
    WALLET_CHALLENGE = r;
    const el = document.getElementById('settingsChallengeText');
    el.textContent = r.message;
    el.style.display = 'block';
    msg('settingsVerifyMsg', 'Sign this exact message with your wallet app, then paste the signature below.', 'info');
  } else {
    msg('settingsVerifyMsg', r.error || 'Error generating challenge.', 'err');
  }
});

document.getElementById('settingsVerifyBtn').addEventListener('click', async () => {
  const signature = document.getElementById('settingsSignature').value.trim();
  if (!signature) { msg('settingsVerifyMsg', 'Paste your signed message first.', 'err'); return; }
  if (!WALLET_CHALLENGE?.nonce) { msg('settingsVerifyMsg', 'Generate a challenge first.', 'err'); return; }
  const r = await post('/hub/identity/wallet/verify', { account_id: ACCOUNT_ID, signature });
  if (r.ok) {
    msg('settingsVerifyMsg', 'Wallet verified. You can now receive payouts.', 'ok');
    document.getElementById('settingsSignature').value = '';
  } else {
    msg('settingsVerifyMsg', r.error || 'Verification failed.', 'err');
  }
});

// ── Admin ─────────────────────────────────────────────────────────────────────
function loadAdmin() {
  // Populate account selects
  const opts = ALL_ACCOUNTS
    .filter(a => a.account_id !== ACCOUNT_ID)
    .map(a => `<option value="${a.account_id}">${accountLabel(a)}</option>`)
    .join('');
  ['adminDispenseAccount','adminControlAccount','adminDeleteAccount'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.innerHTML = opts;
  });

  // Auto-fill cycle IDs
  if (OPEN_CYCLE_ID) {
    const cid = document.getElementById('adminCycleId');
    if (cid && !cid.value) cid.value = OPEN_CYCLE_ID;
    const ccid = document.getElementById('adminCloseCycleId');
    if (ccid && !ccid.value) ccid.value = OPEN_CYCLE_ID;
  }
}

document.getElementById('adminOpenCycleBtn').addEventListener('click', async () => {
  const cycle_id     = Number(document.getElementById('adminCycleId').value);
  const fast_user_count = Number(document.getElementById('adminFastUsers').value || 5);
  const btcPrice     = document.getElementById('adminBtcPrice').value;
  if (!cycle_id) { msg('adminOpenMsg', 'Enter a cycle number.', 'err'); return; }
  const body = { cycle_id, fast_user_count };
  if (btcPrice) body.btc_price_usd = Number(btcPrice);
  const r = await post('/hub/cycle/run-v31', body);
  if (r.ok) {
    OPEN_CYCLE_ID = r.cycle_id;
    msg('adminOpenMsg', `Cycle ${r.cycle_id} opened. Revenue: $${r.fast_revenue_usd} · Pot: ${r.payout_pot_btc} BTC · Pool: ${r.pool_principal_btc} BTC`, 'ok');
  } else {
    msg('adminOpenMsg', r.error || 'Error.', 'err');
  }
});

document.getElementById('adminCloseCycleBtn').addEventListener('click', async () => {
  const cycle_id = Number(document.getElementById('adminCloseCycleId').value);
  if (!cycle_id) { msg('adminCloseMsg', 'Enter the cycle number to close.', 'err'); return; }
  const r = await post('/hub/cycle/close-v31', { cycle_id });
  if (r.ok) {
    msg('adminCloseMsg', `Cycle ${r.cycle_id} settled. ${r.qualifying_submissions} qualifying submissions, ${r.total_cycle_votes} total votes.`, 'ok');
    const lines = (r.payouts||[]).map(p =>
      `${shortId(p.account_id)}  ${p.vote_share_pct}% vote share → ${p.payout_btc} BTC payout${Number(p.royalty_btc)>0?` + ${p.royalty_btc} BTC yield`:''}`
    ).join('\n');
    const pre = document.getElementById('adminCloseResult');
    pre.textContent = lines || '(no qualifying submissions)';
    pre.style.display = 'block';
    OPEN_CYCLE_ID = null;
  } else {
    msg('adminCloseMsg', r.error || 'Error.', 'err');
  }
});

document.getElementById('adminDispenseBtn').addEventListener('click', async () => {
  const account_id  = document.getElementById('adminDispenseAccount').value;
  const amount_usd  = Number(document.getElementById('adminDispenseAmount').value);
  if (!account_id || !amount_usd) { msg('adminDispenseMsg', 'Select an account and enter an amount.', 'err'); return; }
  const r = await post('/hub/admin/dispense', { account_id, amount_usd });
  msg('adminDispenseMsg', r.ok ? `Done. Added $${r.dispensed_usd} → ${r.dispensed_btc} BTC` : r.error||'Error.', r.ok ? 'ok' : 'err');
});

document.getElementById('adminSetControlBtn').addEventListener('click', async () => {
  const account_id   = document.getElementById('adminControlAccount').value;
  const control_mode = document.getElementById('adminControlMode').value;
  const reason       = document.getElementById('adminControlReason').value.trim() || null;
  const r = await post('/hub/admin/account-controls/set', { account_id, control_mode, reason });
  msg('adminControlMsg', r.ok ? `Updated to: ${control_mode}` : r.error||'Error.', r.ok ? 'ok' : 'err');
});

document.getElementById('adminDeleteAccountBtn').addEventListener('click', async () => {
  const account_id = document.getElementById('adminDeleteAccount').value;
  if (!account_id) return;
  const a = ALL_ACCOUNTS.find(x => x.account_id === account_id);
  if (!confirm(`Delete ${accountLabel(a||{account_id})}? This cannot be undone.`)) return;
  const r = await post('/hub/admin/accounts/delete', { account_id });
  if (r.ok) {
    msg('adminDeleteMsg', 'Account deleted.', 'ok');
    ALL_ACCOUNTS = ALL_ACCOUNTS.filter(a => a.account_id !== account_id);
    loadAdmin();
  } else {
    msg('adminDeleteMsg', r.error||'Error.', 'err');
  }
});

// ── Sign Out ──────────────────────────────────────────────────────────────────
document.getElementById('signOutBtn').addEventListener('click', () => {
  clearSession();
  document.getElementById('app').style.display = 'none';
  document.getElementById('loginScreen').style.display = 'flex';
  document.getElementById('loginAccountId').value = '';
  clearMsg('loginError');
});

// ── Login Screen Events ───────────────────────────────────────────────────────
document.getElementById('showCreatePath').addEventListener('click', () => {
  document.getElementById('loginPath').style.display = 'none';
  document.getElementById('createPath').style.display = 'block';
});

document.getElementById('showLoginPath').addEventListener('click', () => {
  document.getElementById('createPath').style.display = 'none';
  document.getElementById('loginPath').style.display = 'block';
});

document.getElementById('loginBtn').addEventListener('click', async () => {
  const id = document.getElementById('loginAccountId').value.trim();
  if (!id) { document.getElementById('loginError').textContent = 'Paste your account ID first.'; return; }
  const btn = document.getElementById('loginBtn');
  btn.disabled = true; btn.textContent = 'Signing in…';
  try {
    await tryLogin(id);
    saveSession();
    await bootApp();
  } catch (e) {
    document.getElementById('loginError').textContent = e.message;
  } finally {
    btn.disabled = false; btn.textContent = 'Sign In';
  }
});

document.getElementById('loginAccountId').addEventListener('keydown', e => {
  if (e.key === 'Enter') document.getElementById('loginBtn').click();
});

document.getElementById('createBtn').addEventListener('click', async () => {
  const name = document.getElementById('signupName').value.trim();
  const role = document.getElementById('signupRole').value;
  if (!name) { document.getElementById('createError').textContent = 'Enter a name or handle.'; return; }
  const btn = document.getElementById('createBtn');
  btn.disabled = true; btn.textContent = 'Creating…';
  try {
    const r = await fetch(`${API}/hub/accounts/create`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ role, label: name }),
    }).then(res => res.json());
    if (!r.ok) throw new Error(r.error || 'Could not create account.');
    await tryLogin(r.account_id);
    saveSession();
    await bootApp();
  } catch (e) {
    document.getElementById('createError').textContent = e.message;
  } finally {
    btn.disabled = false; btn.textContent = 'Create Account';
  }
});

// ── Init ──────────────────────────────────────────────────────────────────────
(async () => {
  const saved = localStorage.getItem('hub_account_id');
  if (saved) {
    try {
      await tryLogin(saved);
      await bootApp();
      return;
    } catch (_) {
      clearSession();
    }
  }
  // Show login screen
  document.getElementById('loginScreen').style.display = 'flex';
})();
