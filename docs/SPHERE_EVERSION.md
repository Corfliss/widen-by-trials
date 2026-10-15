# Plan: Smale's Paradox (Sphere Eversion) as a Walkable Level in Godot

**Status:** Plan (no implementation)
**Engine:** Godot 4.7 (Forward+), per `project.godot`
**Source input:** `docs/FEEDBACK 1.md` — "make Smale's Paradox sphere eversion as the level now rather than flat level... you stand at any given point in surface of a sphere shaped level, and can be inverted inside and outside"
**Assumed assets:** one huge planet-scale sphere already made in Blender, with props on top of it.

## Constraints (kept as given)

1. This document is a **plan only** — no Godot implementation code.
2. Every mathematical claim about the paradox is backed by **peer-reviewed sources** (tier 1 below). Non-peer-reviewed material is labeled and is used only for visualization/history context, never to justify the math.
3. **No assumptions.** Anything not established by a source is marked *"No source — must be measured/decided in this project"*.
4. Output of this task is this document.

---

## 1. Terms disambiguated

No aero-engineering specification document exists in this repository (grep for `aero|eversion|Smale` matches only the feedback note). Disambiguation below is therefore against general engineering/aero usage of the same words. **This plan involves no aerodynamics, aeroelasticity, or structural shell analysis.**

