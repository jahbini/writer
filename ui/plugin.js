// writer/ui/plugin.js — browser-side plugin served to the shared
// pipeline UI as /api/writer/ui.js. Loaded once per page when
// /api/status returns controls.ui_plugin === 'writer'.
//
// Migrates these writer-only features off the forked index.html:
//   • Certificate panel (reads/writes /api/certificate)
//   • Storacle Observations list + Save-Observation button
//     (reads/writes /api/storacle_observations, /api/storacle_observation)
//   • env_overrides badge in the Pipe controls panel
//
// All DOM is injected into the shared seam slots; the shared refresh()
// loop is unaware of these features. A 2 s plugin-local poll drives
// certificate + storacle refreshes.
//
// Contract (see pipeline/ui/index.html, REFACTOR_UI.md):
//   init(ctx)                                — one-shot after first /api/status
//   decorateArtifact(name, nodeEl, ctx)      — artifact-node overrides
//   decorateFileModal(path, fileMeta, textEl) — modal body override
//   renderDynamicPanel(key, target, value)    — dynamic-panel override
//   pipeSelectPrefixOptions()                 — pipe-select prefix HTML

(function () {
  const byId = (id) => document.getElementById(id);
  const escapeHtml = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));

  // ── env_overrides badge ──────────────────────────────────────────
  // The shared UI rewrites #pipe-current on each /api/status tick.
  // We hitch to that via MutationObserver so the badge stays fresh
  // without touching shared refresh(). Reads window.__lastStatus
  // (the shared seam's stash) rather than the writer-fork's
  // window._lastStatus.
  function paintEnvOverrides() {
    const slot = byId('pipe-plugin-slot');
    if (!slot) return;
    let envEl = byId('pipe-env-overrides');
    if (!envEl) {
      envEl = document.createElement('div');
      envEl.id = 'pipe-env-overrides';
      envEl.style.cssText = 'font-size:0.85em;margin-top:4px;';
      slot.appendChild(envEl);
    }
    const env = (window.__lastStatus && window.__lastStatus.env_overrides) || {};
    const keys = Object.keys(env);
    if (keys.length) {
      envEl.innerHTML = 'env: ' + keys.map(k =>
        `<span style="background:#eef;color:#049;border:1px solid #ccd;border-radius:3px;padding:1px 6px;margin-right:4px;font-family:monospace;">${escapeHtml(k)}=${escapeHtml(env[k])}</span>`
      ).join('');
    } else {
      envEl.innerHTML = '';
    }
  }
  function wireEnvOverridesObserver() {
    const target = byId('pipe-current');
    if (!target) return;
    new MutationObserver(paintEnvOverrides).observe(target, {
      childList: true, characterData: true, subtree: true,
    });
    paintEnvOverrides();
  }

  // ── Certificate panel ────────────────────────────────────────────
  // Human-administered acceptance test for the pipe's current storacle.
  // Puppeteer's certificate_scan_ite consumes the written cert on its
  // next tick. Same contract as the writer-fork version — writer's
  // /api/certificate GET/POST endpoints are preserved by project.coffee.
  const CERT_PANEL_HTML = `
    <section class="panel" id="certificate-panel">
      <h2>Certificate</h2>
      <div id="certificate-status" class="hint mono"></div>
      <div id="certificate-body" style="margin-top:8px;">
        <div class="hint">loading…</div>
      </div>
    </section>
  `;

  async function refreshCertificate() {
    const body = byId('certificate-body');
    const statusEl = byId('certificate-status');
    if (!body) return;
    // Never clobber unsaved typing.
    const active = document.activeElement;
    if (active && (active.id === 'certificate-comments' || active.id === 'certificate-verdict')) return;
    try {
      const resp = await fetch('/api/certificate', { cache: 'no-store' });
      const data = await resp.json();
      if (!data.ok) throw new Error(data.error || 'certificate fetch failed');
      statusEl.textContent = `pipe=${data.pipe} · state=${data.state} · stage=${data.stage}`;
      if (!data.storacle_present) {
        body.innerHTML = '<div class="hint" style="color:#c60;">⚠ no storacle output in <code>out/</code>. Run storacle (newborn / storacle / sat_ladder recipe) before grading.</div>';
        return;
      }
      const meta = data.storacle_meta || {};
      const text = data.storacle_text || '';
      const prev = data.current_certificate;
      const llm = meta.llm_config || {};
      const prevBlock = prev ? `
        <details style="margin-bottom:8px;">
          <summary style="cursor:pointer;color:#888;">previously submitted certificate (awaiting puppeteer scan)</summary>
          <div class="mono" style="font-size:0.8em;background:#f8f8f8;padding:6px;border-left:3px solid #ccc;white-space:pre-wrap;">${escapeHtml(JSON.stringify(prev.grade || {}, null, 2))}</div>
        </details>` : '';
      body.innerHTML = `
        ${prevBlock}
        <div style="margin-bottom:6px;">
          <b>Test administered:</b>
          <div class="hint" style="font-size:0.85em;">
            story_id=<code>${escapeHtml(meta.story_id || '')}</code> ·
            temp=${llm.temperature ?? '?'} ·
            maxTokens=${llm.maxTokens ?? '?'} ·
            topP=${llm.topP ?? '?'} ·
            adapter=<code>${escapeHtml(meta.adapter_path || 'none')}</code>
          </div>
        </div>
        <div style="margin-bottom:6px;">
          <b>Prompt template:</b>
          <pre style="font-size:0.85em;background:#f8f8f8;color:#000;padding:6px;max-height:120px;overflow:auto;">${escapeHtml(meta.template_text || '')}</pre>
        </div>
        <div style="margin-bottom:8px;">
          <b>Response:</b>
          <pre style="font-size:0.85em;background:#f8f8f8;color:#000;padding:6px;max-height:220px;overflow:auto;">${escapeHtml(text)}</pre>
        </div>
        <div style="display:flex;flex-direction:column;gap:6px;border-top:1px solid #ccc;padding-top:8px;">
          <label><b>Verdict:</b>
            <select id="certificate-verdict" style="margin-left:4px;">
              <option value="pass">pass — promote to next stage</option>
              <option value="hospital">hospital — hold for later</option>
              <option value="graveyard">graveyard — cemetery (reject)</option>
            </select>
          </label>
          <label><b>Comments:</b>
            <textarea id="certificate-comments" style="width:100%;min-height:5em;font-family:monospace;font-size:0.9em;padding:6px;box-sizing:border-box;" placeholder="What did the model do well / badly? Reasoning behind the verdict."></textarea>
          </label>
          <div style="display:flex;gap:8px;align-items:center;">
            <button type="button" id="certificate-submit-btn">Submit Certificate</button>
            <span id="certificate-submit-status" class="hint"></span>
          </div>
        </div>
      `;
      const btn = byId('certificate-submit-btn');
      if (btn) btn.addEventListener('click', submitCertificate);
    } catch (err) {
      statusEl.textContent = `error: ${err.message || err}`;
    }
  }

  async function submitCertificate() {
    const verdict  = byId('certificate-verdict')?.value || '';
    const comments = byId('certificate-comments')?.value || '';
    const stat     = byId('certificate-submit-status');
    if (!verdict) {
      if (stat) stat.textContent = 'pick a verdict first';
      return;
    }
    if (stat) stat.textContent = 'submitting…';
    try {
      const resp = await fetch('/api/certificate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ verdict, comments }),
      });
      const data = await resp.json();
      if (!resp.ok || !data.ok) throw new Error(data.error || `http ${resp.status}`);
      if (stat) stat.textContent = `certificate written (stage=${data.stage}, verdict=${data.verdict}) — awaiting puppeteer scan`;
      setTimeout(refreshCertificate, 500);
    } catch (err) {
      if (stat) stat.textContent = `error: ${err.message || err}`;
    }
  }

  // ── Storacle Observations panel ──────────────────────────────────
  const STORACLE_PANEL_HTML = `
    <section class="panel" id="storacle-observations-panel">
      <h2>Storacle Observations</h2>
      <div style="margin-bottom:8px;">
        <button id="save-observation-button" type="button" style="background:#5c6bc0; color:#fff;">
          📝 Save Observation of Previous Storacle Run
        </button>
        <span id="save-observation-result" class="hint mono" style="margin-left:8px;"></span>
      </div>
      <div id="storacle-observations-list" class="mono" style="max-height:600px; overflow-y:auto; font-size:0.85em;">
        <div class="hint">(none yet — click "Save Observation" after a storacle run to capture)</div>
      </div>
    </section>
  `;

  async function saveStoracleObservation() {
    const result = byId('save-observation-result');
    if (result) result.textContent = 'capturing…';
    try {
      const res = await fetch('/api/storacle_observation', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ noted_by: window.CURRENT_USER || null }),
      });
      const data = await res.json();
      if (!res.ok || !data.ok) throw new Error(data.error || 'capture failed');
      if (result) result.textContent = `captured observation #${data.id} at ${data.observed_at}`;
      await refreshStoracleObservations();
    } catch (err) {
      if (result) result.textContent = `capture failed: ${String(err?.message || err)}`;
    }
  }

  async function refreshStoracleObservations() {
    const target = byId('storacle-observations-list');
    if (!target) return;
    try {
      const res = await fetch('/api/storacle_observations', { cache: 'no-store' });
      const data = await res.json();
      if (!res.ok || !data.ok) throw new Error(data.error || 'list failed');
      const obs = Array.isArray(data.observations) ? data.observations : [];
      if (!obs.length) {
        target.innerHTML = '<div class="hint">(none yet — click "Save Observation" after a storacle run to capture)</div>';
        return;
      }
      const focused = document.activeElement;
      const focusedObsId = (focused && focused.classList?.contains('obs-notes'))
        ? focused.getAttribute('data-obs-id') : null;
      target.innerHTML = obs.map((o) => renderObservationRow(o, focusedObsId)).join('');
      target.querySelectorAll('.obs-notes').forEach((node) => {
        node.addEventListener('blur', () => saveObservationNote(node).catch(console.error));
      });
      target.querySelectorAll('.obs-save-btn').forEach((node) => {
        node.addEventListener('click', (event) => {
          const id = event.target.getAttribute('data-obs-id');
          const textarea = target.querySelector(`.obs-notes[data-obs-id="${id}"]`);
          if (textarea) saveObservationNote(textarea).catch(console.error);
        });
      });
    } catch (err) {
      target.innerHTML = `<div class="hint" style="color:#c00;">list failed: ${String(err?.message || err)}</div>`;
    }
  }

  function renderObservationRow(obs, focusedObsId) {
    const cfg = obs.llm_config || {};
    const tags = [];
    if (cfg.temperature != null) tags.push(`temp=${cfg.temperature}`);
    if (cfg.topP != null) tags.push(`topP=${cfg.topP}`);
    if (cfg.repetition_penalty != null) tags.push(`rep=${cfg.repetition_penalty}`);
    if (cfg.presence_penalty != null) tags.push(`pres=${cfg.presence_penalty}`);
    if (cfg.maxTokens != null) tags.push(`max=${cfg.maxTokens}`);
    if (obs.use_kag) tags.push('kag');
    if (obs.use_chunks) tags.push(`chunks(top-${obs.rag_top_k || '?'})`);
    tags.push(obs.adapter_path ? `adapter=${obs.adapter_path}` : 'base');
    if (obs.lora_run_id) tags.push(`lora=${obs.lora_run_id.slice(-16)}`);
    const tagLine = tags.map((t) => `<span style="background:#e0e4ea;padding:1px 5px;margin-right:4px;border-radius:3px;">${escapeHtml(t)}</span>`).join('');
    const prompt = obs.prompt_text || '';
    const generated = obs.generated_text || '';
    const isFocused = focusedObsId === String(obs.id);
    const notesValue = isFocused ? undefined : (obs.notes || '');
    return `
      <details style="border:1px solid #ccc;border-radius:4px;margin-bottom:8px;padding:6px;">
        <summary style="cursor:pointer;">
          <b>#${obs.id}</b> · ${escapeHtml(obs.observed_at)}
          · ${escapeHtml(obs.story_id || '(no story)')}
          · <span style="color:${obs.notes ? '#080' : '#a60'};">notes ${obs.notes ? '✓' : '(empty)'}</span>
        </summary>
        <div style="margin-top:6px;">${tagLine}</div>
        <details style="margin-top:6px;"><summary style="cursor:pointer;font-size:0.85em;color:#666;">prompt (${prompt.length} chars)</summary>
          <pre style="white-space:pre-wrap;background:#f6f6f6;padding:6px;font-size:0.85em;max-height:200px;overflow-y:auto;">${escapeHtml(prompt)}</pre>
        </details>
        <details open style="margin-top:6px;"><summary style="cursor:pointer;font-size:0.85em;color:#666;">generated (${generated.length} chars)</summary>
          <pre style="white-space:pre-wrap;background:#fafaf5;padding:6px;font-size:0.85em;max-height:300px;overflow-y:auto;">${escapeHtml(generated)}</pre>
        </details>
        <label style="display:block;margin-top:6px;">
          <div style="font-size:0.85em;color:#333;margin-bottom:2px;">Notes (freeform; helper corpus material):</div>
          <textarea class="obs-notes" data-obs-id="${obs.id}" rows="4" style="width:98%;font-family:inherit;font-size:0.9em;">${notesValue != null ? escapeHtml(notesValue) : ''}</textarea>
        </label>
        <button type="button" class="obs-save-btn" data-obs-id="${obs.id}" style="margin-top:4px;">Save Notes</button>
        <span class="obs-save-status" data-obs-id="${obs.id}" style="margin-left:8px;font-size:0.85em;color:#666;"></span>
      </details>
    `;
  }

  async function saveObservationNote(textarea) {
    const id = textarea.getAttribute('data-obs-id');
    const notes = textarea.value;
    const status = document.querySelector(`.obs-save-status[data-obs-id="${id}"]`);
    if (status) status.textContent = 'saving…';
    try {
      const res = await fetch('/api/storacle_observation', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: Number(id), notes: notes, noted_by: window.CURRENT_USER || null }),
      });
      const data = await res.json();
      if (!res.ok || !data.ok) throw new Error(data.error || 'save failed');
      if (status) status.textContent = `saved ${data.updated_at}`;
    } catch (err) {
      if (status) { status.style.color = '#c00'; status.textContent = String(err?.message || err); }
    }
  }

  // ── init: inject panels, start refresh loop ──────────────────────
  function injectWriterPanels() {
    const slot = byId('pipe-scope-plugin-slot') || byId('project-root-plugin-slot');
    if (!slot) return false;
    const wrap = document.createElement('div');
    wrap.id = 'writer-panels-wrap';
    wrap.innerHTML = CERT_PANEL_HTML + STORACLE_PANEL_HTML;
    slot.appendChild(wrap);
    const saveBtn = byId('save-observation-button');
    if (saveBtn) saveBtn.addEventListener('click', saveStoracleObservation);
    return true;
  }

  window.PipelinePluginUI = {
    init(_ctx) {
      wireEnvOverridesObserver();
      if (!injectWriterPanels()) {
        console.warn('[writer] no plugin slot found');
        return;
      }
      refreshCertificate().catch(console.error);
      refreshStoracleObservations().catch(console.error);
      window.setInterval(() => { refreshCertificate().catch(console.error); }, 2000);
      window.setInterval(() => { refreshStoracleObservations().catch(console.error); }, 5000);
    },
    decorateArtifact() { return null; },
    decorateFileModal() { return null; },
    renderDynamicPanel() { return false; },
    pipeSelectPrefixOptions() { return ''; },
  };

  // Expose for anything else that wants to call them (e.g. unit tests,
  // or a future top-level button).
  window.submitCertificate = submitCertificate;
  window.saveStoracleObservation = saveStoracleObservation;
  window.refreshCertificate = refreshCertificate;
  window.refreshStoracleObservations = refreshStoracleObservations;
})();
