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
// The default engine itself.
function current(store) {
    const chosen = template(store)
    return all(store).find(function(e) { return e.template === chosen }) || Tree.searchEngines[0]
}
function setDefault(store, template) { store.setSetting("searchEngine", template) }
// Engines hidden from Home's engine button (Settings › Web); the default one always shows.
function hidden(store) {
    try {
        const list = JSON.parse(store.setting("web.hiddenEngines", "[]") || "[]")
        return Array.isArray(list) ? list : []
    } catch (e) {
        return []
    }
}
function setHidden(store, template, hide) {
    const list = hidden(store).filter(function(t) { return t !== template })
    if (hide) list.push(template)
    store.setSetting("web.hiddenEngines", JSON.stringify(list))
}
// The engines offered for a search: those not hidden, the default always among them.
function shown(store) {
    const off = hidden(store), chosen = template(store)
    const list = all(store).filter(function(e) { return e.template === chosen || off.indexOf(e.template) < 0 })
    return list.some(function(e) { return e.template === chosen }) ? list : [current(store)].concat(list)
}

// Search addresses of well-known sites, so typing "google.com" is enough when adding an engine.
var known = {
    "google.com": ["Google", "https://www.google.com/search?q=%s"],
    "scholar.google.com": ["Google Scholar", "https://scholar.google.com/scholar?q=%s"],
    "bing.com": ["Bing", "https://www.bing.com/search?q=%s"],
    "duckduckgo.com": ["DuckDuckGo", "https://duckduckgo.com/?q=%s"],
    "naver.com": ["Naver", "https://search.naver.com/search.naver?query=%s"],
    "search.naver.com": ["Naver", "https://search.naver.com/search.naver?query=%s"],
    "daum.net": ["Daum", "https://search.daum.net/search?q=%s"],
    "arxiv.org": ["arXiv", "https://arxiv.org/search/?query=%s&searchtype=all"],
    "semanticscholar.org": ["Semantic Scholar", "https://www.semanticscholar.org/search?q=%s"],
    "pubmed.ncbi.nlm.nih.gov": ["PubMed", "https://pubmed.ncbi.nlm.nih.gov/?term=%s"],
    "pubmed.gov": ["PubMed", "https://pubmed.ncbi.nlm.nih.gov/?term=%s"],
    "wikipedia.org": ["Wikipedia", "https://en.wikipedia.org/w/index.php?search=%s"],
    "en.wikipedia.org": ["Wikipedia", "https://en.wikipedia.org/w/index.php?search=%s"],
    "ko.wikipedia.org": ["Wikipedia (Korean)", "https://ko.wikipedia.org/w/index.php?search=%s"],
    "youtube.com": ["YouTube", "https://www.youtube.com/results?search_query=%s"],
    "github.com": ["GitHub", "https://github.com/search?q=%s"],
    "dblp.org": ["dblp", "https://dblp.org/search?q=%s"],
    "researchgate.net": ["ResearchGate", "https://www.researchgate.net/search?q=%s"],
    "paperswithcode.com": ["Papers with Code", "https://paperswithcode.com/search?q=%s"],
    "openreview.net": ["OpenReview", "https://openreview.net/search?term=%s"],
    "ieeexplore.ieee.org": ["IEEE Xplore", "https://ieeexplore.ieee.org/search/searchresult.jsp?queryText=%s"],
    "dl.acm.org": ["ACM Digital Library", "https://dl.acm.org/action/doSearch?AllField=%s"],
    "link.springer.com": ["Springer", "https://link.springer.com/search?query=%s"],
    "springer.com": ["Springer", "https://link.springer.com/search?query=%s"],
    "sciencedirect.com": ["ScienceDirect", "https://www.sciencedirect.com/search?qs=%s"],
    "riss.kr": ["RISS", "https://www.riss.kr/search/Search.do?query=%s"],
    "dbpia.co.kr": ["DBpia", "https://www.dbpia.co.kr/search/topSearch?searchOption=all&query=%s"],
    "perplexity.ai": ["Perplexity", "https://www.perplexity.ai/search?q=%s"]
}
function hostOf(text) {
    return String(text).trim().replace(/^https?:\/\//i, "").replace(/^www\./i, "").replace(/[\/?#].*$/, "").toLowerCase()
}
// What a typed address becomes: as typed when it has %s (https:// added), a known site's search address,
// or the site's /search?q=. Empty when it does not look like a site.
function templateFor(text) {
    const value = String(text).trim()
    if (!value.length) return ""
    if (value.indexOf("%s") >= 0) return /^https?:\/\//i.test(value) ? value : "https://" + value
    const host = hostOf(value)
    if (!/^[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(host)) return ""
    return known[host] ? known[host][1] : "https://" + host + "/search?q=%s"
}
// A name for a typed site: the known one, else the site's main word ("example.org": "Example").
function nameFor(text) {
    const host = hostOf(text)
    if (known[host]) return known[host][0]
    const main = host.split(".").filter(function(part) { return part !== "search" })[0] || host
    return main.length ? main.charAt(0).toUpperCase() + main.slice(1) : ""
}
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
    setHidden(store, template, false)
    store.setSetting("web.engines", JSON.stringify(custom(store).filter(function(e) { return e.template !== template })
                                                                  .map(function(e) { return {name: e.name, template: e.template} })))
    if (store.setting("searchEngine", "") === template) setDefault(store, Tree.searchEngines[0].template)
    custom(store)
}

// Extract only search words; addresses and arXiv identifiers are never sent to AI.
function words(store, text) {
    const value = String(text || "").trim()
    const intent = Tree.webIntent(value, template(store))
    if (!intent || intent.title.indexOf("Open ") === 0) return ""
    const named = /^([a-z]+):\s*(\S[\s\S]*)$/i.exec(value)
    if (named && Tree.searchEngines.some(function(e) { return e.prefix === named[1].toLowerCase() }))
        return named[2]
    return value
}
function prepare(store, text) { store.searchText.prepare(words(store, text)) }
function input(store, text) {
    const query = words(store, text)
    if (!query.length) return text
    const value = String(text || "").trim()
    return value.slice(0, value.length - query.length) + store.searchText.webQuery(query)
}
