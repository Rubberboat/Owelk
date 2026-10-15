.pragma library

// Collections as a tree that folds, shared by the Library panel and the Library tab's sidebar.
// researchStore.collections() lists them in tree order (a collection, then its sub-collections, each
// with depth and parentId). A collection's sub-collections show only while it is open; the open ones
// are a setting of this computer (library.openCollections, ids joined by commas).

function parse(setting) {
    return (setting || "").split(",").filter(function(id) { return id.length > 0 })
}

// The collections that contain this one (its parent, the parent's parent, …).
function ancestors(collections, id) {
    const byId = {}
    collections.forEach(function(c) { byId[c.id] = c })
    const list = []
    let c = byId[id]
    while (c && c.parentId && byId[c.parentId] && list.indexOf(c.parentId) < 0) {
        list.push(c.parentId)
        c = byId[c.parentId]
    }
    return list
}

// The rows to show: each collection with hasChildren and open, sub-collections of a closed one left out.
// The collection shown (if any) keeps its parents open, so it stays in sight.
function rows(collections, open, shown) {
    const openIds = open.concat(shown ? ancestors(collections, shown) : [])
    const result = []
    let hideDeeperThan = -1
    for (let i = 0; i < collections.length; ++i) {
        const c = collections[i], depth = c.depth || 0
        if (hideDeeperThan >= 0 && depth > hideDeeperThan) continue
        hideDeeperThan = -1
        const hasChildren = i + 1 < collections.length && (collections[i + 1].depth || 0) > depth
        const isOpen = hasChildren && openIds.indexOf(c.id) >= 0
        result.push(Object.assign({}, c, {hasChildren: hasChildren, open: isOpen}))
        if (hasChildren && !isOpen) hideDeeperThan = depth
    }
    return result
}

// The open list with a collection opened or closed.
function toggled(open, id, on) {
    const rest = open.filter(function(x) { return x !== id })
    return on ? rest.concat([id]) : rest
}
