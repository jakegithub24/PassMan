## Overview

PassMan — an open-source password manager — wears its identity as **glassmorphism**: layered frosted-glass panels floating over a flat, neutral floor. The brand reads as calm and trustworthy rather than flashy — a deep navy-teal `{colors.primary}` (`#0C447C`) carries every primary action against a soft sage-white floor `{colors.canvas}` (`#f4f6f5`), with two barely-there radial tints (`{colors.canvas-tint-1}`, `{colors.canvas-tint-2}`) keeping the neutral background from feeling sterile. Where most security products lean cold and clinical, PassMan leans soft: generous frosted-glass blur, rounded geometry throughout, and a single restrained accent color used only where it matters — the next action to take.

Typography is a single, quiet voice. **Inter** carries everything — hero headlines at weight 800 down to fine print at weight 400 — paired with **Material Symbols Outlined** for every icon. There is no second display face; hierarchy comes entirely from size and weight, not from switching typefaces.

Elevation, not color, is the brand's primary structural device. Every screen separates a flat "floor" (page background, main content) from "floating" frosted-glass chrome (nav, bars, cards, rows) — the more contextual/transient an element is, the higher it floats and the softer/larger its shadow.

**Key Characteristics:**
- A single teal-gradient CTA accent `{colors.primary}` → `{colors.primary-dark}` — the brand's universal primary-action color. No second accent competes with it in any one view.
- One typeface, Inter, at weights 400–800 — hierarchy is built from size/weight, not face-switching. Material Symbols Outlined is the sole icon system.
- `{rounded.xl}` 20 px is the canonical device-frame/large-panel radius; `{rounded.md}` 11 px is the canonical control radius. Corners are soft everywhere; nothing is sharp.
- Elevation is layered and literal: a flat base layer (`Level 0`) with frosted-glass chrome floating above it in graduated steps up to a contextual floating badge (`Level 6`).
- A three-step semantic strength scale — green / yellow / gray — used consistently wherever credential or data health needs a quick visual read.
- The repeating credential row — icon chip + name + masked value + strength pill — is the brand's signature interactive component, appearing at three sizes across desktop, mobile, and a floating widget.

## Colors

### Brand & Accent
- **PassMan Teal** (`{colors.primary}` — `#0C447C`): The brand's universal primary-action color. Every CTA, submit button, active nav/tab state, and FAB.
- **PassMan Teal Dark** (`{colors.primary-dark}` — `#08325D`): The gradient terminus — every primary-action fill is `linear-gradient(135deg, {colors.primary}, {colors.primary-dark})`, never a flat fill.

### Surface
- **Canvas** (`{colors.canvas}` — `#f4f6f5`): The flat, opaque "floor" — main content background, no blur, no shadow.
- **Frame** (`{colors.frame}` — `#eef3f1`): The outer page/frame background behind the device shell.
- **Canvas Tint 1** (`{colors.canvas-tint-1}` — `#dbe9f6`): Soft radial wash, top-left of the page background.
- **Canvas Tint 2** (`{colors.canvas-tint-2}` — `#e4eefa`): Soft radial wash, bottom-right of the page background.
- **Glass** (`{colors.glass}` — `rgba(255,255,255,0.55)`): Standard frosted-glass fill for chrome.
- **Glass Strong** (`{colors.glass-strong}` — `rgba(255,255,255,0.72)`): Denser glass fill for sidebar / search chrome.
- **Glass Border** (`{colors.glass-border}` — `rgba(255,255,255,0.6)`): Border color on all glass panels.
- **Hairline** (`{colors.hairline}` — `rgba(20,22,26,0.08)`): Flat dividers and the device-frame border.

### Text
- **Ink** (`{colors.ink}` — `#14161a`): Primary text and headings.
- **Ink Soft** (`{colors.ink-soft}` — `#5b6169`): Secondary/muted text — subtext, captions, placeholders.

