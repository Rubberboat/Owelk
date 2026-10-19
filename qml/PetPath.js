.pragma library

// The tuxedo cat's colors, as in docs/pet/tuxedo-cat-pet.html (--fur, --cat-white, --eye ...).
var fur = "#1D1B1E", furHi = "#2F2C32", furLo = "#121114", white = "#F7F6F1", eye = "#CFE3A0", pupil = "#101012"
var pink = "#E9A0A5", nose = "#343137", closed = "#8E929B"
// The dark-theme rim light (--rim) around the cat, so black fur stays visible on a dark desktop.
var rim = "#FFFFFF"

// SVG path strings for what SVG draws as <ellipse> and <rect rx>.
function ellipse(cx, cy, rx, ry) {
    return "M" + (cx - rx) + "," + cy + " a" + rx + "," + ry + " 0 1 0 " + (2 * rx) + ",0 a" + rx + "," + ry + " 0 1 0 " + (-2 * rx) + ",0 Z"
}
function rect(x, y, w, h, r) {
    r = Math.min(r, w / 2, h / 2)
    if (r <= 0) return "M" + x + "," + y + " h" + w + " v" + h + " h" + (-w) + " Z"
    return "M" + (x + r) + "," + y + " h" + (w - 2 * r) + " a" + r + "," + r + " 0 0 1 " + r + "," + r
        + " v" + (h - 2 * r) + " a" + r + "," + r + " 0 0 1 " + (-r) + "," + r
        + " h" + (-(w - 2 * r)) + " a" + r + "," + r + " 0 0 1 " + (-r) + "," + (-r)
        + " v" + (-(h - 2 * r)) + " a" + r + "," + r + " 0 0 1 " + r + "," + (-r) + " Z"
}

// CSS keyframes as numbers: keys [[position 0..1, value], ...]; position t (0..1). smooth is CSS's
// ease-in-out between keys, otherwise linear.
function keyframes(keys, t, smooth) {
    if (t <= keys[0][0]) return keys[0][1]
    for (let i = 0; i < keys.length - 1; ++i) {
        const a = keys[i], b = keys[i + 1]
        if (t <= b[0]) {
            let u = (t - a[0]) / (b[0] - a[0])
            if (smooth) u = u * u * (3 - 2 * u)
            return a[1] + (b[1] - a[1]) * u
        }
    }
    return keys[keys.length - 1][1]
}
// Where a cycle of `period` seconds is at time t seconds (0..1), shifted by `shift` cycles.
function cycle(t, period, shift) {
    const p = t / period + (shift || 0)
    return p - Math.floor(p)
}
// The part of a number after the point (0..1).
function frac(x) {
    return x - Math.floor(x)
}
// 0 below a, 1 above b, an ease-in-out between.
function smoothstep(a, b, x) {
    const u = Math.min(1, Math.max(0, (x - a) / (b - a)))
    return u * u * (3 - 2 * u)
}
// A value that goes 0 -> 1 -> 0 over a cycle (CSS "alternate" with ease-in-out).
function back(p) {
    const u = p < .5 ? p * 2 : (1 - p) * 2
    return u * u * (3 - 2 * u)
}

// The gallop (one stride), as the page's @keyframes fu fl hu hl hipsK midK runAll runHead tailRun.
var fu = [[0, -68], [.25, -8], [.5, 48], [.75, -35], [1, -68]]
var fl = [[0, -8], [.25, 0], [.5, 75], [.75, 60], [1, -8]]
var hu = [[0, 62], [.25, 18], [.5, -50], [.75, 5], [1, 62]]
var hl = [[0, 12], [.25, -30], [.5, 25], [.75, -5], [1, 12]]
var hipsX = [[0, -11], [.25, 0], [.5, 15], [.75, 5], [1, -11]]
var hipsY = [[0, 0], [.25, 0], [.5, -3], [.75, 0], [1, 0]]
var midX = [[0, -5], [.25, 0], [.5, 7], [.75, 2], [1, -5]]
var midY = [[0, 0], [.25, 0], [.5, -2], [.75, 0], [1, 0]]
var allY = [[0, -5], [.25, 1], [.5, -8], [.75, 1], [1, -5]]
var allR = [[0, -1.5], [.25, 1], [.5, 2], [.75, -1], [1, -1.5]]