| Term | Meaning here (differential topology) | Confusable with |
|---|---|---|
| **Smale's Paradox** | Not a logical paradox: a counterintuitive *theorem* — a sphere can be turned inside-out smoothly (Smale 1958/59, tier 1). | "Paradox" used loosely for any surprising result. |
| **Eversion** | Turning a surface inside-out via continuous deformation of the *surface itself*. | "Eversion" of physical shells in solid mechanics (a load-driven physical instability) — **out of scope**; nothing in this plan is a mechanics simulation. |
| **Immersion** | A map with full-rank derivative everywhere: no crease, no tear, **self-intersection allowed**. | Rendering "immersion" (immersive display); engineering "immersion" (submersion/immersion of pipelines). |
| **Embedding** | Immersion that is also one-to-one (no self-intersection). Start and end states are embeddings; intermediate states are not. | — |
| **Regular homotopy** | Continuous deformation through immersions only (the allowed animation). Distinct from plain homotopy (may crease) and isotopy (may not self-intersect). | "Homotopy" used loosely for any deformation. |
| **Crease** | A point where the surface loses smoothness (derivative degenerates) — **forbidden** at every moment of the eversion. | Visual shading artifact, which is a renderer issue, not a topological one. |
| **Double point / self-intersection curve** | Where the surface passes through itself during eversion — **required and allowed**. | Z-fighting (a depth-buffer artifact — see Risks). |
| **Halfway model** | The special midpoint immersion (Boy's surface or Morin surface) that the eversion is built around. | "Midpoint" of a linear mesh interpolation — not the same thing (see D2). |
| **Sphere** | The hollow 2-sphere surface S² — the level's walkable skin. Not a solid ball, not a spheroid, not an aerodynamic body. "Planet-sized" is a game scale, a presentation choice only. |

## 2. What the peer-reviewed sources establish

1. **The theorem.** Smale proved that all immersions of S² in ℝ³ are regularly homotopic; in particular the standard embedding and its inside-out mirror image are connected by a regular homotopy — no crease, no tear, self-intersections permitted. (Smale, *Trans. Amer. Math. Soc.* 90 (1958), 281–290; fuller treatment: Smale, *Ann. of Math.* 69 (1959), 327–344.)
2. **Explicit formulas exist.** Bednorz & Bednorz give "relatively simple explicit formulas for the whole eversion, both analytic and topologically simpler, including also Boy surface," via a family of ruled surfaces, with demonstrated visualization. (*Differential Geometry and its Applications* 64 (2019), 59–79.) **This is the plan's formula source.**
3. **An explicit construction is published.** Francis & Morin publish Shapiro's explicit eversion (halfway-model method). (*Mathematical Intelligencer* 2(4), 200–203, doi:10.1007/BF03028603.) — fallback construction if (2) proves unsuitable.
4. **Visualization techniques are published.** Francis & Sullivan, minimax eversion and how to render/visualize it. (*IEEE Trans. Visualization and Computer Graphics* 10(5) (2004), 509–515.)

Everything about *game* feasibility (Godot performance, walkability feel, collision) has **no published source**; it is addressed below as project-owned measurement, not as fact.

## 3. Decisions (captured)

**D1 — Experience: ride the surface.** The eversion plays in real time while the player walks on it.
*Consequence:* collision and props must track a deforming surface every frame. *Sacrificed:* the cheaper "watch then respawn" model.

**D2 — Animation: formula-driven CPU vertex update.** Evaluate the closed-form immersion each frame and push vertices to Godot (`ArrayMesh`, with `ARRAY_FLAG_USE_DYNAMIC_UPDATE` + `surface_update_vertex_region`, per the official 4.7 class reference).
*Consequence:* every frame is a true regular-homotopy sample — the crease-free property stays verifiable. *Sacrificed:* CPU per frame; blend shapes and vertex-shader morphs were **rejected** because linear interpolation between two immersions is not guaranteed to be an immersion (it can crease, i.e. break the very theorem being portrayed), and shader-side formulas make normal computation and verification untrustworthy.

**D3 — Locomotion: parameter-space walking.** The player is anchored to material coordinates (u, v) on the sphere; world ground position each frame is `f_t(u, v)` (the formula), and the local up-vector comes from the surface partials at that point.
*Consequence:* exact ground contact through folds and self-intersections — it never asks "which sheet is below me", a question that is ill-defined mid-eversion. Props anchor the same way. *Sacrificed:* the surface metric stretches under the player during the deformation (see Risks).

## 4. Phases

**P0 — Source lock & formula selection (no code).** Obtain the Bednorz & Bednorz paper; confirm the formula family covers: start = standard sphere embedding, end = inside-out embedding, and a documented midpoint; record parameterization (domain, poles, seams) and partial derivatives. *Exit:* a one-page formula sheet with the paper's equation references. *Fallback if unsuitable:* Francis & Morin halfway-model construction (tier 1, but more stages to implement).

**P1 — Offline numeric verifier (before any Godot work).** Sample `f_t(u, v)` over a dense (u, v, t) grid; compute the smallest singular value of the 2×3 Jacobian at each sample; require it > ε everywhere. This is the project's proof-by-measurement that our discretization of the published eversion never creases. *Exit:* verifier passes with recorded margin; it becomes a regression tool for every later change.

**P2 — Mesh pipeline.** Reconcile the Blender sphere's topology with the formula's parameterization (poles and seam are the known friction points — no source exists for how *this* mesh matches *these* formulas; measure in this phase). Per-frame: evaluate positions on CPU, push vertex region updates; compute normals from the formula's partials (analytic), not from mesh finite differences. Eversion driver node owns scalar `t ∈ [0, 1]`, with hold capability at the midpoint. *Exit:* sphere everts in-engine, P1 verifier still green on the actual vertex buffer.

**P3 — Player, props, ground.** `CharacterBody3D` with custom radial gravity replaced by D3's up-vector; walk motion integrated in (u, v) space; props parented to material anchors. Character sheet-switching during self-intersection is *inherent* to D3 (anchor never changes), so no sheet logic is written. *Exit:* player stands on the sphere through a full eversion and ends up on the same material point with the world inside-out around them.

**P4 — Presentation.** Two-sided rendering so face orientation drives inside/outside coloring (how this should *look* is a creative-director decision, not technical). Camera: verify nothing clips when the player is geometrically inside the self-intersecting surface.

**P5 — Budget & measurement.** Frame budget 16.6 ms @60 fps; the eversion subsystem (vertex evaluation + upload + gravity/up-vector) gets an initial cap of **2 ms CPU/frame**, to be re-set after first measurement. *No source exists for these numbers — this budget is ours, and P5 either confirms it or revises it with recorded data.* Measure: vertex count vs. update cost, mesh upload bandwidth, worst-case frame during eversion.

## 5. Verification — we'll know this was right if…

1. **Topological:** P1 verifier reports min singular value > ε over the full (u, v, t) grid, on both the formula *and* the live vertex buffer.
2. **Visual:** hold-frames at any `t` show no crease; inside/outside coloring flips across a full cycle; self-intersection curves render without z-fighting.
3. **Gameplay:** start standing at point A → complete one eversion → still standing at material point A, with the world inverted; props follow their anchors; no ground penetration at any `t`.
4. **Performance:** measured worst-case eversion frame ≤ the P5 budget on min-spec hardware.

## 6. Risks

| Risk | Mitigation |
|---|---|
| Blender topology ≠ formula parameterization (seams/poles) | P0 extracts domain first; P2 measures mismatch before committing to a remesh plan |
| Metric distortion under the player during deformation (D3) | Authentic but may feel wrong — evaluate in playtest; tuning lever is eversion speed, not the math |
| Up-vector flips near folds → disorientation | Hold-capable `t`, slow ramps, camera smoothing; player comfort is a playtest criterion |
| Z-fighting where sheets coincide exactly | Depth-offset rendering epsilon (visual only; does not alter the evaluated surface) |
| Bednorz formulas don't fit the level's needs | Fall back to Francis & Morin construction (both tier 1) |
| CPU vertex update cost at planet tessellation | P5 measures first; only if over budget, revisit D2 (blend shapes remain disqualified for correctness reasons) |

**Open (non-blocking, for other leads):** airborne behavior during eversion (game-design); inside/outside color language (creative-director); whether props invert with the surface or are destroyed (game-design). A formal ADR will be raised at implementation start, per architecture policy.

## 7. Sources

**Tier 1 — peer-reviewed, backs the math:**
1. Smale, S. *A classification of immersions of the two-sphere.* Trans. Amer. Math. Soc. 90 (1958), 281–290.
2. Smale, S. *The classification of immersions of spheres in Euclidean space.* Ann. of Mathematics 69 (1959), 327–344. (full text: https://webhomes.maths.ed.ac.uk/~v1ranick/papers/smale4.pdf)
3. Lashof, R.; Smale, S. *On the immersion of manifolds in Euclidean space.* Ann. of Math. 68 (1958), 562–583.
4. Bednorz, A.; Bednorz, W. *Analytic sphere eversion using ruled surfaces.* Differential Geometry and its Applications 64 (2019), 59–79. doi:10.1016/j.difgeo.2019.02.004 (preprint: arXiv:1711.10466)
5. Francis, G. K.; Morin, B. *Arnold Shapiro's Eversion of the Sphere.* Mathematical Intelligencer 2(4), 200–203. doi:10.1007/BF03028603
6. Francis, G. K.; Sullivan, J. M. *Visualizing a Sphere Eversion.* IEEE Trans. Visualization and Computer Graphics 10(5) (2004), 509–515.

**Tier 2 — reputable, NOT peer-reviewed; visualization/history context only, never math justification:**
- Phillips, A. *Turning a Surface Inside Out.* Scientific American 214(5) (1966), 112–120. (magazine)
- Max, N. *Turning a Sphere Inside Out.* film, International Film Bureau, 1977.
- *Outside In.* Geometry Center, 1994. (http://www.geom.uiuc.edu/docs/weboogl/zoo/outsidein)
- Grant, M. *Turning spheres inside-out.* university lecture slides (https://homepages.abdn.ac.uk/mark.grant/pages/resources/175spheres.pdf)

**Tier 3 — official engine documentation (Godot 4.7, not peer-reviewed; engine facts only):**
- ArrayMesh class reference (blend shapes, `surface_update_vertex_region`, `ARRAY_FLAG_USE_DYNAMIC_UPDATE`): https://docs.godotengine.org/en/stable/classes/class_arraymesh.html
- Procedural geometry tutorial: https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/arraymesh.html
- CharacterBody3D, ConcavePolygonShape3D, SurfaceTool: https://docs.godotengine.org/en/stable/classes/
