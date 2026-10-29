extends RefCounted
## Fixed geometric measurement, also run unchanged against the pre-7C source.
static func angle(edge: Dictionary) -> float:
	if edge.type not in ["tunnel","diagonal"]: return 0.0
	var a: Rect2 = edge.pieces[0]
	var b: Rect2 = edge.pieces[-1]
	return rad_to_deg(atan2(absf(b.end.y-a.end.y),b.end.x-a.position.x))

static func shape(edge: Dictionary) -> String:
	if edge.type not in ["tunnel","diagonal"]: return edge.type
	var a: Rect2 = edge.pieces[0]
	var b: Rect2 = edge.pieces[-1]
	var rise := b.end.y-a.end.y
	if rise == 0: return "flat_tunnel"
	if absf(rise)<96 or angle(edge)<20 or angle(edge)>50: return "gentle_tunnel"
	for i in range(1,edge.pieces.size()):
		var delta: float = edge.pieces[i].end.y-edge.pieces[i-1].end.y
		if delta*rise<0 or absf(delta)>64: return "gentle_tunnel"
	return "diagonal_steps"