### Semantic
- **Positive / Strong** (`{colors.positive}` — `#12a37f`): Strong-password indicator, success state.
- **Warning / Moderate** (`{colors.warning}` — `#e8a93c`): Moderate-password indicator, caution state.
- **Neutral / Weak** (`{colors.neutral}` — `#c9cdd1`): Weak-or-unset indicator, inactive state.
- **Negative** (`{colors.negative}` — `#e0483f`): Unread-notification dot, destructive/error state.

## Typography

### Font Family
A single face carries the system:
1. **Inter** — every hero headline, body copy, label, and button — weights 400 through 800. No second display face; hierarchy is size/weight only.
2. **Material Symbols Outlined** — the sole icon font, always at weight 300 (`'FILL' 0, 'wght' 300, 'GRAD' 0`).

### Hierarchy

| Token | Size | Weight | Line Height | Letter Spacing | Use |
|---|---|---|---|---|---|
| `{typography.hero-lg}` | 32px | 800 | 1.15 | -0.01em | Desktop dashboard hero headline. |
| `{typography.hero-sm}` | 22px | 800 | 1.2 | 0 | Mobile hero headline. |
| `{typography.auth-title}` | 20–24px | 800 | 1.2 | 0 | Auth card title, desktop. |
| `{typography.auth-title-sm}` | 21px | 800 | 1.2 | 0 | Auth title, mobile. |
| `{typography.label}` | 13px | 600 | 1.2 | 0.06em, uppercase | Section/frame labels. |
| `{typography.body-lg}` | 14.5px | 400 | 1.6 | 0 | Hero/lead paragraphs. |
| `{typography.body}` | 12.5px | 400 | 1.55 | 0 | Default supporting body copy. |
| `{typography.list-primary}` | 13.5–14px | 600 | 1.3 | 0 | Nav items, row primary text. |
| `{typography.meta}` | 11–13px | 400 | 1.3 | 0 | Row subtext, timestamps, fine print. |
| `{typography.button}` | 12–13.5px | 600 | 1.2 | 0 | CTA / submit / tab labels. |

### Principles
- **Weight 800 for hero, weight 600 for structure, weight 400 for reading.** The display ceiling is 800; interactive/structural text sits at 600; long-form supporting copy sits at 400.
- **One face, sized deliberately.** Never introduce a second type family for emphasis — reach for size/weight/color instead.

## Layout

### Spacing System
- **Base unit**: 4 px.
- **Tokens**: `{spacing.xxs}` 4 px · `{spacing.xs}` 8 px · `{spacing.sm}` 12 px · `{spacing.md}` 16 px · `{spacing.lg}` 24 px · `{spacing.xl}` 32 px · `{spacing.2xl}` 40 px.
- **Desktop content padding**: `{spacing.xl}`–`{spacing.2xl}` (28–36 px).
- **Mobile content padding**: `{spacing.md}`–`{spacing.lg}` (18–24 px).
- **Card interior (auth card)**: `{spacing.xl}` (30–32 px).
- **Row gap**: `{spacing.xs}` (8 px).

### Grid & Container
- Desktop app shell: 220 px fixed glass sidebar + fluid content column.
- Mobile app/auth shell: fixed 320 px device width, single column.
- Desktop auth: split layout — teal marketing visual panel (left) + centered glass auth card (right, max-width 360 px).

### Responsive Strategy

#### Breakpoints

| Name | Width | Key Changes |
|---|---|---|
| Mobile | 320px device frame | Single column; bottom tab bar; no sidebar; auth visual panel dropped in favor of compact brand row. |
| Desktop | Fluid, sidebar-driven | Sidebar + top bar navigation; split-panel auth; hero + search/filter above list content. |

#### Touch Targets
Buttons and tappable rows render with 11–12 px vertical padding at 13–13.5 px label size — comfortably within standard touch-target guidance on the mobile shell.

