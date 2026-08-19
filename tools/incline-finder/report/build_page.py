"""Render the climb report as a self-contained HTML page."""
import json, math

D = json.load(open("out/report.json"))
CLIMBS, (CLAT, CLON) = D["climbs"], D["centre"]

def band_class(g):
    if g < 3: return "b1"
    if g < 4.5: return "b2"
    if g < 6: return "b3"
    if g < 8: return "b4"
    return "b5"

def profile_svg(c):
    W, H, L, R, T, B = 720, 168, 46, 12, 16, 34
    xs = [p[0] for p in c["prof_cop"]]
    ys = [p[1] for p in c["prof_cop"]] + [p[1] for p in c["prof_terr"]]
    lo, hi = min(ys), max(ys)
    pad = max(4.0, (hi - lo) * 0.12)
    lo, hi = lo - pad, hi + pad
    sx = lambda d: L + (d / max(xs)) * (W - L - R)
    sy = lambda e: T + (1 - (e - lo) / (hi - lo)) * (H - T - B)
    def path(points):
        return " ".join(("M" if i == 0 else "L") + f"{sx(d):.1f} {sy(e):.1f}"
                        for i, (d, e) in enumerate(points))
    area = path(c["prof_cop"]) + f" L{sx(max(xs)):.1f} {sy(lo):.1f} L{sx(0):.1f} {sy(lo):.1f} Z"
    # contour lines every 10 m
    grid = []
    start = math.ceil(lo / 10) * 10
    for e in range(int(start), int(hi) + 1, 10):
        grid.append(f'<line class="grid" x1="{L}" y1="{sy(e):.1f}" x2="{W-R}" y2="{sy(e):.1f}"/>'
                    f'<text class="gl" x="{L-8}" y="{sy(e)+3.5:.1f}">{e}</text>')
    e0 = c["prof_cop"][0][1]
    ideal = (f'M{sx(0):.1f} {sy(e0):.1f} L{sx(max(xs)):.1f} '
             f'{sy(min(hi, e0 + 0.05 * max(xs))):.1f}')
    ticks = "".join(
        f'<text class="gl" x="{sx(d):.1f}" y="{H-16}" text-anchor="middle">{int(d/100)/10:g}</text>'
        for d in range(0, int(max(xs)) + 1, 250))
    return (f'<svg viewBox="0 0 {W} {H}" class="prof" role="img" aria-label="Elevation profile: '
            f'{c["length"]} metres climbing {c["gain"]:.0f} metres">'
            + "".join(grid) +
            f'<path class="fill" d="{area}"/>'
            f'<path class="ideal" d="{ideal}"/>'
            f'<path class="terr" d="{path(c["prof_terr"])}"/>'
            f'<path class="cop" d="{path(c["prof_cop"])}"/>'
            f'{ticks}<text class="gl" x="{W-R}" y="{H-16}" text-anchor="end">km</text></svg>')

def bands_html(c):
    n = len(c["bands"])
    cells = "".join(
        f'<div class="band {band_class(g)}" style="flex:{100 if i < n-1 else max(20, c["length"]-x)}">'
        f'<span>{g:.1f}</span></div>' for i, (x, g) in enumerate(c["bands"]))
    return f'<div class="bands" aria-label="gradient per 100 metres">{cells}</div>'

