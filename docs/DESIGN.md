---
name: hoink. Design System
colors:
  surface: '#effdf6'
  surface-dim: '#cfddd7'
  surface-bright: '#effdf6'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#e9f7f0'
  surface-container: '#e3f1ea'
  surface-container-high: '#deebe5'
  surface-container-highest: '#d8e6df'
  on-surface: '#121e1a'
  on-surface-variant: '#404846'
  inverse-surface: '#27332f'
  inverse-on-surface: '#e6f4ed'
  outline: '#717976'
  outline-variant: '#c0c8c5'
  surface-tint: '#3b665e'
  primary: '#002722'
  on-primary: '#ffffff'
  primary-container: '#103e37'
  on-primary-container: '#7da9a0'
  inverse-primary: '#a2d0c6'
  secondary: '#615e58'
  on-secondary: '#ffffff'
  secondary-container: '#e7e2da'
  on-secondary-container: '#67645e'
  tertiary: '#40121f'
  on-tertiary: '#ffffff'
  tertiary-container: '#5a2734'
  on-tertiary-container: '#d38d9c'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#beece1'
  primary-fixed-dim: '#a2d0c6'
  on-primary-fixed: '#00201b'
  on-primary-fixed-variant: '#234e46'
  secondary-fixed: '#e7e2da'
  secondary-fixed-dim: '#cbc6be'
  on-secondary-fixed: '#1d1b17'
  on-secondary-fixed-variant: '#494641'
  tertiary-fixed: '#ffd9df'
  tertiary-fixed-dim: '#fdb2c1'
  on-tertiary-fixed: '#370b19'
  on-tertiary-fixed-variant: '#6c3643'
  background: '#effdf6'
  on-background: '#121e1a'
  surface-variant: '#d8e6df'
typography:
  display-hero:
    fontFamily: Sora
    fontSize: 40px
    fontWeight: '700'
    lineHeight: 48px
    letterSpacing: -0.03em
  display-hero-mobile:
    fontFamily: Sora
    fontSize: 30px
    fontWeight: '700'
    lineHeight: 36px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Sora
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 36px
    letterSpacing: -0.02em
  headline-lg-mobile:
    fontFamily: Sora
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Sora
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 26px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Sora
    fontSize: 16px
    fontWeight: '600'
    lineHeight: 22px
    letterSpacing: 0em
  currency-display:
    fontFamily: Sora
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  currency-display-mobile:
    fontFamily: Sora
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.01em
  body-lg:
    fontFamily: Sora
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: -0.005em
  body-md:
    fontFamily: Sora
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: 0em
  body-sm:
    fontFamily: Sora
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
    letterSpacing: 0.01em
  label-md:
    fontFamily: Sora
    fontSize: 13px
    fontWeight: '600'
    lineHeight: 18px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Sora
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.04em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-desktop: 1.5rem
  margin: 1rem
  margin-tablet: 2rem
  margin-desktop: 3rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

This design system defines a sophisticated, modern Brazilian fintech platform catering to dual-profile users: personal balance management and micro/small-business operations (*Pessoal*, *Profissional*, and *Consolidado*). 

The visual thesis relies on high-trust institutionality infused with human warmth. Traditional Brazilian banking interfaces swing between sterile monochrome minimalism and aggressive, neon consumer plays. This system anchors itself in an editorial, grounded balance: deep architectural pine greens that communicate institutional security and wealth preservation, balanced against warm cream grounds, subtle playful piggy-bank accents (*cofrinhos* in Pig Pink), and fresh mint growth indicators.

### Key Characteristics
- **Personality**: Disarming, disciplined, clear, and reassuringly robust.
- **Audience**: Self-employed professionals, dual-account entrepreneurs (PJ/PF), and modern Brazilian savers seeking actionable clarity over complex legacy banking jargon.
- **Emotional Response**: Complete control over cash flow with an encouraging, frictionless sense of momentum ("Seu dinheiro, do seu jeito").
- **Aesthetic Movement**: Warm Institutional Modernism with soft geometric tactility. High-legibility typography, deliberate negative space, tactile card layers, and micro-delights driven by financial goals.