#### Image Behavior
No photography. Iconography is exclusively Material Symbols Outlined; brand marks are flat vector logo/avatar assets; third-party service marks appear as small inline SVGs inside credential rows.

## Elevation & Depth

| Level | Treatment | Use |
|---|---|---|
| Level 0 — Flat | No blur, no shadow. | Main content background, page floor. |
| Level 1 — Glass Chrome | `blur(16px) saturate(140%)`, `0 4px 14px rgba(20,22,26,0.05)` or hairline border. | Sidebar, top bar, header, search/filter bars. |
| Level 2 — Glass Row | `blur(6px)`, border only (`1px solid rgba(255,255,255,0.5)`), no shadow. | List rows, compact rows. |
| Level 3 — Glass Card | `blur(24px) saturate(150%)`, `0 24px 48px rgba(20,22,26,0.10)`. | Auth card, standalone feature cards. |
| Level 4 — Solid Accent | No blur; `0 14px 28px` teal-tinted shadow. | FAB, standalone gradient buttons. |
| Level 5 — Glass Float | `blur(28px) saturate(160%)`, dual drop-shadow (`0 24px 48px` + `0 4px 12px`). | Floating widget panel, mobile bottom tab bar. |
| Level 6 — Float Badge | No blur; `0 10px 22px` teal-tinted shadow. | Contextual floating pills/badges. |

The brand uses **z-index and blur/shadow intensity as one paired signal** — an element's floating "height" and its visual softness always move together; the pairing itself is the elevation cue, more than any single shadow value.

## Shapes

### Border Radius Scale

| Token | Value | Use |
|---|---|---|
| `{rounded.none}` | 0px | Full-bleed edges (device frame outer edge only). |
| `{rounded.sm}` | 8px | Icon chips, small chips/badges. |
| `{rounded.md}` | 11px | Inputs, rows, tabs, buttons — the most common control radius. |
| `{rounded.lg}` | 16px | Mid-size panels (feature cards). |
| `{rounded.xl}` | 20px | The brand's canonical large-panel radius — device frame, auth card, floating widget. |
| `{rounded.pill}` | 999px | Strength pills, floating badge. |
| `{rounded.full}` | 50% | Circular elements — avatars, FAB. |

## Components

### Buttons

**`button-primary`** — the teal-gradient CTA/submit pill.
- Background `linear-gradient(135deg, {colors.primary}, {colors.primary-dark})`, text white, label `{typography.button}`, padding 11–12px 20px, shape `{rounded.md}`, shadow `0 8–12px 20–26px` teal-tinted (intensity scales with prominence).

**`button-secondary`** — the glass/social secondary.
- Background `{colors.glass}`, text `{colors.ink}`, 1px solid `rgba(255,255,255,0.65)` border, same typography/padding/shape as primary.

**`button-fab`** — the circular mobile add-button.
- Background `linear-gradient(135deg, {colors.primary}, {colors.primary-dark})`, 50px circle, shape `{rounded.full}`, shadow `0 14px 28px` teal-tinted, 1px `rgba(255,255,255,0.35)` border.

### Cards & Containers

**`card-glass-chrome`** — sidebar / top bar / header chrome.
- Background `{colors.glass-strong}` or `{colors.glass}`, Level 1 elevation, border `{colors.glass-border}`.

**`card-row`** — the credential/list row (see Signature Components).
- Background `rgba(255,255,255,0.42)`, Level 2 elevation, shape `{rounded.md}`.

**`card-auth`** — the login/sign-up card.
- Background `{colors.glass}`, Level 3 elevation, padding `{spacing.xl}`, shape `{rounded.xl}`, max-width 360px (desktop).

**`card-widget`** — the floating credential widget panel.
- Background `rgba(255,255,255,0.5)`, Level 5 elevation, shape `{rounded.xl}`.

### Inputs & Forms

