---
name: humanizer
version: 2.8.2
description: |
  Remove signs of AI-generated writing from prose, docs, PRDs, specs, READMEs,
  release notes, comments, and user-facing copy. Use when the user asks to
  humanize, de-AI, make text sound natural, reduce chatbot tone, match a writing
  sample, or review text for AI tells. Based on blader/humanizer and Wikipedia's
  "Signs of AI writing" guide.
source: blader/humanizer@1b48564898e999219882660237fde01bf4843a0f
source_kind: adapted
stage: docs
maturity: experimental
license: MIT
---

# Humanizer

Use this skill to rewrite text that sounds generated, over-polished, promotional,
or padded. The goal is not to make text sloppy. The goal is to make it specific,
honest, and matched to the writer's real context.

Adapted from `blader/humanizer` v2.8.2. The upstream license is MIT and the
copyright notice is preserved in `LICENSE`.

## Fit in skill-commons

- Profile: optional utility.
- Stage: docs.
- Ground truth served: LLMs overproduce generic, evidence-light prose; durable
  artifacts need a consistent human-readable voice.
- Relationship to `STYLE.md`: `STYLE.md` is the repo-wide lintable writing rule.
  This skill is the rewrite process that applies those ideas to arbitrary text.
- Relationship to `markdown`: `markdown` organizes and converts documents.
  `humanizer` edits wording after the content exists.
- Relationship to `design-taste-frontend`: that skill removes visual slop from
  frontend UI. `humanizer` removes prose slop from text.

## Boundaries

Use this skill for:

- README, PRD, Spec, QA report, ADR, changelog, release note, landing page copy,
  blog post, support reply, proposal, or comment text that feels AI-generated.
- Text that needs to match a provided writing sample.
- Review-only passes where the user wants a list of AI tells without rewriting.

Do not use this skill to:

- Hide authorship when a school, employer, platform, or legal process requires
  AI disclosure.
- Make unsupported claims sound more confident.
- Invent personal anecdotes, sources, quotes, dates, or opinions.
- Add personality to legal, reference, API, or technical text where neutral prose
  is the right voice.

If the user's intent is to evade a required disclosure policy, refuse that part
and offer a transparent editing pass instead.

## Process

1. Identify the text and target audience.
2. Ask for a voice sample only when matching a specific author matters and the
   sample is not already available.
3. Scan for AI tells using the checklist below.
4. Rewrite the text while preserving meaning, scope, claims, and paragraph-level
   coverage.
5. Audit the rewrite for remaining tells.
6. Return the final text plus a short change note when useful.

## Voice calibration

If the user provides a writing sample, read it first and infer:

- sentence length and rhythm;
- word choice level;
- paragraph openings;
- punctuation habits;
- recurring phrases;
- transition style;
- how much uncertainty, humor, or first-person perspective the author normally
  uses.

Match the sample. Do not "upgrade" a casual writer into corporate prose.

When no sample exists, use a plain, specific, slightly varied voice. Let the text
sound like a person with context wrote it, not like a brand guide woke up and
started managing stakeholders.

## AI tells to remove

### Content tells

- Inflated significance: "pivotal", "crucial", "vital", "testament",
  "underscores", "marks a shift", "broader landscape".
- Fake depth from trailing `-ing` phrases: "showcasing", "highlighting",
  "reflecting", "symbolizing", "fostering".
- Promotional travel-brochure language: "nestled", "breathtaking", "vibrant",
  "renowned", "must-visit", "rich tapestry".
- Vague attribution: "experts say", "industry observers believe", "reports
  suggest" without naming the source.
- Formula sections: "Challenges and future prospects", "Despite challenges, X
  continues to thrive".
- Generic optimistic endings: "The future looks bright", "exciting times ahead".

### Language tells

- Overused AI vocabulary: "additionally", "delve", "enhance", "intricate",
  "interplay", "key", "landscape", "showcase", "tapestry", "valuable",
  "vibrant".
- Copula avoidance: "serves as", "stands as", "boasts", "features", when
  "is" or "has" is clearer.
- Negative parallelisms: "not just X, but Y", "not only X but also Y".
- Rule of three forced lists.
- Synonym cycling where one term should simply repeat.
- False ranges: "from X to Y" when X and Y do not form a real scale.
- Excessive hedging: "could potentially possibly", "it may be argued".

### Style tells

- Em dash and en dash dependence. Prefer periods, commas, colons, parentheses,
  or a rewritten sentence.
- Boldface used as mechanical emphasis.
- Vertical lists with bold inline labels when a sentence would do.
- Title Case headings in ordinary docs.
- Emojis in serious durable artifacts.
- Curly quotes when project style expects straight quotes.
- Diff-anchored writing outside changelogs: "This was added to replace...".
- Manufactured punchlines: stacked short sentences that all try to land.
- Aphorism formulas: "X is the Y of Z", "X is not a tool but a mirror".
- Fake-candid openers: "Honestly?", "Look,", "Here's the thing".

### Chatbot artifacts

- "I hope this helps."
- "Let me know if you want..."
- "Of course!"
- "Great question."
- "Would you like me to..."
- "Let's dive in."
- Knowledge-cutoff disclaimers pasted into user-facing text.
- Speculative filler where a source is missing.

## False-positive guard

Do not flatten every strong sentence. A human can write polished prose, use an
em dash, hedge carefully, or write a dry paragraph. Look for clusters of tells
and ask whether the text got less specific because of them.

Preserve:

- technical precision;
- sourced claims;
- a writer's real quirks;
- field-specific vocabulary;
- a deliberate formal tone;
- useful repetition when it improves clarity.

## Rewrite rules

- Preserve meaning and factual claims.
- Keep roughly the same coverage. If the input has five paragraphs, the output
  should normally have five paragraphs unless the user asks for a shorter edit.
- Replace generic claims with specific facts only when the facts are already in
  the text or supplied by the user.
- If the input lacks evidence, say so rather than inventing it.
- Prefer concrete nouns and verbs.
- Cut ceremony before cutting substance.
- Keep the audience in mind. A technical spec should become clearer, not chatty.

## Output formats

For a rewrite request:

```text
<rewritten text>

Change note:
- <short note about the main edits, only when useful>
```

For a review-only request:

```text
AI-writing tells found:
- <pattern>: <evidence> → <suggested fix>

Risk:
- <any fact, source, tone, or disclosure issue>
```

For text governed by disclosure rules:

```text
I can help edit this for clarity and voice, but I cannot help hide AI involvement
where disclosure is required.

Transparent edit:
<edited text>
```
