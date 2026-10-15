class_name SphereEversion
extends RefCounted
## Bednorz & Bednorz analytic sphere eversion (arXiv:1711.10466v2).
##
## eval(theta, phi, s) -> Vector3 is an immersion for every s in [0,1]:
##   s = 0 : right-side-out sphere, radius R_EXPECT
##   s = 1 : inside-out sphere,      radius R_EXPECT
## so s traces a regular homotopy (crease-free) from one to the other.
## eversion_verify.gd is the headless numeric gate that proves it.
##
## ---------------------------------------------------------------------------
## P0 FORMULA SHEET  (n = 2 throughout; source eq. numbers = the paper)
## ---------------------------------------------------------------------------
## Domain: theta in [-pi/2, pi/2] (latitude, +pi/2 = north), phi in [-pi, pi).
##
## Cylinder map (before closing):      h = omega * sin(theta) / cos^n(theta)
##
## Ruled core eq.(4)  [ p = 1 - |q*t| keeps smoothness (5): (n-1)p(1-q|t|)+q t^2 > 0 ]
##   x = t cos(phi) + p sin((n-1)phi) - h sin(phi)
##   y = t sin(phi) + p cos((n-1)phi) + h cos(phi)
##   z = h sin(n phi) - (t/n) cos(n phi) - q t h
##
## Final sphere / unfold eq.(12),(15)  [ used when lambda < 1 ]  (cn = cos^n theta)
##   x = ( t(1-lam+lam cn) cos(phi) - lam omega sin(theta) sin(phi) ) / cn
##   y = ( t(1-lam+lam cn) sin(phi) + lam omega sin(theta) cos(phi) ) / cn
##   z = lam ( omega sin(theta)(sin(n phi) - q t)/cn - (t/n) cos(n phi) )
##       - (1-lam) eta^(1+k) t |t|^(2k) sin(theta) / cos^(2n) theta
##
## Damping eq.(7):   x' = x (xi + eta(x^2+y^2))^-k ,  z' = z / (xi + eta(x^2+y^2))
##   k = kappa = (n-1)/(2n) = 1/4
##
## Closing  r'->r'':
##   alpha <= eps  -> eq.(9)   x'' = x'/rho , z'' = -z'      (rho = x'^2+y'^2)
##   alpha >  eps  -> eq.(8)   gamma = 2 sqrt(alpha beta)
##     x'' = x' e^(gamma z') / (alpha + beta rho)
##     z'' = [(alpha-beta rho)/(alpha+beta rho)] e^(gamma z')/gamma
##           - (1/gamma)(alpha-beta)/(alpha+beta)
##   beta = 1 chosen so (8) -> (9) continuously as alpha -> 0.
##   NOTE: (8) approaches (9) with an O(sqrt(alpha)) term, so d(map)/dalpha -> inf
##   at alpha=0. The schedule eases xi,alpha with smoothstep across stages 2 & 6
##   (alpha ~ (s-s0)^2 there) which restores finite velocity => no visible pop.
##
## Table 1 schedule (rows differ only in listed params; beta=1, omega=2, eta=1):
##   row  sphere        : lam=0 xi=0 a=0     q=Q   |t|=1/Q
##   row  inverted w.h. : lam=1 xi=0 a=0     q=Q   |t|=1/Q
##   row  unfolded w.h. : lam=1 xi=1 a=ALPHA q=Q   |t|=1/Q
##   row  closed w.h.   : lam=1 xi=1 a=ALPHA q=0   |t|<1/Q  (t sweeps -1/Q..+1/Q)
## Read bottom->top for t<0, sweep t in the top row, top->bottom for t>0.
## Stages (master s in [0,1]):
##   1 [0,.15]   lam 0->1                 (lambda form, alpha=0  -> (9))
##   2 [.15,.30] xi 0->1, a 0->A  eased   (eq4, closing  (9)/(8) handoff)
##   3 [.30,.40] q  Q->0                  (eq4, p 0->1)
##   4 [.40,.60] t  -1/Q -> +1/Q          (the flip)
##   5 [.60,.70] q  0->Q                  (eq4, p 1->0)
##   6 [.70,.85] xi 1->0, a A->0  eased   (eq4, closing (8)/(9) handoff)
##   7 [.85,1]   lam 1->0                 (lambda form, alpha=0  -> (9))
## t = -1/Q at s=0 gives the outward sphere; t = +1/Q at s=1 the inward one.
## ---------------------------------------------------------------------------

