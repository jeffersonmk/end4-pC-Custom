.pragma library

// Battery history of one device: a list of {t, p, s, g?} points, t in ms, p in
// 0..1, s in "d" (discharging) | "c" (charging) | "f" (full). g = 1 marks the
// first reading after the device showed up (the shell may have been blind
// before it, so the point is not a real percentage crossing).
// Controllers report the level in coarse steps (DualSense: 10 %), so a point
// is only stored when the level or the state changes.

var MAX_AGE = 72 * 3600 * 1000
var MAX_POINTS = 600
var RECONNECT_GAP = 2 * 3600 * 1000

function addPoint(points, t, p, s, session) {
    var last = points.length ? points[points.length - 1] : null
    if (last && last.p === p && last.s === s) {
        if (!session) return points
        // A shell restart (or a short reconnect) at the same level: a draining pad
        // crosses a step about hourly, so within two hours nothing
        // was missed and the history simply continues.
        if (t - last.t < RECONNECT_GAP) return points
    }
    var point = { t: t, p: p, s: s }
    if (session) point.g = 1
    var next = points.concat([point])
    var cut = t - MAX_AGE
    next = next.filter(function (x) { return x.t >= cut })
    return next.length > MAX_POINTS ? next.slice(next.length - MAX_POINTS) : next
}

// Points inside [now - span, now], keeping the reading that was already valid
// at the window start (clipped to it). Returns [{x: 0..1, y: 0..1, gap: bool}].
function chart(points, now, span) {
    var start = now - span
    var out = []
    var carry = null
    for (var i = 0; i < points.length; i++) {
        var pt = points[i]
        if (pt.t < start) { carry = pt; continue }
        if (out.length === 0 && carry && !pt.g)
            out.push({ x: 0, y: carry.p, gap: false })
        out.push({ x: (pt.t - start) / span, y: pt.p, gap: !!pt.g })
    }
    if (out.length === 0 && carry) out.push({ x: 0, y: carry.p, gap: false })
    if (out.length) out.push({ x: 1, y: out[out.length - 1].y, gap: false })
    return out
}

// Rates (fraction per hour, negative = draining) of the intervals that start
// and end on a real step crossing in the same watched session and state.
function rates(points, state) {
    var out = []
    for (var i = 2; i < points.length; i++) {
        var a = points[i - 1], prev = points[i - 2], b = points[i]
        if (a.g || b.g) continue
        if (a.s !== state || b.s !== state || prev.s !== state) continue
        if (a.p === b.p) continue
        var hours = (b.t - a.t) / 3600000
        if (hours < 1 / 60) continue
        out.push((b.p - a.p) / hours)
    }
    return out
}

function median(list) {
    var s = list.slice().sort(function (x, y) { return x - y })
    var m = Math.floor(s.length / 2)
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2
}

// Seconds until empty (draining) or full (charging), or 0 when unknown.
// Uses the median of the last few measured steps, so it works right after
// connecting, from earlier sessions.
function estimate(points, charging, pct) {
    var r = rates(points, charging ? "c" : "d").slice(-5)
    if (r.length === 0) return 0
    var rate = median(r)
    if (charging ? rate <= 0 : rate >= 0) return 0
    var hours = charging ? (1 - pct) / rate : pct / -rate
    return Math.max(0, Math.round(hours * 3600))
}
