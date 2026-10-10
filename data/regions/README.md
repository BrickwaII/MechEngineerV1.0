# data/regions/

Region files: one map each. `campaign/region_map.gd` reads them; the format is
below. Each act in `data/tuning/acts.json` lists its map variants (these files)
and the default one. The dev menu (`ui/dev/dev_menu.tscn`) plays a run on any
mix of variants.

| Act | File | Regions | Notes |
|---|---|---|---|
| 1 | `lake_washington_8.json` | 8 | Seattle, Bellevue and six suburbs around the lake |
| 1 | `lake_washington_12.json` | 12 | **default.** Seattle in two (the Ship Canal splits it) |
| 1 | `lake_washington_16.json` | 16 | Seattle in four districts |
| 1 | `lake_washington_22.json` | 22 | Seattle in five, plus Edmonds, Woodinville, Issaquah, Burien, SeaTac |
| 2 | `north_america_19.json` | 19 | US regions, Canadian groups, northern Mexico as one |
| 2 | `north_america_33.json` | 33 | **default.** Big states alone, small ones grouped |
| 2 | `north_america_57.json` | 57 | One per state or province (tiny states grouped, below) |
| 3 | `world_8.json` | 8 | Continents and blocs |
| 3 | `world_20.json` | 20 | **default.** World regions; Russia split at the Urals |
| 3 | `world_39.json` | 39 | Major countries, small ones grouped with neighbors |
| test | `act1_placeholder.json`, `harbor_town_placeholder.json` | 12, 6 | Hand-drawn maps the tests use |

Tiny states grouped in `north_america_57.json`: Maryland, Delaware and DC
(Chesapeake); Massachusetts, Connecticut and Rhode Island (Southern New
England); Vermont and New Hampshire. New Brunswick, Nova Scotia and Prince
Edward Island are the Maritimes; Baja California and Baja California Sur are
one region.

## Sources and credit

The outlines are public domain:

- [Natural Earth](https://www.naturalearthdata.com) (public domain): 1:10m land
  and North America lakes (act 1 coastline, Lake Washington), 1:10m admin-1
  states and provinces with lakes cut out (act 2), 1:50m admin-0 countries with
  lakes cut out (act 3). Made with Natural Earth.
- US Census Bureau TIGER/Line 2019 places (public domain), via
  [geojson-us-city-boundaries](https://github.com/generalpiston/geojson-us-city-boundaries):
  the city cores of act 1. Census servers were not reachable from the build
  machine; the mirror is the same data as GeoJSON.
- Hand-drawn approximations: Mercer Island and Lake Sammamish
  (`sources/hand_drawn_*.geojson`), too small for Natural Earth 1:10m.

## How the files are made

`tools/region_prep/prepare_regions.py` builds every file here except the
placeholders, from `sources/<id>.source.json`: which source features make each
region, the frame and projection, water crossings and starts, and the
gameplay numbers (provides, defense, pressure base). Edit a source file and
rebuild, rather than editing the output; see `tools/README.md`. Outlines are
simplified and game-shaped, not survey-accurate: an act 1 city is its city
limits grown over nearby land, and labels sit at the point deepest inside.

## Format

```
{
  "id", "name",
  "projection": "flat" | "globe",        optional, flat by default
  "source": "credit line",               optional
  "regions": [{
    "id", "name", "short_name" (optional, for crowded maps), "kind",
    "polygon": [[x, y], ...],            the main piece
    "parts": [[[x, y], ...], ...],       optional further pieces (islands)
    "label_at": [x, y],                  optional, the centroid by default
    "adjacent": [ids], "provides": {power, energy, material},
    "defense": 0-5, "pressure_base": 1-3, "starts_owned": bool
  }],
  "starts": [...],                       optional starting locations
  "water": [polygons], "land": [polygons],   optional scenery
  "crossings": [{"between": [id, id], "name"}],  bridges, ferries, straits
  "zoom_inset": [points]                 optional: where the last act's map sits
}
```

Flat maps give points 0 to 1 across the view (x right, y down); globe maps
give longitude and latitude in degrees. Adjacency must be symmetric; a
crossing's two regions must list each other.
