# Dev Log — Blank Page Between Section Heading and tcolorbox

**Date:** 2026-06-08  
**File:** `exercices_quantique_chapter_6.tex`  
**Class:** `ceri/sty/rapport.cls` (based on `report`, uses `titlesec`)

---

## Bug

A blank page appeared between the `\section*{Démonstrations}` heading and the
`\begin{demonstration}[...]` tcolorbox that followed it directly.

Attempted mitigations that did NOT work:
- `\nopagebreak[4]` between the heading and the box — ignored
- Switching tcolorbox skin from `enhanced` to `enhanced jigsaw` + `breakable` — box
  still landed on the next page

## Root Cause

`rapport.cls` loads `titlesec` and calls `\titleformat{\section}` to style section
headings. When titlesec is active, every `\section` (including the starred `\section*`
form) is processed through titlesec's internal machinery. That machinery computes
spacing *around* the heading using its own penalty/glue model — it does not respect
standard LaTeX `\nopagebreak` penalties inserted after the heading by the user.

The result: LaTeX saw the heading at the bottom of a short page and, because titlesec
had already consumed the penalty glue, freely moved the large tcolorbox to the next
page, leaving the heading stranded and producing a blank-looking page.

## Fix

Replaced `\section*{Démonstrations}` with a plain inline group that replicates the
visual output of `\titleformat{\section}` exactly — without invoking titlesec:

```latex
% BEFORE (broken)
\section*{Démonstrations}
\addcontentsline{toc}{section}{Démonstrations}
\nopagebreak[4]
\begin{demonstration}[...]

% AFTER (fixed)
\phantomsection
\addcontentsline{toc}{section}{Démonstrations}
{\color{fgRed}\normalfont\Large\bfseries Démonstrations}
\par\vspace{2mm}
\begin{demonstration}[...]
```

- `\phantomsection` — gives hyperref an anchor so the TOC hyperlink points to the
  correct page.
- `{\color{fgRed}\normalfont\Large\bfseries Démonstrations}` — matches the exact
  format defined by `\titleformat{\section}` in the class (red, Large, bfseries).
- `\par\vspace{2mm}` — closes the paragraph and adds a small gap before the box;
  being plain glue, it cannot trigger a page break on its own when the box is
  breakable.
- No titlesec machinery involved → no unexpected penalty model → the box starts
  immediately below the heading.

## Key Takeaway

When `titlesec` is loaded, **never rely on `\nopagebreak` placed after a `\section`
heading** to keep the next element on the same page. Titlesec replaces LaTeX's
native section code with its own formatter, and the formatter discards the user's
penalty. The only reliable fix is to avoid `\section{}`/`\section*{}` altogether
for that heading and replicate its appearance manually.
