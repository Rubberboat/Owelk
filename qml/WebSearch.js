.pragma library
.import "WorkspaceTree.js" as Tree

// Web search engines: the built-in ones (Tree.searchEngines), then the reader's own (Settings › Web), each
// {name, label, template} where %s stands for the words. The default one is the "searchEngine" setting.
function valid(engine) {
    return !!engine && typeof engine.name === "string" && engine.name.trim().length > 0
        && typeof engine.template === "string" && /^https?:\/\/\S+$/i.test(engine.template) && engine.template.indexOf("%s") >= 0
}
// Read from the settings (web.engines, JSON); Tree then names them too.
function custom(store) {
    let list = []
    try {
        const saved = JSON.parse(store.setting("web.engines", "[]") || "[]")
        if (Array.isArray(saved)) list = saved.filter(valid).map(function(e) { return {name: e.name.trim(), label: e.name.trim(), template: e.template} })
    } catch (e) {}
    Tree.setCustomEngines(list)
    return list
}
function all(store) { return Tree.searchEngines.concat(custom(store)) }
function isBuiltIn(template) { return Tree.searchEngines.some(function(e) { return e.template === template }) }
// The default engine's template (an older or unknown setting falls back to the first built-in one).
function template(store) {
    custom(store)
    const saved = store.setting("searchEngine", "")
    return valid({name: "x", template: saved}) ? saved : Tree.searchEngines[0].template
}
function setDefault(store, template) { store.setSetting("searchEngine", template) }
// An engine of one's own; false when the name is empty, the address has no %s, or it is listed already.
function add(store, name, template) {
    const engine = {name: String(name).trim(), template: String(template).trim()}
    if (!valid(engine) || all(store).some(function(e) { return e.template === engine.template })) return false
    store.setSetting("web.engines", JSON.stringify(custom(store).map(function(e) { return {name: e.name, template: e.template} }).concat([engine])))
    custom(store)
    return true
}
// Removed; when it was the default, the first built-in engine takes over.
function remove(store, template) {
    store.setSetting("web.engines", JSON.stringify(custom(store).filter(function(e) { return e.template !== template })
                                                                  .map(function(e) { return {name: e.name, template: e.template} })))
    if (store.setting("searchEngine", "") === template) setDefault(store, Tree.searchEngines[0].template)
    custom(store)
}