def locator_svg():
    W, H = 720, 420
    pts = [(CLAT, CLON)]
    for c in CLIMBS:
        pts += [tuple(p) for p in c["coords"]]
    mlat, mlon = 111320.0, 111320.0 * math.cos(math.radians(CLAT))
    xs = [(lo - CLON) * mlon for _, lo in pts]; ys = [(la - CLAT) * mlat for la, _ in pts]
    span = max(max(map(abs, xs)), max(map(abs, ys))) * 1.15
    sx = lambda lo: W / 2 + (lo - CLON) * mlon / span * (W / 2 - 30)
    sy = lambda la: H / 2 - (la - CLAT) * mlat / span * (H / 2 - 30)
    rings = "".join(
        f'<circle class="ring" cx="{W/2}" cy="{H/2}" r="{r*1000/span*(H/2-30):.1f}"/>'
        f'<text class="gl" x="{W/2+4}" y="{H/2 - r*1000/span*(H/2-30) + 12:.1f}">{r} km</text>'
        for r in (1, 2, 3) if r * 1000 / span * (H / 2 - 30) < H / 2 - 20)
    routes = []
    for c in CLIMBS:
        d = " ".join(("M" if i == 0 else "L") + f"{sx(lo):.1f} {sy(la):.1f}"
                     for i, (la, lo) in enumerate(c["coords"]))
        routes.append(f'<path class="route r{c["rank"]}" d="{d}"/>')
        la, lo = c["coords"][len(c["coords"]) // 2]
        routes.append(f'<circle class="dot" cx="{sx(lo):.1f}" cy="{sy(la):.1f}" r="11"/>'
                      f'<text class="rank" x="{sx(lo):.1f}" y="{sy(la)+4:.1f}" '
                      f'text-anchor="middle">{c["rank"]}</text>')
    return (f'<svg viewBox="0 0 {W} {H}" class="loc" role="img" aria-label="Locator map of the five '
            f'climbs around Eklanda Hage">{rings}{"".join(routes)}'
            f'<circle class="home" cx="{W/2}" cy="{H/2}" r="5"/>'
            f'<text class="homelab" x="{W/2}" y="{H/2-14}" text-anchor="middle">Eklanda Hage</text>'
            f'</svg>')

cards = []
for c in CLIMBS:
    roads = " → ".join(f'{n} <span class="rm">{d} m</span>' for n, d in c["roads"][:5] if d > 25)
    gmaps = (f'https://www.google.com/maps/dir/{c["start"][0]:.5f},{c["start"][1]:.5f}/'
             f'{c["end"][0]:.5f},{c["end"][1]:.5f}/data=!4m2!4m1!3e1')
    cards.append(f"""
<article class="climb">
  <header class="ch">
    <span class="num">{c['rank']}</span>
    <div>
      <h3>{c['name']}</h3>
      <p class="ends">{c['bottom_label']} <span class="arrow">↗</span> {c['top_label']}</p>
    </div>
    <p class="away"><b>{c['dist']/1000:.1f} km</b><span>from Eklanda Hage</span></p>
  </header>
  <dl class="stats">
    <div><dt>Length</dt><dd>{c['length']} m</dd></div>
    <div><dt>Gain</dt><dd>{c['gain']:.0f} m</dd></div>
    <div><dt>Average</dt><dd class="hi">{c['grade']:.2f} %</dd></div>
    <div><dt>Elevation</dt><dd>{c['bottom_m']}→{c['top_m']} m</dd></div>
    <div><dt>Pulling ≥3 %</dt><dd>{c['steady']} % of it</dd></div>
    <div><dt>Two DEMs</dt><dd>{c['grade_cop']:.2f} / {c['grade_terr']:.2f} %</dd></div>
  </dl>
  {profile_svg(c)}
  {bands_html(c)}
  <p class="legend"><span class="k cop"></span>Copernicus GLO-30 <span class="k terr"></span>AWS terrain
     <span class="k ideal"></span>a true 5 % ramp · strip shows gradient per 100 m
     · <a href="{gmaps}">route in Google Maps</a></p>
</article>""")

html = f"""<title>Eklanda Hage Climbs</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Familjen+Grotesk:wght@400;500;600;700&family=Source+Serif+4:opsz,wght@8..60,400;8..60,600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
:root {{
  --paper:#eaefec; --surface:#f7faf8; --line:#c9d6cf; --ink:#0f1a17; --muted:#55665f;
  --teal:#0d6a5a; --teal-soft:#0d6a5a1f; --contour:#9a6a3c; --rust:#a8492a;
  --b1:#cbdcd4; --b2:#93c3b4; --b3:#3d9581; --b4:#0d6a5a; --b5:#a8492a;
  --sans:"Familjen Grotesk",system-ui,sans-serif;
  --serif:"Source Serif 4",Georgia,serif;
  --mono:"IBM Plex Mono",ui-monospace,monospace;
}}
@media (prefers-color-scheme: dark) {{
  :root:not([data-theme="light"]) {{
    --paper:#0c1412; --surface:#131d1a; --line:#25332e; --ink:#e3ebe6; --muted:#94a69e;
    --teal:#4cc0a4; --teal-soft:#4cc0a422; --contour:#c08b57; --rust:#e0724a;
    --b1:#2c4740; --b2:#3f7f6e; --b3:#4cc0a4; --b4:#7ddcc2; --b5:#e0724a;
  }}
}}
:root[data-theme="dark"] {{
  --paper:#0c1412; --surface:#131d1a; --line:#25332e; --ink:#e3ebe6; --muted:#94a69e;
  --teal:#4cc0a4; --teal-soft:#4cc0a422; --contour:#c08b57; --rust:#e0724a;
  --b1:#2c4740; --b2:#3f7f6e; --b3:#4cc0a4; --b4:#7ddcc2; --b5:#e0724a;
}}
* {{ box-sizing:border-box; }}
body {{ margin:0; background:var(--paper); color:var(--ink); font-family:var(--serif);
  font-size:17px; line-height:1.6; -webkit-font-smoothing:antialiased; }}
.wrap {{ max-width:860px; margin:0 auto; padding:clamp(28px,5vw,64px) clamp(18px,4vw,32px) 80px;
  display:flex; flex-direction:column; gap:44px; }}
h1,h2,h3 {{ font-family:var(--sans); text-wrap:balance; margin:0; letter-spacing:-0.01em; }}
h1 {{ font-size:clamp(34px,6vw,52px); font-weight:700; line-height:1.05; }}
h2 {{ font-size:22px; font-weight:600; }}
h3 {{ font-size:21px; font-weight:600; }}
p {{ margin:0; }}
a {{ color:var(--teal); text-underline-offset:3px; }}
.eyebrow {{ font-family:var(--mono); font-size:12px; letter-spacing:.14em; text-transform:uppercase;
  color:var(--muted); }}
.lede {{ font-size:20px; color:var(--muted); max-width:62ch; }}
header.top {{ display:flex; flex-direction:column; gap:14px; }}
.verdict {{ background:var(--surface); border:1px solid var(--line); border-radius:3px;
  padding:22px 24px; display:flex; flex-direction:column; gap:10px; }}
.verdict .big {{ font-family:var(--sans); font-size:clamp(24px,4vw,32px); font-weight:600;
  line-height:1.2; }}
.verdict .big b {{ color:var(--teal); font-weight:600; }}
section {{ display:flex; flex-direction:column; gap:18px; }}
.climb {{ background:var(--surface); border:1px solid var(--line); border-radius:3px;
  padding:22px 24px 18px; display:flex; flex-direction:column; gap:16px; }}
.ch {{ display:flex; align-items:flex-start; gap:16px; }}
.ch > div {{ flex:1; min-width:0; }}
.num {{ font-family:var(--mono); font-size:13px; color:var(--paper); background:var(--teal);
  width:26px; height:26px; border-radius:50%; display:grid; place-items:center; flex:none;
  margin-top:3px; }}
.ends {{ font-family:var(--mono); font-size:12.5px; color:var(--muted); margin-top:4px; }}
.arrow {{ color:var(--teal); }}
.away {{ font-family:var(--sans); text-align:right; font-size:12px; color:var(--muted);
  display:flex; flex-direction:column; line-height:1.25; flex:none; }}
.away b {{ font-size:18px; color:var(--ink); font-weight:600; }}
.stats {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(112px,1fr)); gap:12px 8px;
  margin:0; padding:14px 0; border-top:1px solid var(--line); border-bottom:1px solid var(--line); }}
.stats div {{ display:flex; flex-direction:column; gap:2px; }}
dt {{ font-family:var(--mono); font-size:10.5px; letter-spacing:.09em; text-transform:uppercase;
  color:var(--muted); }}
dd {{ margin:0; font-family:var(--sans); font-size:19px; font-weight:500;
  font-variant-numeric:tabular-nums; }}
dd.hi {{ color:var(--teal); }}
svg.prof, svg.loc {{ width:100%; height:auto; display:block; overflow:visible; }}
.grid {{ stroke:var(--line); stroke-width:1; }}
.gl {{ font-family:var(--mono); font-size:9px; fill:var(--muted); }}
.fill {{ fill:var(--teal-soft); }}
.cop {{ fill:none; stroke:var(--teal); stroke-width:2.2; stroke-linejoin:round; }}
.terr {{ fill:none; stroke:var(--contour); stroke-width:1.3; stroke-dasharray:1 3;
  stroke-linecap:round; }}
.ideal {{ fill:none; stroke:var(--muted); stroke-width:1; stroke-dasharray:7 5; opacity:.75; }}
.bands {{ display:flex; gap:2px; height:26px; }}
.band {{ display:grid; place-items:center; border-radius:1px; font-family:var(--mono);
  font-size:9.5px; color:#08110e; }}
.band span {{ opacity:.85; }}
.b1{{background:var(--b1)}} .b2{{background:var(--b2)}} .b3{{background:var(--b3)}}
.b4{{background:var(--b4)}} .b5{{background:var(--b5)}}
.legend {{ font-family:var(--mono); font-size:11px; color:var(--muted); display:flex;
  flex-wrap:wrap; align-items:center; gap:6px; }}
.k {{ width:16px; height:0; border-top-width:2.4px; border-top-style:solid; display:inline-block;
  margin-right:2px; }}
.k.cop {{ border-color:var(--teal); }}
.k.terr {{ border-color:var(--contour); border-top-style:dotted; }}
.k.ideal {{ border-color:var(--muted); border-top-style:dashed; }}
.ring {{ fill:none; stroke:var(--line); stroke-width:1; stroke-dasharray:3 4; }}
.route {{ fill:none; stroke:var(--teal); stroke-width:3; stroke-linecap:round; stroke-linejoin:round; }}
.route.r3, .route.r4, .route.r5 {{ opacity:.55; }}
.dot {{ fill:var(--surface); stroke:var(--teal); stroke-width:1.5; }}
.rank {{ font-family:var(--mono); font-size:11px; fill:var(--ink); }}
.home {{ fill:var(--rust); }}
.homelab {{ font-family:var(--mono); font-size:11px; fill:var(--rust); letter-spacing:.06em; }}
.note {{ color:var(--muted); font-size:15.5px; max-width:64ch; }}
.method {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:18px; }}
.method div {{ display:flex; flex-direction:column; gap:5px; }}
.method h4 {{ font-family:var(--mono); font-size:11px; letter-spacing:.1em; text-transform:uppercase;
  color:var(--muted); margin:0; font-weight:400; }}
.method p {{ font-size:15px; }}
.rm {{ font-family:var(--mono); font-size:11px; color:var(--muted); }}
hr {{ border:none; border-top:1px solid var(--line); margin:0; }}
</style>

<div class="wrap">
  <header class="top">
    <p class="eyebrow">Mölndal · OpenStreetMap + 2 elevation models</p>
    <h1>A kilometre at five per cent</h1>
    <p class="lede">Every road within 4 km of Eklanda Hage, walked uphill and measured against
      two independent elevation models. Five climbs come close to the target; one is almost
      exactly it.</p>
  </header>

  <div class="verdict">
    <p class="eyebrow">Closest to the brief</p>
    <p class="big"><b>Sisjövägen</b> — 995 m at 5.0 %, 50 m of climbing, on one road with no
      turns, 2.0 km from your door.</p>
    <p class="note">From the Datavägen/Knapegårdsvägen junction at 14 m, south-east and up to
      65 m. Both elevation models agree to within 0.25 percentage points, and a separated
      cycle path runs alongside the whole length.</p>
  </div>

  <section>
    <h2>Where they are</h2>
    <p class="note">Rings at 1, 2 and 3 km from Eklanda Hage. Nothing inside 2 km holds a steady
      5 % for a kilometre — the closest candidate, the service road up Västra Eklanda Höjd at
      625 m, is steeper in one model than the other and flattens in its middle third.</p>
    {locator_svg()}
  </section>

  <section>
    <h2>The five</h2>
    {"".join(cards)}
  </section>

  <hr>

  <section>
    <h2>How this was measured</h2>
    <div class="method">
      <div><h4>Roads</h4><p>Overture Maps transportation segments (OpenStreetMap-derived),
        July 2026 release — 13,075 tarmac segments within 4 km, resampled every 25 m.</p></div>
      <div><h4>Elevation</h4><p>AWS Terrain Tiles for the search, Copernicus GLO-30 as an
        independent check. Both are surface models: trees and buildings beside the road add
        noise, so profiles are smoothed over 60 m.</p></div>
      <div><h4>Search</h4><p>A depth-first walk uphill from every junction, dropping any branch
        that gives back more than 6 m below its high point, then trimming each corridor to the
        stretch that best matches 1 km at 5 %.</p></div>
      <div><h4>What to trust</h4><p>Averages over a kilometre are solid to about ±0.3 points.
        Individual 100 m readings in the strip are not — treat the bands as shape, not gospel.</p></div>
    </div>
  </section>
</div>
"""
open("climbs.html", "w").write(html)
print(f"wrote climbs.html ({len(html)/1024:.0f} KB)")
