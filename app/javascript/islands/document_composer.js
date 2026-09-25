import React, { useCallback, useEffect, useRef, useState } from "react"
import { createRoot } from "react-dom/client"
import htm from "htm"

const html = htm.bind(React.createElement)
const csrf = () => document.querySelector('meta[name="csrf-token"]')?.content

async function api(url, options = {}) {
  const res = await fetch(url, {
    ...options,
    headers: { Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": csrf(), ...(options.headers || {}) },
  })
  const body = await res.json().catch(() => ({}))
  return { status: res.status, body }
}

function FieldTable({ fields, values, missing }) {
  return html`<table className="fields">
    <tbody>
      ${fields.map((f) => html`<tr key=${f} className=${missing.includes(f) ? "missing" : ""}>
        <td className="mono">{{${f}}}</td>
        <td>${values[f] ?? html`<em>no value on this matter yet</em>`}</td>
      </tr>`)}
    </tbody>
  </table>`
}

function DocList({ docs }) {
  if (!docs.length) return html`<p className="hint">No documents generated yet.</p>`
  return html`<ul className="docs">
    ${docs.map((d) => html`<li key=${d.id}>
      <span className=${"badge doc-" + d.status}>${d.status}</span>
      <a href=${"/documents/" + d.id}>${d.template_key} v${d.version}</a>
      <small className="mono"> #${d.id} · ${d.short_digest}</small>
      ${d.pdf_url && html` · <a href=${d.pdf_url} target="_blank" rel="noopener">PDF</a>`}
    </li>`)}
  </ul>`
}

function Composer({ matter, templates, endpoints }) {
  const [templateId, setTemplateId] = useState(templates[0]?.id)
  const [preview, setPreview] = useState(null)
  const [docs, setDocs] = useState([])
  const [busy, setBusy] = useState(false)
  const [log, setLog] = useState([])
  const poll = useRef(null)

  const loadDocs = useCallback(async () => {
    const { body } = await api(endpoints.list)
    setDocs(body.documents || [])
    return body.documents || []
  }, [endpoints.list])

  const loadPreview = useCallback(async (id) => {
    const { body } = await api(`${endpoints.preview}?template_id=${id}`)
    setPreview(body)
  }, [endpoints.preview])

  useEffect(() => { loadDocs() }, [loadDocs])
  useEffect(() => { if (templateId) loadPreview(templateId) }, [templateId, loadPreview])
  useEffect(() => () => clearInterval(poll.current), [])

  const watch = () => {
    clearInterval(poll.current)
    let ticks = 0
    poll.current = setInterval(async () => {
      const list = await loadDocs()
      ticks += 1
      if (ticks > 40 || list.every((d) => d.status !== "pending")) {
        clearInterval(poll.current)
        loadPreview(templateId)
      }
    }, 750)
  }

  const generate = async (times) => {
    setBusy(true)
    const started = performance.now()
    const payload = JSON.stringify({ template_id: templateId })
    const results = await Promise.all(
      Array.from({ length: times }, () => api(endpoints.create, { method: "POST", body: payload }))
    )
    const ms = Math.round(performance.now() - started)
    const lines = results.map((r, i) => r.body.document
      ? `request ${String.fromCharCode(65 + i)}: HTTP ${r.status} ${r.body.created ? "created" : "returned existing"} document #${r.body.document.id} (v${r.body.document.version})`
      : `request ${String.fromCharCode(65 + i)}: HTTP ${r.status} ${r.body.error || ""}`)
    const ids = new Set(results.map((r) => r.body.document?.id).filter(Boolean))
    if (times > 1) lines.push(ids.size === 1 ? `→ ${times} concurrent requests, 1 document (${ms} ms)` : `→ ${ids.size} documents: idempotency FAILED`)
    setLog(lines)
    setBusy(false)
    watch()
  }

  const tpl = templates.find((t) => t.id === Number(templateId))
  const blocked = !preview || preview.missing.length > 0

  return html`<div className="composer card">
    <label>Template
      <select value=${templateId} onChange=${(e) => setTemplateId(Number(e.target.value))}>
        ${templates.map((t) => html`<option key=${t.id} value=${t.id}>${t.name} (v${t.version})</option>`)}
      </select>
    </label>
    ${tpl?.description && html`<p className="hint">${tpl.description}</p>`}
    ${preview && html`<div>
      <${FieldTable} fields=${preview.template.fields} values=${preview.values} missing=${preview.missing} />
      ${preview.inputs_digest && html`<p className="hint mono">inputs sha256 ${preview.inputs_digest.slice(0, 16)}…
        ${preview.existing ? ` · already generated as #${preview.existing.id} (v${preview.existing.version})` : " · not generated yet"}</p>`}
      ${preview.missing.length > 0 && html`<p className="warn">Cannot generate: ${preview.missing.join(", ")} not known for this matter yet. Advance the workflow first.</p>`}
      <details><summary>Preview merged text</summary><div className="paper small" dangerouslySetInnerHTML=${{ __html: preview.html }}></div></details>
    </div>`}
    <div className="btn-row">
      <button className="btn" disabled=${busy || blocked} onClick=${() => generate(1)}>Generate</button>
      <button className="btn ghost" disabled=${busy || blocked} onClick=${() => generate(2)} title="Fires two POSTs at the same instant">Generate twice at once</button>
    </div>
    ${log.length > 0 && html`<pre className="race">${log.join("\n")}</pre>`}
    <h3>Generated for ${matter}</h3>
    <${DocList} docs=${docs} />
  </div>`
}

export function mount(el, props) {
  createRoot(el).render(html`<${Composer} ...${props} />`)
}
