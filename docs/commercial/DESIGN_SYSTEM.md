# Arena OS — Design System

**Visual sources of truth**

| Surface | Source |
|---|---|
| Staff counter tablet | `404 Lobby OS.dc.html` (1280×800 frame) |
| Owner Web | Same file · OWNER WEB / `T.*` tokens (1440×900) |
| Customer apps | Derived consumer theme using arena branding colours |
| Super Admin | Neutral dense admin (Barlow + mono); not neon gaming |

---

## 1. Brand & typography (staff / owner dark)

| Role | Font |
|---|---|
| Display / nav / CTA | **Chakra Petch** |
| Timers / pills / meta | **JetBrains Mono** (tabular) |
| Body | **Barlow** |

---

## 2. Colour tokens (counter)

| Token | Value |
|---|---|
| bg | `#07070A` |
| frame | `#0B0B0F` |
| sidebar | `#0E0F14` |
| surface / card | `#101117` |
| dialog | `#12131A` |
| text | `#E8EAF0` |
| accent / live | `#7CFF4F` |
| warning / ending | `#FFB020` |
| danger / overtime | `#FF4444` |
| grey / idle | `#6B7080` |
| info / stock | `#4A8CFF` |

Owner Web light theme uses HTML `T.*` palette; dark optional.

---

## 3. Layout chrome (staff)

- Sidebar **172px**; header **76px**  
- Floor grid **3 columns**, gap **14**, card min-height **206**  
- Session dialogs **centered** (not bottom sheets)  
- Titles only in header  

Forbidden in Lobby UI: Material `AppBar` / `NavigationBar` / `FilledButton` / `showModalBottomSheet` as primary chrome (`UI_PARITY_AUDIT.md`).

---

## 4. Component catalogue

| Component | Spec |
|---|---|
| LobbyButton | Primary fill accent; secondary inset ring; h 52–58 |
| StatusPill | Dot + mono label; state colours |
| StationCard | Name, typeLine, pill, timer, progress+sweep, players, footer |
| ZonePill | Radius 16 |
| SyncPill | Blink dot |
| LobbyDialog | Overlay rgba(4,4,7,.74); radius 16; sheetUp |
| DataTable | Members/stock header `#101117` rows `#0D0E13` |
| Toast | Bottom center |
| FormField | h 52, inset ring, no Material underline |

Motion: `otPulse`, `breathe`, `sweep`, `dotBlink`, `sheetUp`, `toastIn` — state motion, not decoration spam.

---

## 5. Dynamic theming

From `arena_settings` / `me().branding`:

- `brand_name`, `logo_url`, `primary_color`, `accent_color`  
- Applied to CTAs and owner chrome; **semantic status colours stay fixed** for safety (live/ending/overtime must remain recognizable).

---

## 6. Customer app theme

- Light default; brand primary for CTA  
- Large booking cards; wallet balance hero  
- Avoid staff cyber density  

---

## 7. Iconography & assets

- Prefer Lucide (web) / custom outlined icons (Flutter)  
- No emoji as UI chrome  
- Station type icons configurable per `station_types.icon_key`

---

## 8. Figma workflow

1. Screen inventory IDs in `SCREEN_INVENTORY.md` are Figma frame names.  
2. Build components from this token sheet.  
3. Staff frames start from Lobby HTML measurements (parity audit).  
4. Owner frames from HTML W* sections.