const N := 2                      # paper's n (n = 2 -> simplest eversion, not Boy)
const Q := 2.0 / 3.0              # Q < 1 ; 1/Q = 1.5 is |t| at the sphere rows
const T_REST := 1.0 / Q           # 1.5
const KAPPA := (N - 1) / (2.0 * N)  # 0.25
const BETA := 1.0                 # =1 so (8) matches (9) as alpha->0
const ETA := 1.0
const OMEGA := 2.0
const ALPHA_STAR := 1.0            # alpha > 0 for the closed/unfolded rows
const R_EXPECT := ETA ** KAPPA * T_REST ** (-1.0 / N)  # sphere radius = 0.8165
const ALPHA_EPS := 1e-9           # switch to (9) below this alpha
const POLE_NUDGE := 0.01          # difference-centre offset off a coordinate pole
const TPOW := T_REST ** 0.5       # |t|^2kappa with |t| = T_REST (lambda branch only)


## Per-frame eversion parameters for a given master progress s.
class EversionParams:
	var t: float = 0.0
	var q: float = 0.0
	var xi: float = 0.0
	var alpha: float = 0.0
	var lam: float = 0.0
	var use_lambda: bool = false   # true -> eq (12),(15); false -> eq (4)


static func params(s: float) -> EversionParams:
	var pm := EversionParams.new()
	if s < 0.15:
		pm.t = -T_REST; pm.q = Q; pm.xi = 0.0; pm.alpha = 0.0
		pm.lam = _lin(s, 0.0, 0.15); pm.use_lambda = true
	elif s < 0.30:
		var e := _smooth(_lin(s, 0.15, 0.30))
		pm.t = -T_REST; pm.q = Q; pm.xi = e; pm.alpha = ALPHA_STAR * e
		pm.lam = 1.0; pm.use_lambda = false
	elif s < 0.40:
		var u := _lin(s, 0.30, 0.40)
		pm.t = -T_REST; pm.q = Q * (1.0 - u); pm.xi = 1.0; pm.alpha = ALPHA_STAR
		pm.lam = 1.0; pm.use_lambda = false
	elif s < 0.60:
		var u := _lin(s, 0.40, 0.60)
		pm.t = -T_REST + 2.0 * T_REST * u; pm.q = 0.0; pm.xi = 1.0; pm.alpha = ALPHA_STAR
		pm.lam = 1.0; pm.use_lambda = false
	elif s < 0.70:
		var u := _lin(s, 0.60, 0.70)
		pm.t = T_REST; pm.q = Q * u; pm.xi = 1.0; pm.alpha = ALPHA_STAR
		pm.lam = 1.0; pm.use_lambda = false
	elif s < 0.85:
		var e := _smooth(1.0 - _lin(s, 0.70, 0.85))
		pm.t = T_REST; pm.q = Q; pm.xi = e; pm.alpha = ALPHA_STAR * e
		pm.lam = 1.0; pm.use_lambda = false
	else:
		pm.t = T_REST; pm.q = Q; pm.xi = 0.0; pm.alpha = 0.0
		pm.lam = 1.0 - _lin(s, 0.85, 1.0); pm.use_lambda = true
	return pm