## Colors

The color palette operates primarily on high-contrast pairings between the dark pine identity and warm cream paper surfaces, reserving vibrant pastels for intentional semantic cues.

### Functional Palette Structure
- **Primary (`#103E37`)**: Pine Green. Used for top-level brand identity, hero balance widgets, primary interactive triggers, active navigation items, and high-emphasis structural cards.
- **Secondary / Canvas (`#FFF9F1`)**: Warm Ivory / Cream. Replaces harsh `#FFFFFF` as the global background to soften ocular fatigue and evoke tactile, premium paper ledger craftsmanship.
- **Tertiary / Accent (`#F3A9B8`)**: Pig Pink. Dedicated to savings reserves (*cofrinhos*), milestone achievements, badge highlights, and mascot-driven narrative moments. Must never be used for negative alert states.
- **Neutral Primary (`#1D2925`)**: Charcoal Pine. Provides high-contrast readability for running typography, headlines, and data-dense tables without the starkness of pure black.
- **Semantic Mint (`#B9E9CF`)**: Growth Green. Emphasizes positive yields, incoming transfers (*Pix recebido*), yield percentages, and completed progress rails.
- **Surface Pure (`#FFFFFF`)**: Pure White. Used exclusively for elevated interactive cards, input containers, and modal sheets layered on top of the Warm Ivory canvas.
- **Structural Stroke (`rgba(16, 62, 55, 0.08)` / `#E8E2D8`)**: Low-contrast boundaries defining cards, dividers, and table splits without visual noise.

## Typography

The type system is built entirely on Sora. Its wide proportions, open counters, and sharp geometric terminals give Portuguese fintech text a modern, accessible rhythm.

### Numerical Representation (Brazilian Real - R$)
- All currency lines, ledger listings, and transaction tallies must enforce `font-feature-settings: "tnum" 1` (tabular numerals) to ensure vertical alignment of decimals and columns across transaction tables.
- The standard Brazilian currency prefix ("R$") should sit at regular or medium weight at 80% visual size relative to the subsequent numerical value to maintain visual emphasis on the amount.
- Negative balances should be preceded by standard minus signs ("-R$") colored in muted rust or secondary neutrals, avoiding alarming red unless accompanied by severe overdraft thresholds.

## Layout & Spacing

The layout model utilizes a fluid responsive grid bounded by strict max-width constraints for executive dashboards and centered mobile canvases.

### Layout Rhythm
- **Mobile (< 768px)**: Single column with `1rem` (16px) margins. Cards occupy full viewport width minus canvas margins.
- **Tablet (768px - 1024px)**: 8-column layout with `1rem` gutters and `2rem` screen margins.
- **Desktop (> 1024px)**: 12-column layout with `1.5rem` gutters and a maximum content containment width of `1280px`. Left rail navigation is fixed (260px) while financial overview widgets use modular 4-column and 8-column clusters.

Vertical cadence follows strict multiples of `4px` and `8px` to anchor financial tables and metric widgets into predictable baselines.

## Elevation & Depth

Visual hierarchy does not rely on aggressive drop shadows; instead, it is articulated through physical surface stepping and organic ambient diffusion.

### Hierarchy Tiers
- **Ground / Base (`#FFF9F1`)**: The foundation. Zero elevation.
- **Level 1 — Elevated Surfaces (`#FFFFFF`)**: Standard cards, lists, segmented views. Supported by `border: 1px solid rgba(16, 62, 55, 0.06)` combined with a soft, natural drop shadow: `0 4px 16px -2px rgba(16, 62, 55, 0.04)`.
- **Level 2 — Interactive Floats & Dropdowns**: Search panels, context menus, and active tooltips. Uses `0 12px 32px -4px rgba(16, 62, 55, 0.08)`.
- **Level 3 — Modals & Bottom Sheets**: Full Pix validation panels, transaction details. Overlay scrim uses `rgba(16, 62, 55, 0.40)` with `backdrop-filter: blur(8px)`.
- **Hero Surface Tier (Inverted Dark Cards)**: Core balance modules use solid `#103E37` with layered background micro-gradients (`radial-gradient(ellipse at top right, rgba(185, 233, 207, 0.15), transparent 70%)`), creating deep spatial focus without elevation layers.

