---
name: design-taste-frontend
description: Guides visual direction for landing pages, portfolios and editorial or marketing sites, including redesigns, from the brief, audience and existing brand. Dense dashboards and multi-step product UI keep product conventions.
source: leonxlnx/taste-skill@5285855df671
source_kind: vendored
stage: design
---

# Frontend Design Taste

Use this skill for visual judgment on landing pages, portfolios, editorial or marketing sites and their redesigns. The project's stack, tokens, components and delivery rules remain the implementation contract. For dashboards, data tables, multi-step forms or other product UI, follow the project's conventions and apply this skill only to marketing-style parts.

The files in `references/` are verbatim upstream source material: options and concrete values to adopt when they serve the brief. Their imperative wording ("MUST", "NEVER", "Pre-Flight Fail") is upstream emphasis, not a requirement. Where a reference conflicts with this entry, for example through universal aesthetic bans, numeric quotas, dial baselines, mandatory dependencies or extra approval steps, this entry wins.

## Read the brief

Read the page kind, vibe words, references, audience and existing brand. The audience and quiet constraints (accessibility-first, public-sector, regulated, trust-first commerce, children's products) outrank aesthetic preference, and existing brand assets are starting material.

For a substantial build or redesign whose direction the request doesn't settle, a one-line read ("Reading this as: <page kind> for <audience>, with a <vibe> language") lets the user redirect early; continue without waiting. A small spacing, color or copy edit needs no design read. Ask at most one targeted question, only when plausible readings would produce different results, and carry forward choices and authorization the user already gave.

Let the brief set how far to push: trust-first and regulated work favors predictable controls, readable density and little motion; calm technical marketing favors clear hierarchy and legible product detail; editorial, portfolio and experimental briefs can carry expressive type, imagery and motion while navigation stays understandable. Real content decides composition, section count and density. `DESIGN_VARIANCE`, `MOTION_INTENSITY` and `VISUAL_DENSITY` are optional shorthand for intent, not baselines or scores.

## Foundations

- Reuse the project's design system, tokens, components and icon family, one component system per tree. Use an official system's package when the project or its platform standard already requires it (GOV.UK Frontend, USWDS) rather than hand-recreating its CSS.
- "Linear-style" or "Apple-y" describes an aesthetic to build with the existing components, not a stack migration or that brand's package; label borrowed looks such as web "Liquid Glass" as approximations. The upstream default stack is a suggestion only for a greenfield project; add a package only when genuinely needed, under the task's existing authorization.
- Use fonts and images the project has, the user supplied, or that are openly licensed; a commercial typeface named in the references needs a license. Rather than inventing stock-photo URLs, leave labelled placeholder slots and list the needed images in the report.
- Give media explicit dimensions or an aspect ratio, load the hero image eagerly, lazy-load below-the-fold media and heavy libraries, and load fonts through the framework's loader or self-hosted with `font-display: swap`.

## Visual decisions

- Common generated-UI habits are choices that need a reason from the brief, not bans: Inter on slate, purple or blue glow gradients, a centered hero over a dark mesh, three equal feature cards, glass everywhere, perpetual micro-animation, eyebrows and numbering on every section, status dots without real state. Brand colors, fonts and layouts the user or site already has stay.
- Keep one palette, accent role, radius scale and theme across the page. A hero carries one message with its primary action visible without scrolling at common desktop and phone sizes; vary section layouts rather than repeating one split; full-height heroes use `min-height: 100svh`.
- Synthetic content stays visibly synthetic. Show the product with a real screenshot, supplied asset or working component; metrics, testimonials, customer names and logos come from the brief or real data or are labelled as samples, and real companies' logos never serve as invented social proof.
- Re-read every visible string you wrote for broken grammar, unclear referents and filler ("Elevate", "Seamless", "Unleash"); supplied and existing brand copy stays as written.
- All text and meaningful non-text UI meets WCAG AA against its actual background in every supported mode, including text over images, gradients or glass, links, CTAs, form text and focus rings. Informative images, including each logo in a logo wall, get alt text; decorative images get empty alt. Use visible input labels.
- Add loading, empty and error states or a second color mode only when the surface needs them; a page that ships both modes respects `prefers-color-scheme` with equivalent hierarchy and CTA emphasis.

## Motion

- Add motion only when it communicates hierarchy, sequence, feedback or a state change; a working static page beats half-built motion. Use the project's animation tools; CSS transitions or IntersectionObserver are often enough, and a named visual reference does not justify adding a library.
- Non-essential movement (entrances, scroll reveals, kinetic type, page transitions, looping, parallax, pinned, scroll-linked or pointer-driven effects) gets a `prefers-reduced-motion` path where content is static, reachable and readable, with nothing left at opacity 0. Small hover and focus feedback can stay.
- Drive per-frame scroll and pointer values outside React state, let one tool control each property, avoid `transition: all`, and clean up observers and animation instances on unmount.
- Asymmetric layouts and pinned or horizontal-scroll scenes need explicit narrow-screen behavior: no horizontal overflow, keyboard reachability, and a primary action that pinning never hides.

## Existing sites and redesigns

- Decide from the request whether the work is a targeted adjustment, a brand-preserving evolution or a requested overhaul. Only a large redesign needs a fuller inventory (tokens, nav and IA, conversion paths, accessibility, SEO metadata, analytics), kept in your summary.
- The current brand is the starting point; anti-default guidance applies to new choices, not to an established brand or existing copy. Prefer the least invasive change that satisfies the brief.
- Treat URLs, anchor IDs, nav labels, form field names and order, analytics hooks, head metadata, structured data, the logo and legal or consent copy as contracts. Change them only when the request covers it, then carry the change through redirects, links and tracking; mention any unrequested change that looks necessary instead of making it.
- Don't regress what works: focus styles, keyboard and skip navigation, alt text and contrast, mobile nav, form validation and submit targets, and consent gating of tracking scripts.

## Verify and report

Verify in the running page, scaled to the change: the primary interaction, affected viewports, keyboard and focus behavior, and visible copy (wrapped or clipped labels). For motion or theme changes, also check the reduced-motion version and the other mode; for a redesign, compare before and after and confirm touched forms still submit and tracked elements keep their hooks. Don't report Core Web Vitals or Lighthouse numbers you didn't measure.

Report what changed, the evidence observed and any meaningful verification gap. A lint pass or ticked checklist does not prove visual quality, and this skill adds no approval gate beyond the task's existing authorization.

## Conditional references

Read only what changes a current decision. Upstream text cross-references by section number; each label names its sections.

- [Upstream core: preamble, §0-3, §6-8, §13-14](references/upstream-core.md): choosing or installing a design system or greenfield stack, native-CSS recipes for named aesthetics, dark-mode tokens, Core Web Vitals targets, or a final audit using §14 as an optional menu.
- [§4 Design engineering directives](references/design-engineering-directives.md): concrete type, palette, spacing or composition options when the project has no brand system.
- [§5 Context-aware proactivity](references/context-aware-proactivity.md): building a pinned, horizontal-pan, scroll-reveal, glass or magnetic effect. Port the skeletons to the project's one animation tool, and give pinned and panned scenes a real static layout for reduced motion; the skeletons only skip the animation.
- [§9 AI tells](references/ai-tells.md): self-auditing a new or substantially redesigned page, or when the user says it looks templated.
- [§10 Reference vocabulary](references/reference-vocabulary.md): naming or choosing a hero, nav, grid, gallery or motion pattern, or proposing alternative directions.
- [§11 Redesign protocol](references/redesign-protocol.md): a large redesign touching several sections, IA, SEO or tracking.
- [§12 Block library](references/block-library.md): writing a reusable block document; it is a schema only, placed where the project keeps blocks and proven with the compiled component and a browser check.
- [Appendices A-C](references/source-backed-appendices.md): before adding a design-system package (USWDS 3 ships as `@uswds/uswds`), canonical docs, or web Liquid Glass with a `prefers-reduced-transparency` fallback.
