class_name RouteServiceOverlay
extends CanvasLayer
## NAV-PERF-01B debug overlay for RouteService, toggled with F6: the route work per frame against its budget (last, p95, worst),
## the queue (now, worst, by kind and state), wait before a search starts, time to a result, search work, the counters
## (completed, failed, cancelled, superseded, invalidated, shared, reused) and the last jobs. Read-only: it changes nothing.

var sim: WorldSim
var _label := Label.new()
var _t := 0.0


func _init(p_sim: WorldSim) -> void:
	sim = p_sim
	name = "RouteServiceOverlay"
	layer = 90
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 120)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.09, 0.82)
	sb.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override("panel", sb)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	panel.add_child(_label)
	add_child(panel)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	_label.text = text()


func text() -> String:
	var r := sim.routing
	var rep := r.report()
	var st: Dictionary = rep.stats
	var fm: Dictionary = rep.frame_ms
	var lines: Array[String] = []
	lines.append("ROUTES (F6)  budget %.1f ms/step   revision %d%s" % [r.frame_budget_ms, r.revision, ("  (" + r.last_invalidation + ")") if r.last_invalidation != "" else ""])
	lines.append("frame  last %.2f  p95 %.2f  max %.2f ms   longest step %.2f ms   overruns %d" % [r.last_frame_ms, fm.p95, rep.frame_ms_max, rep.slice_ms_max, st.overruns])
	lines.append("queue  %d now  %d max   %s" % [rep.queue, rep.queue_max, str(r.queue_summary())])
	lines.append("wait   p95 %.0f  max %.0f ms     to result p95 %.0f  max %.0f ms     work p95 %.1f  max %.1f ms" % [rep.wait_ms.p95, rep.wait_ms.max,
		rep.total_ms.p95, rep.total_ms.max, rep.work_ms.p95, rep.work_ms.max])
	lines.append("jobs   %d done  %d failed  %d cancelled (%d superseded)  %d invalidated  %d shared  %d cached  %d same again  %d at once" % [st.completed,
		st.failed, st.cancelled, st.superseded, st.invalidated, st.deduped, st.cache_hits, st.reused_same, st.sync_runs])
	lines.append("by kind %s" % str(rep.by_kind))
	var n := 0
	for i in range(r.recent.size() - 1, -1, -1):
		var j: Dictionary = r.recent[i]
		lines.append("  #%d %s %s %s  wait %.0f  total %.0f  work %.1f ms  %d steps%s%s" % [j.id, j.kind, j.owner, j.state, j.wait_ms, j.total_ms, j.work_ms, j.slices,
			("  restarts %d" % j.restarts) if j.restarts > 0 else "", ("  " + String(j.reason)) if String(j.reason) != "" else ""])
		n += 1
		if n >= 8:
			break
	return "\n".join(lines)