## Map (theta, phi) -> R^3 for a given parameter set (hot path: no param recompute).
static func eval(theta: float, phi: float, pm: EversionParams) -> Vector3:
	var x: float
	var y: float
	var z: float
	# Trig hoisted (both branches need theta/phi) and every pow() replaced by an
	# exact algebraic identity for n=2, kappa=1/4, ETA=1: pow() is the single most
	# expensive op here, and this runs 559 verts x 5 evals per frame (the whole
	# perf budget). Values are unchanged, so the gate must stay GREEN.
	var c := cos(theta)
	var sn := sin(theta)
	var sp := sin(phi)
	var cp := cos(phi)
	var s2p := 2.0 * sp * cp        # sin(n*phi), n = 2  (double-angle)
	var c2p := cp * cp - sp * sp    # cos(n*phi), n = 2
	if pm.use_lambda:
		var cn := c * c             # pow(c, n), n = 2
		var c2n := cn * cn          # pow(c, 2n) = pow(c, 4)
		var tc := pm.t * (1.0 - pm.lam + pm.lam * cn)
		x = (tc * cp - pm.lam * OMEGA * sn * sp) / cn
		y = (tc * sp + pm.lam * OMEGA * sn * cp) / cn
		# |t| = T_REST in this branch and ETA^(1+kappa) = 1, so both factors collapse to TPOW.
		z = pm.lam * (OMEGA * sn * (s2p - pm.q * pm.t) / cn
				- (pm.t / N) * c2p) \
			- (1.0 - pm.lam) * pm.t * TPOW * sn / c2n
	else:
		var cn := c * c             # pow(c, n), n = 2
		var h: float = OMEGA * sn / cn
		var pv: float = 1.0 - absf(pm.q * pm.t)   # paper's p
		# (n - 1) = 1, so sin/cos((n-1)phi) are just sin/cos(phi)
		x = pm.t * cp + pv * sp - h * sp
		y = pm.t * sp + pv * cp + h * cp
		z = h * s2p - (pm.t / N) * c2p - pm.q * pm.t * h

	# eq.(7) damping  (d^-kappa = d^-1/4 = 1/sqrt(sqrt(d)), kappa = 1/4)
	var d: float = pm.xi + ETA * (x * x + y * y)
	var inv_ds := 1.0 / sqrt(sqrt(d))
	var xp := x * inv_ds
	var yp := y * inv_ds
	var zp := z / d
	var rho := xp * xp + yp * yp

	if pm.alpha <= ALPHA_EPS:
		# eq.(9)
		return Vector3(xp / rho, yp / rho, -zp)
	# eq.(8)
	var gamma := 2.0 * sqrt(pm.alpha * BETA)
	var ex := exp(gamma * zp)
	var den := pm.alpha + BETA * rho
	var zpp := ((pm.alpha - BETA * rho) / den) * ex / gamma \
		- (1.0 / gamma) * (pm.alpha - BETA) / (pm.alpha + BETA)
	return Vector3(xp * ex / den, yp * ex / den, zpp)


## Convenience: full map including per-call params (verifier / occasional use).
static func f(theta: float, phi: float, s: float) -> Vector3:
	return eval(theta, phi, params(s))


## Surface normal via central differences of the map itself (topology-independent).
## jt x jp is the material normal: outward at s=0, inward at s=1 (the flip, verified
## by eversion_verify). Near a coordinate pole jphi degenerates, so nudge the
## difference centre off the pole first; the surface keeps its exact-pole position
## (no hole) while still getting a correct limit normal there.
static func normal(theta: float, phi: float, pm: EversionParams, h: float = 1e-4) -> Vector3:
	var th := theta
	if absf(theta) > PI * 0.5 - POLE_NUDGE:
		th = signf(theta) * (PI * 0.5 - POLE_NUDGE)
	var jt := eval(th + h, phi, pm) - eval(th - h, phi, pm)
	var jp := eval(th, phi + h, pm) - eval(th, phi - h, pm)
	var n := jt.cross(jp)
	var nlen := n.length()
	if nlen < 1e-9:
		return eval(th, phi, pm).normalized()
	return n / nlen


## Differential frame at (theta, phi): position, unit normal, and the two unit
## tangent directions (north = d/dtheta, east = d/dphi). The player uses these to
## orient itself on the surface and to integrate walking in material space.
## Position uses the exact theta (no hole at a pole); only the derivatives nudge
## off the pole, mirroring normal().
static func surface_frame(theta: float, phi: float, pm: EversionParams, h: float = 1e-4) -> Dictionary:
	var th := theta
	if absf(theta) > PI * 0.5 - POLE_NUDGE:
		th = signf(theta) * (PI * 0.5 - POLE_NUDGE)
	var pos := eval(theta, phi, pm)
	var jt := eval(th + h, phi, pm) - eval(th - h, phi, pm)
	var jp := eval(th, phi + h, pm) - eval(th, phi - h, pm)
	var n := jt.cross(jp)
	var nlen := n.length()
	var nrm: Vector3 = pos.normalized() if nlen < 1e-9 else n / nlen
	return {
		"pos": pos,
		"normal": nrm,
		"north": jt.normalized(),
		"east": jp.normalized(),
	}


static func _lin(x: float, a: float, b: float) -> float:
	return (x - a) / (b - a)


static func _smooth(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)
