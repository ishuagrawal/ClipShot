# Product

## Register

product

## Users

Developers, designers, and writers who capture UI components from any app to drop into docs, bug reports, PRs, and social posts. They are fluent in tools like Figma, Linear, CleanShot, and Raycast. They arrive mid-task: capture, frame, annotate, export, leave. Sessions are short and goal-directed.

## Product Purpose

ClipShot captures a precise component (not a loose rectangle) and turns it into a presentable image: auto-detected boundaries, smart padding, generated backgrounds, annotations, export. Success: the exported image looks deliberately art-directed with near-zero manual work.

## Brand Personality

Precision instrument with warmth. Three words: exacting, crafted, quiet. The editor should feel like a drafting table in a well-lit studio: the captured image is the single hero, the chrome is dark and recedes, and every number (dimensions, padding, zoom) reads like it came off a measuring tool.

## Anti-references

- The previous in-app theme: cool neutral gray + teal accent, interchangeable with any 2024 dark SaaS tool. Explicitly rejected by the owner as "soulless, repetitive, sloppy."
- Figma/Linear cosplay: cool dark gray + electric blue/purple accent.
- Glassmorphism, gradient-text, glow-heavy "AI tool" aesthetics.
- Light-mode utility look (Xnapper, Shottr).

## Design Principles

1. **The image is the hero.** Chrome is dark, warm, and flat; the canvas stage gets the contrast budget. Nothing in the UI may compete with the screenshot's own colors.
2. **Measure like an instrument.** Every numeric value (px, %, ratios) is monospaced, aligned, and live. Dimensions and zoom read like a HUD, not like form fields.
3. **Drafting-table materiality.** The canvas is a workbench: dot-grid stage, crop-mark corner ticks on the artboard, registration-mark accent color. Decoration only where it communicates "this is a precision surface."
4. **One accent, spent on state.** Vermilion marks selection, focus, and the primary action. Never decoration, never inactive chrome.
5. **Earned familiarity.** Standard macOS affordances (sidebar, toolbar, sliders, shortcuts). Distinctiveness comes from material and type, not invented controls.

## Accessibility & Inclusion

- Text contrast ≥4.5:1 on its actual surface; large/bold ≥3:1.
- All controls keyboard-reachable; existing accessibility labels preserved or improved.
- Hover-only affordances must have a visible resting state.
- Motion: 120–250 ms state transitions only; respect Reduce Motion for anything larger.
