extends SceneTree
## P1 headless numeric gate for the sphere eversion.
##
## Run:  godot --headless --path . -s src/objects/eversion_verify.gd
## Exit code 0 = GREEN (safe to ship the surface), 1 = RED (do NOT use).
##
## Proves, for the *ported* SphereEversion math:
##   1. endpoints are exact spheres of radius R_EXPECT with opposite orientation
##      (material normal jt x jp: outward at s=0, inward at s=1 => true flip)
##   2. crease-free: min singular value of the 2x3 Jacobian > EPS over the bulk
##   3. the pinch (both poles -> origin at s=0.15/0.85) is a smooth cap, not a
##      crease: near-pole sigma tracks the natural cap scale (ratio > 0.5)
##   4. surface stays bounded and finite (compact, no NaN)
##   5. no teleports: stage-boundary jumps shrink to ~linear (a residual O(sqrt)
##      pop from the alpha->0 closing handoff would fail this check)

const EV := preload("res://src/objects/sphere_eversion.gd")

const EPS_CREASE := 0.03     # bulk min-sigma floor (validated ~0.066 => 2x margin)
const POLE_MARGIN := 0.1      # stay this far (rad) from the coordinate poles
const NAN_LIMIT := 10.0       # |coord| above this = blew up / not compact
const BOUNDARY_EPS := 1e-5
const BOUNDARY_TOL := 1e-3    # linear ~1.4e-4 passes; sqrt-pop ~9e-3 fails


func _init() -> void:
	var fails := 0
	print("=== sphere eversion verifier (P1 gate) ===")
	print("R_EXPECT = %.5f  (N=%d Q=%.3f T_REST=%.2f)" % [
		EV.R_EXPECT, EV.N, EV.Q, EV.T_REST])

	fails += _check_endpoints()
	fails += _check_bulk_immersion()
	fails += _check_pinch()
	fails += _check_bounded()
	fails += _check_boundary_continuity()

	if fails == 0:
		print("\nVERDICT: GREEN  (crease-free, correct flip, no teleports)")
		quit(0)
	else:
		print("\nVERDICT: RED  (%d check(s) failed)" % fails)
		quit(1)


# sigma_min of the 2x3 Jacobian [jt; jp] via eigenvalues of J J^T:
# tr = |jt|^2+|jp|^2, det = |jt x jp|^2  =>  sigma2^2 = (tr - sqrt(tr^2-4det))/2
func _min_sigma(theta: float, phi: float, s: float, h: float = 1e-4) -> float:
	var pm := EV.params(s)
	# /2h => true derivatives, so sigma is comparable to R_EXPECT (matches the
	# EPS_CREASE / pinch-ratio thresholds, which are derivative-scale).
	var jt := (EV.eval(theta + h, phi, pm) - EV.eval(theta - h, phi, pm)) / (2.0 * h)
	var jp := (EV.eval(theta, phi + h, pm) - EV.eval(theta, phi - h, pm)) / (2.0 * h)
	var tr := jt.length_squared() + jp.length_squared()
	var det := jt.cross(jp).length_squared()
	var disc := maxf(0.0, tr * tr - 4.0 * det)
	return sqrt(maxf(0.0, 0.5 * (tr - sqrt(disc))))


func _check_endpoints() -> int:
	var fails := 0
	var n := 24
	for cfg in [
		{"s": 0.0, "name": "s=0 START", "outward": true},
		{"s": 1.0, "name": "s=1 END  ", "outward": false},
	]:
		var s: float = cfg.s
		var rs := PackedFloat32Array()
		var outward := 0
		var total := 0
		for ti in range(n):
			var th := -PI / 2 + 0.15 + (PI - 0.3) * ti / (n - 1)
			for pj in range(n):
				var ph := TAU * pj / float(n)
				var p := EV.f(th, ph, s)
				rs.append(p.length())
				var pm := EV.params(s)
				var jt := EV.eval(th + 1e-4, ph, pm) - EV.eval(th - 1e-4, ph, pm)
				var jp := EV.eval(th, ph + 1e-4, pm) - EV.eval(th, ph - 1e-4, pm)
				if jt.cross(jp).dot(p) > 0.0:
					outward += 1
				total += 1
		var mean := 0.0
		for r in rs:
			mean += r
		mean /= rs.size()
		var variance := 0.0
		for r in rs:
			variance += (r - mean) * (r - mean)
		variance /= rs.size()
		var std := sqrt(variance)
		var frac := float(outward) / float(total)
		var sphere_ok := absf(mean - EV.R_EXPECT) < 1e-3 and std < 1e-3
		var want := 0.95 if cfg.outward else 0.05
		var orient_ok := (frac > 0.95) if cfg.outward else (frac < 0.05)
		var ok := sphere_ok and orient_ok
		if not ok:
			fails += 1
		print("  [%s] radius mean=%.4f std=%.5f  outward_frac=%.3f (want %s %.2f)  %s" % [
			cfg.name, mean, std, frac,
			">" if cfg.outward else "<", want,
			"OK" if ok else "FAIL"])
	return fails


