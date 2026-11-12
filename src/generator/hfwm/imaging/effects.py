"""Art passes — the registry of toggleable transforms applied to the art.

An honest stitch of the game's own minimap tiles is the baseline this
pipeline promises.  Anything that goes beyond that and *changes pixels the
player will actually see* is an "art pass", and the rule is simple:

    if a pass modifies the art, it is registered here.  There is no such
    thing as an always-on art transform.

Registering a pass is what makes it toggleable.  From the entries in
:data:`ART_PASSES` the CLI derives, with no per-pass code:

* a ``--<name>`` / ``--no-<name>`` flag pair, defaulting to the pass's own
  :attr:`Pass.default`,
* a ``--<name>-<option>`` flag for each of its options, parsed and
  validated by the option's own :attr:`Option.parse`,
* a line in the run banner saying what is on and with what settings,
* ``--list-art-passes``, and ``--no-art-passes`` to get the raw stitch,
* a stamp in the generated ``FDIDMap.lua`` header recording which passes
  produced the art that is checked in.

That last one matters because ``WorldMap/`` is not tracked: the stamp is
the only record of how the installed art was made.

:func:`resolve` turns parsed CLI values into a plain nested dict — no
classes, no closures — because it is handed to ``ProcessPoolExecutor``
workers and has to pickle.  A pass that is off is simply absent from it,
so ``zone.py`` tests ``"ocean" in passes`` rather than carrying a flag
per pass.

A note on the default.  The three passes here are alternatives, and the
default one — ``alpha-sea`` — deliberately does the *least*: it leaves the
sea transparent and decides nothing, so the choice of what sits behind the
terrain moves out of this pipeline and into the addon's options panel,
where it costs a dropdown rather than a rebuild.  The other two bake a
backdrop in, and are kept for the cases where that is actually wanted.

Adding a pass
-------------
Append a :class:`Pass` to :data:`ART_PASSES`, then read its settings in
:mod:`hfwm.pipeline.zone`.  Nothing in :mod:`hfwm.cli` needs to change.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable

from ..config.ocean import DEFAULT_OCEAN_COLOR
from .ocean import parse_rgb


# ---------------------------------------------------------------------------
# Registry types
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Option:
    """One tunable of a pass, surfaced as ``--<pass>-<name>``.

    *parse* converts the command-line string into whatever the pass wants
    to receive and raises :class:`ValueError` with a human-readable
    message on bad input; the CLI turns that into an exit status rather
    than a traceback.  *default* is kept as a **string** so the generated
    ``--help`` shows exactly what a user would have to type to reproduce
    it.
    """

    name: str
    metavar: str
    default: str
    help: str
    parse: Callable[[str], object]

    @property
    def dest(self) -> str:
        return self.name.replace("-", "_")


@dataclass(frozen=True)
class Pass:
    """One art-modifying pass.

    *supersedes* names passes this one makes meaningless.  Base art, for
    instance, replaces the whole notion of a sea colour, so it supersedes
    ``ocean``: asking for both is a contradiction rather than a stack.
    :func:`resolve` silently drops a superseded pass that was only on by
    default (with a note) and refuses the run if both were asked for
    explicitly.
    """

    name: str
    summary: str
    default: bool
    describe: Callable[[dict], str]
    options: tuple[Option, ...] = ()
    supersedes: tuple[str, ...] = ()
    notes: tuple[str, ...] = field(default_factory=tuple)

    @property
    def dest(self) -> str:
        return self.name.replace("-", "_")


# ---------------------------------------------------------------------------
# The passes
# ---------------------------------------------------------------------------

def _describe_alpha_sea(settings: dict) -> str:
    return (
        "sea and uncovered gaps left transparent; the in-game background "
        "dropdown decides what shows through"
    )


def _describe_ocean(settings: dict) -> str:
    return (
        "sea baked to #%02X%02X%02X, extended into gaps that border open "
        "water" % settings["color"]
    )


def _describe_base_art(settings: dict) -> str:
    return (
        "stitch composited over Blizzard's own hand-painted art; sea and "
        "uncovered gaps left transparent"
    )


ALPHA_SEA = Pass(
    name="alpha-sea",
    summary="Leave the sea transparent so the background is chosen in game.",
    default=True,
    describe=_describe_alpha_sea,
    notes=(
        "The two passes below each bake a backdrop into the BLPs, which "
        "means the player is stuck with whatever was chosen at generation "
        "time and a change of mind costs a 175 MB rebuild. This pass ships "
        "the stitch with its sea and its uncovered cells still transparent "
        "and lets the addon put something behind it at draw time, so one "
        "set of tiles serves three of the four backgrounds the options "
        "panel offers: nothing at all, the unified sea colour, or "
        "Blizzard's own art (which the client already has loaded, so it "
        "costs nothing to show).",
        "The fourth, \"Original\", is the one it cannot serve. The erase "
        "keeps the sea's colour in the RGB channels under alpha 0, so the "
        "shipped files really are bit-exact to a raw stitch, but this "
        "client honours alpha whatever blend mode a texture is given, so "
        "there is no way to read those pixels back on screen. The raw look "
        "comes from a separate dump instead (--original).",
        "The trade-off against --ocean is that a flat backdrop cannot tell "
        "an empty cell that opens onto the sea from one walled inside a "
        "landmass, so on the Ocean Blue background the ~1% of cells that "
        "--ocean deliberately leaves black go blue instead.",
        "Which pixels are sea comes from the terrain, not from colour: "
        "hfwm.gamedata.ocean_water reads each ADT's Ocean-type liquid and "
        "seabed depth, so a lake, a river, a canal or dark terrain shading "
        "is never erased with the sea, and a change in the colour the "
        "minimap baker paints the sea with cannot leave stripes behind.",
    ),
)


OCEAN = Pass(
    name="ocean",
    summary="Bake the sea into the art as a single flat colour.",
    default=False,
    describe=_describe_ocean,
    options=(
        Option(
            name="color",
            metavar="RGB",
            default="#%02X%02X%02X" % DEFAULT_OCEAN_COLOR,
            help=(
                "colour every ocean fill is collapsed onto, as #RRGGBB or "
                "R,G,B (default: the game's own coastal water — unify onto "
                "the near-black open-ocean fill instead and every shore "
                "gets darker rather than the sea getting consistent)"
            ),
            parse=parse_rgb,
        ),
    ),
    supersedes=("alpha-sea",),
    notes=(
        "The stitch renders the sea several different ways, which meet as "
        "hard rectangular seams on 533-yard tile boundaries. This collapses "
        "them onto one colour and extends it into empty cells that border "
        "open water.",
        "Baking the colour in is only worth it for the cell classification: "
        "the sea reaches gaps that open onto open water and stops at ones "
        "walled inside a landmass, which a backdrop drawn behind "
        "transparent art cannot do. Otherwise prefer --alpha-sea and pick "
        "Ocean Blue in game.",
    ),
)


BASE_ART = Pass(
    name="base-art",
    summary="Bake Blizzard's hand-painted map art in under the stitch.",
    default=False,
    describe=_describe_base_art,
    supersedes=("alpha-sea", "ocean"),
    notes=(
        "Instead of choosing a colour for everything the stitch does not "
        "cover, use the client's own art layer as the backdrop: the sea, "
        "the coastline and the parchment border come from the original "
        "hand-painted tiles, with the satellite terrain drawn over the "
        "top. Needs each zone's original art BLPs, which are fetched from "
        "CASC using the very FDIDs the addon remaps.",
        "The in-game Hybrid background gets the same look without baking "
        "it in, because the client already has its own art layer loaded. "
        "This pass is for producing art that shows it on a client whose "
        "own tiles have been replaced or are unavailable.",
    ),
)


# Order is load-bearing.  :func:`resolve` walks this list applying each
# enabled pass's supersedes, so a pass that can lose to another has to be
# listed *before* it — otherwise a loser could be knocked out by a pass
# that is itself knocked out a moment later.  Listing them baseline-first
# satisfies that, and is also the order the run banner reads in.
ART_PASSES: tuple[Pass, ...] = (ALPHA_SEA, OCEAN, BASE_ART)

PASSES_BY_NAME: dict[str, Pass] = {p.name: p for p in ART_PASSES}


# ---------------------------------------------------------------------------
# Resolution
# ---------------------------------------------------------------------------

def resolve(
    requested: dict[str, bool | None],
    values: dict[str, str],
    all_off: bool = False,
) -> tuple[dict[str, dict], list[str]]:
    """Turn CLI input into ``{pass_name: {option: parsed_value}}``.

    *requested* maps a pass name to ``True`` (explicitly on), ``False``
    (explicitly off) or ``None`` (not mentioned — use its default).
    *values* maps ``"<pass>_<option>"`` dests to raw strings.  When
    *all_off* is set every pass is off regardless, which is what
    ``--no-art-passes`` does.

    Returns the settings dict plus notes worth printing.  Raises
    :class:`ValueError` if two explicitly requested passes contradict each
    other or an option value does not parse.
    """
    notes: list[str] = []

    enabled = {
        p.name: (p.default if requested.get(p.name) is None
                 else bool(requested[p.name]))
        for p in ART_PASSES
    }
    if all_off:
        for name in enabled:
            enabled[name] = False
        return {}, ["all art passes disabled — raw stitch"]

    # Supersede: an explicitly requested pass beats one that is merely on
    # by default; two explicit requests that contradict each other are a
    # mistake worth stopping for.
    for p in ART_PASSES:
        if not enabled[p.name]:
            continue
        for loser in p.supersedes:
            if not enabled.get(loser):
                continue
            if requested.get(loser):
                raise ValueError(
                    f"--{loser} and --{p.name} cannot both be used: "
                    f"{p.name} supersedes {loser}"
                )
            enabled[loser] = False
            notes.append(
                f"--{p.name} supersedes --{loser}, which is on by "
                f"default — disabling it"
            )

    settings: dict[str, dict] = {}
    for p in ART_PASSES:
        if not enabled[p.name]:
            continue
        opts: dict[str, object] = {}
        for opt in p.options:
            raw = values.get(f"{p.dest}_{opt.dest}", opt.default)
            try:
                opts[opt.dest] = opt.parse(raw)
            except ValueError as exc:
                raise ValueError(f"--{p.name}-{opt.name}: {exc}") from exc
        settings[p.name] = opts

    return settings, notes


def banner_lines(settings: dict[str, dict]) -> list[str]:
    """Return ``"<name>: <description>"`` for each enabled pass."""
    if not settings:
        return ["(none — raw stitch, gaps left black)"]
    return [
        f"{p.name}: {p.describe(settings[p.name])}"
        for p in ART_PASSES
        if p.name in settings
    ]


def stamp(settings: dict[str, dict]) -> list[str]:
    """Return the compact record written into ``FDIDMap.lua``'s header.

    Deliberately reproducible: every enabled pass with every option
    spelled out, so the stamp is enough to regenerate the same art.
    """
    if not settings:
        return ["none (raw stitch)"]
    out = []
    for p in ART_PASSES:
        if p.name not in settings:
            continue
        opts = settings[p.name]
        if not opts:
            out.append(p.name)
            continue
        rendered = " ".join(
            f"{opt.name}="
            + ("#%02X%02X%02X" % opts[opt.dest]
               if isinstance(opts[opt.dest], tuple) else str(opts[opt.dest]))
            for opt in p.options
        )
        out.append(f"{p.name}({rendered})")
    return out