**`text-input`** (`field-input`) — the canonical form field.
- Background `rgba(255,255,255,0.65)`, text `{colors.ink-soft}` (placeholder) / `{colors.ink}` (value), 1px `rgba(255,255,255,0.75)` border, inset shadow, body in `{typography.body}`, padding 11px 13px, shape `{rounded.md}`. Always paired with a `{typography.label}`-style field label above and a leading Material Symbols icon.

### Navigation

**`nav-sidebar-item`** — desktop sidebar nav row.
- Text `{colors.ink-soft}` default; active state gets `linear-gradient(135deg, {colors.primary}, {colors.primary-dark})` fill, white text, weight 600, Level-4-style shadow. Exactly one active item per screen.

**`nav-tab-mobile`** — bottom tab bar item.
- Text `{colors.ink-soft}` default, `{colors.primary}` + weight 600 when active. Fixed 4-item set (Logins, Vaults, Notes, Settings) at Level 5 elevation.

**`nav-topbar`** — desktop top bar / mobile header.
- Background `{colors.glass}`, Level 1 elevation, hosts screen title, lock icon, notification bell (with `{colors.negative}` ping dot when unread), and profile avatar, in that fixed order.

**`nav-tabs-segmented`** — the Login/Sign-up (or any 2–3 way) segmented toggle.
- Track background `rgba(255,255,255,0.5)`, active segment gets the primary gradient fill + shadow, shape `{rounded.md}` outer / `{rounded.sm}` per-segment.

### Signature Components

**`credential-row`** — the brand's repeating list pattern, at three sizes.
- Desktop: icon chip (30px, `{rounded.sm}`) + name (`{typography.list-primary}`) + masked/domain subtext (`{typography.meta}`) + lock glyph + strength pill (`{colors.positive}` / `{colors.warning}` / `{colors.neutral}`) + overflow menu.
- Mobile: same anatomy, icon 28px, lock/overflow dropped to save width.
- Widget: same anatomy, icon 26px, pill dropped.
- Sensitive values always render masked (`••••••••••`), never plaintext.

**`hero-block`** — top-level landing/dashboard hero.
- Headline `{typography.hero-lg}`/`{typography.hero-sm}`, supporting copy `{typography.body-lg}`, single `button-primary` CTA. Used only on top-level screens, never on deep/utility screens.

**`search-filter-row`** — paired glass search input + filter chip.
- Background `{colors.glass-strong}`, Level 1 elevation, shape `{rounded.md}`. Always sits directly above a row list.

**`auth-visual-panel`** — desktop-only marketing panel beside the auth card.
- Full-bleed `linear-gradient(160deg, {colors.primary}, {colors.primary-dark})`, two soft blurred glow orbs, brand mark, large centered logo mark, a glass feature card (icon + label rows), and a headline/subcopy pair in white/translucent-white text.

**`strength-pill`** — the three-step credential-health indicator.
- `{colors.positive}` strong / `{colors.warning}` moderate / `{colors.neutral}` weak-or-unset. Always the rightmost element before any overflow control on a `credential-row`.

### Examples (composable surfaces)

> Maps PassMan's primitives onto common cross-product surface archetypes, for consistency when an agent needs to build a screen type that has no existing mockup.

**`ex-app-shell-row`** — `nav-sidebar-item` / `nav-tab-mobile`. Active state uses the primary teal gradient as the indicator.

**`ex-auth-form-card`** — `card-auth` with `text-input` primitives and `nav-tabs-segmented` inside.

**`ex-data-table-cell`** — `credential-row` generalized: icon chip + primary label + meta text + status pill, reusable for any tabular list (Vaults, Cards, Notes).

**`ex-empty-state-card`** — not yet designed; should reuse `card-glass-chrome` chrome at Level 2–3 with `{typography.body}` caption copy and a `button-primary` recovery action. *(backlog)*