func _check_bulk_immersion() -> int:
	var nt := 30
	var np := 36
	var ns := 30
	var min_sig := INF
	var where := Vector3.ZERO
	for si in range(ns + 1):
		var s := float(si) / ns
		for ti in range(nt):
			var th := -PI / 2 + POLE_MARGIN + (PI - 2 * POLE_MARGIN) * ti / (nt - 1)
			for k in range(np):
				var ph := -PI + TAU * k / float(np)
				var sig := _min_sigma(th, ph, s)
				if sig < min_sig:
					min_sig = sig
					where = Vector3(th, ph, s)
	var ok := min_sig > EPS_CREASE
	print("  [bulk crease-free] min sigma = %.5f at (th,phi,s)=(%.3f,%.3f,%.3f)  %s" % [
		min_sig, where.x, where.y, where.z, "OK" if ok else "FAIL"])
	return 0 if ok else 1


func _check_pinch() -> int:
	# both poles collapse to the origin at s=0.15 / 0.85; the cap must stay smooth
	var fails := 0
	for s in [0.15, 0.5, 0.85]:
		var worst_ratio := INF
		for m in [0.1, 0.03, 0.01]:
			var th: float = PI / 2.0 - m
			var natural: float = EV.R_EXPECT * sin(m)
			var mn := INF
			for k in range(24):
				mn = minf(mn, _min_sigma(th, -PI + TAU * k / 24.0, s))
			worst_ratio = minf(worst_ratio, mn / (natural + 1e-15))
		var ok := worst_ratio > 0.5
		if not ok:
			fails += 1
		print("  [pinch s=%.2f] worst cap ratio = %.3f (smooth ~>.5)  %s" % [
			s, worst_ratio, "OK" if ok else "FAIL"])
	return fails


func _check_bounded() -> int:
	var max_abs := 0.0
	var nan := 0
	for si in range(21):
		var s := float(si) / 20.0
		for ti in range(20):
			var th := -PI / 2 + POLE_MARGIN + (PI - 2 * POLE_MARGIN) * ti / 19.0
			for k in range(24):
				var p := EV.f(th, -PI + TAU * k / 24.0, s)
				if not is_finite(p.x) or not is_finite(p.y) or not is_finite(p.z):
					nan += 1
					continue
				max_abs = maxf(max_abs, maxf(absf(p.x), maxf(absf(p.y), absf(p.z))))
	var ok := nan == 0 and max_abs < NAN_LIMIT
	print("  [bounded/finite] max|coord| = %.4f  NaN = %d  %s" % [
		max_abs, nan, "OK" if ok else "FAIL"])
	return 0 if ok else 1


func _check_boundary_continuity() -> int:
	# a true discontinuity stays constant as delta shrinks; the sqrt-alpha pop
	# regresses to ~9e-3; a clean linear handoff is ~1.4e-4 at delta=1e-5.
	var fails := 0
	var pts := [Vector2(0.5, 1.0), Vector2(1.0, -0.7), Vector2(1.4, 0.3),
		Vector2(-1.2, 2.0), Vector2(0.0, 0.0)]
	for b in [0.15, 0.30, 0.40, 0.60, 0.70, 0.85]:
		var worst := 0.0
		for pt in pts:
			var d := (EV.f(pt.x, pt.y, b - BOUNDARY_EPS)
				- EV.f(pt.x, pt.y, b + BOUNDARY_EPS)).length()
			worst = maxf(worst, d)
		var ok := worst < BOUNDARY_TOL
		if not ok:
			fails += 1
		print("  [boundary s=%.2f] jump@1e-5 = %.6f  %s" % [
			b, worst, "OK" if ok else "FAIL"])
	return fails