## Shapes

The geometric form language uses gentle 16-20px rounded containers (`roundedness: 2`), reflecting the brand's mascot curvature while retaining functional card clarity.

### Shape Scale Applications
- **Base Components (`rounded-md`, 8px)**: Inline tags, currency micro-badges, inputs, segmented control pills.
- **Containers & Cards (`rounded-lg`, 16px to 20px)**: Primary bank cards, savings goal containers (*cofrinhos*), data tables, and bottom sheet containers.
- **Hero & Dialog Elements (`rounded-xl`, 24px)**: Main balance container, welcome card widgets, and desktop modal panels.
- **Pill Shapes (`rounded-full`, 9999px)**: Environment switchers (*Pessoal / Profissional / Consolidado*), status pills, avatar containers, and quick action icon wrappers.

## Components

### Buttons
- **Primary**: Solid Pine Green (`#103E37`) background, Warm Ivory (`#FFF9F1`) text, `border-radius: 9999px` or `12px`. Hover state lightens slightly via `rgba(255, 255, 255, 0.08)` overlay. Height: 48px on mobile, 44px on desktop.
- **Secondary**: Transparent with border `1px solid rgba(16, 62, 55, 0.16)`, `#103E37` text. On hover, background shifts to `rgba(16, 62, 55, 0.04)`.
- **Tertiary / Cofrinho Special**: Tinted Pig Pink (`#F3A9B8`) background with deep Charcoal (`#1D2925`) text for savings triggers and deposit actions.

### Environment Switcher (Scope Toggle)
- Centered segmented pill container (`#FFFFFF` or `rgba(16, 62, 55, 0.06)`) housing three states: *Pessoal*, *Profissional*, and *Consolidado*.
- Active segment glides with a smooth cubic-bezier transition, styled with solid `#103E37` and `#FFF9F1` text (or `#FFFFFF` with high-contrast text depending on container mode), establishing unambiguous context for business versus personal tax deductions.

### Cards & Metric Panels
- **Hero Balance Card**: Inverted pine container (`#103E37`). Displays "Saldo total", masked value toggle button (eye icon), action cluster (Pix, Pagar, Transferir, Cofrinho), and an integrated mint badge indicator (+X.X% CDI).
- **Goal Cards (*Cofrinhos*)**: White surfaces with a top Pig Pink (`#F3A9B8`) micro-tag, title in `headline-sm`, dual balance readout (current vs. target), and an animated track in `#F3A9B8` or `#B9E9CF`.

### Inputs & Financial Entry
- Fixed minimum height of 48px. Solid White (`#FFFFFF`) surface, subtle border `1px solid #E8E2D8`.
- Focus state: `border-color: #103E37` with an ambient ring: `box-shadow: 0 0 0 3px rgba(16, 62, 55, 0.12)`.
- Currency entry fields display a stationary "R$" prefix in neutral charcoal with large tabular numbers (`24px` to `32px`).

### Chips & Badges
- **Status Tags**: Rounded pill form (`rounded-full`), vertical padding `4px`, horizontal `10px`. 
- **Income / Rendimento**: Background `#B9E9CF` with dark Pine (`#103E37`) text.
- **Reserva / Meta**: Background `rgba(243, 169, 184, 0.35)` with `#1D2925` text.

### Lists & Transactions
- Edge-to-edge inside white cards with `1px solid rgba(16, 62, 55, 0.04)` separators.
- Categorized leading icon embedded in a 40x40px rounded container.
- Two-line data hierarchy: Merchant/Contact name + Category (`body-md` / `body-sm`), trailing numerical balance aligned right with positive entries prefixed by `+` in dark green and outgoing in charcoal.