**`ex-toast`** — not yet designed; should reuse `card-widget` chrome (Level 5) at a compact size with `{typography.body}` copy. *(backlog)*

## Do's and Don'ts

### Do
- Reserve `{colors.primary}` gradient for exactly one primary action or active state per view — CTA, submit, active nav, active tab, FAB.
- Keep the flat-floor / floating-glass contrast on every screen: content background is always Level 0, functional chrome is always Level 1+.
- Use `{rounded.md}` 11px for controls and `{rounded.xl}` 20px for large panels — never introduce a sharper or more extreme radius.
- Reuse the `credential-row` anatomy for any list-of-items screen (Vaults, Cards, Notes), swapping only icon content and pill semantics.
- Mask sensitive values by default everywhere they appear.
- Keep an element's z-index and blur/shadow intensity paired per the Elevation table — never assign high elevation with low-elevation shadow strength or vice versa.

### Don't
- Don't introduce a second accent color for primary actions — teal is the sole identity/action color.
- Don't mix in a second type family or a second icon set — Inter + Material Symbols Outlined only.
- Don't apply backdrop-blur to the base content layer — it must stay flat (Level 0).
- Don't add a 5th mobile tab or a 7th sidebar item without revisiting the information architecture first.
- Don't invent new radius, shadow, or spacing values outside the documented scales.
- Don't show plaintext passwords or credential values in any list/browse context.

## Implementation Notes for AI Agents

### Screen Shells

**Desktop app shell:**
```
device-frame (desktop)
  inner (flex row)
    nav-sidebar-item list           <- Navigation
    [flex:1 column]
      nav-topbar                    <- Navigation
      content (Level 0)
        hero-block (optional)       <- Signature Components
        search-filter-row (optional)
        credential-row list
```

**Mobile app shell:**
```
device-frame (mobile)
  inner
    status bar (cosmetic)
    nav-topbar (mobile header)
    body (Level 0)
      hero-block (optional, compact)
      search-filter-row (optional)
      credential-row list (mobile size)
    button-fab (optional)
    nav-tab-mobile bar
```

**Desktop auth shell:**
```
device-frame (auth)
  inner (flex row)
    auth-visual-panel
    form column
      card-auth
        nav-tabs-segmented
        title + subtitle
        text-input x N
        utility row (checkbox + link)
        button-primary (submit)
        divider
        button-secondary x 2 (social)
        footer link
```

**Mobile auth shell:**
```
device-frame (mobile)
  inner
    status bar
    card-auth (full-width, no visual panel)
      compact brand row
      nav-tabs-segmented
      title + subtitle
      text-input x N
      utility row
      button-primary (submit)
      divider
      button-secondary x 2
      footer link
```

For any new screen type not listed here, start from the desktop or mobile app shell and swap only the top-bar title, hero content, and list/content region — never alter sidebar, top-bar, or tab-bar structure.

### Screen-Building Checklist
- [ ] Wrapped in the correct shell above
- [ ] Uses only documented tokens — no new hex colors, radii, or shadow values
- [ ] Exactly one `button-primary` / active state visible per view
- [ ] Elevation level correctly matched to each element's role
- [ ] List content uses `credential-row` at the correct size variant
- [ ] Inter + Material Symbols Outlined only
- [ ] Sidebar or tab bar present with the correct item marked active
- [ ] Sensitive values masked, never plaintext
- [ ] Strength pills use `{colors.positive}` / `{colors.warning}` / `{colors.neutral}` semantics only

### Backlog — Not Yet Designed
1. Floating widget screen (`card-widget` fully specified, no page built yet)
2. Vaults, Cards, Secure Notes, Settings (nav items exist, no screens)
3. Item detail / edit view for a single credential, card, or note
4. Empty and error states (`ex-empty-state-card`, invalid login, weak password on sign-up, network error)
5. Password generator (linked from the dashboard CTA, no screen yet)
6. Toast/notification surface (`ex-toast`)