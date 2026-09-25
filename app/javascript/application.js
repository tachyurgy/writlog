// Event form: show only the payload fields that apply to the chosen event kind.
function wireEventForm() {
  const form = document.querySelector("[data-event-form]")
  if (!form) return
  const select = form.querySelector("[data-kind-select]")
  const sync = () => {
    form.querySelectorAll("label[data-for]").forEach((label) => {
      label.hidden = !label.dataset.for.split(" ").includes(select.value)
    })
  }
  select.addEventListener("change", sync)
  sync()
}

// Mount React islands only where their root element exists.
async function mountIslands() {
  const root = document.getElementById("document-composer")
  if (!root) return
  const { mount } = await import("islands/document_composer")
  mount(root, JSON.parse(root.dataset.props))
}

document.addEventListener("DOMContentLoaded", () => {
  wireEventForm()
  mountIslands()
})
