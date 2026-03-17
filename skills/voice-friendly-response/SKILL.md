# SKILL: voice-friendly-response

## Purpose

The `voice-friendly-response` skill adapts technical output from any other skill into a format that is easy to understand when spoken aloud, read quickly on a small screen, or delivered to someone with limited technical background. It shortens dense explanations, converts lists into numbered field steps, removes jargon, and produces language-localized versions when the community uses a language other than English.

This skill produces communication, not infrastructure actions.

---

## Responsibilities

### Must do

- Accept a technical response or structured output from another skill and transform it into a voice-friendly version.
- Shorten explanations to their essential meaning: what is the situation, what does it mean for the user, what should they do next.
- Convert bullet lists or technical enumerations into numbered, actionable steps suitable for reading aloud or following step by step.
- Remove or translate jargon: replace technical terms with plain equivalents where available (e.g. "node" → "router," "RSSI" → "signal strength," "DNS" → "name lookup").
- Produce a version in the community's preferred language when configured or when explicitly requested.
- Keep voice summaries short: a good voice summary is three to five sentences or five to seven numbered steps at most.
- Preserve accuracy: simplification must not change the meaning or omit critical safety information.
- Produce a "one-line status" version for use in alerts, notification banners, or quick status messages.
- Preserve a "full version" alongside the simplified version when the requester may want to share both.

### Must not do

- Perform any infrastructure actions.
- Change the underlying data or findings from the originating skill.
- Omit warnings, escalation recommendations, or risk information in the simplified version — these must always be present, even if phrased simply.
- Invent information not present in the source response.
- Produce audio files directly (this skill produces text for a voice channel or TTS system to speak).

---

## Inputs

- Source response: the technical output or summary from another skill (e.g. `mesh-readonly`, `server-readonly`, `incident-triage`).
- Optional: target language (ISO code or community-configured language preference).
- Optional: output format hint — "voice summary," "field steps," "one-line status," "simplified explanation."
- Optional: audience hint — "field volunteer," "community member," "maintainer" (affects technical depth).

---

## Outputs

- **Voice-friendly summary**: three to five sentences in plain language covering the key finding, what it means, and the most important next step.
- **Numbered field steps** (when the source response included action steps): a numbered list, each step short enough to be read aloud as a single instruction.
- **One-line status** (always produced): a single sentence suitable for a notification, alert banner, or quick reply.
- **Localized version** (when requested or configured): the same output produced in the community's preferred language.
- Optional: the original technical summary preserved alongside the simplified version for maintainer reference.

---

## Risk Class

**Class A — Read-only / communication only**

This skill only transforms existing content. It produces no infrastructure changes and requires no approval.

---

## Activation Examples

- "Give me a voice summary."
- "Explain this in simple Portuguese."
- "Can you say that more simply?"
- "Give me the field steps I can read to the volunteer."
- "Summarize this for the group chat."
- "What's the one-line status for the alert?"
- "My grandmother needs to understand what's wrong — can you simplify?"
- "Translate the mesh report into Spanish."
- "Give me a version I can read over the phone."
- "Make the triage checklist into numbered steps."
- "Explain in simple language what happened."
- "I'm in the field — give me just the steps."

---

## Language Support

The skill should support at minimum the language(s) used by the community. Common configurations include:

- Portuguese (pt-BR or pt-PT)
- Spanish (es)
- English (en)
- French (fr)
- Other languages as configured in the workspace

The default language should be set in the workspace community profile. Requests in a specific language should always be honored.

---

## Constraints and Guardrails

1. **Accuracy over brevity**: if simplification would lose critical safety information or change the meaning, add a brief plain-language note instead of removing the information. Never sacrifice accuracy for shortness.
2. **Warnings must survive simplification**: any escalation recommendation, safety warning, or "stop and call someone" instruction from the source skill must appear in the simplified output, even if phrased in the simplest possible terms.
3. **No hallucination**: do not add context, causes, or steps that were not present in the source response.
4. **Jargon glossary**: maintain a community-specific glossary of preferred plain-language terms. When a technical term is used in a simplified output, it should be the same plain-language equivalent every time, so community members learn consistent vocabulary.
5. **Length discipline**: voice summaries must not exceed five sentences. Field checklists must not exceed ten steps. If the source material is longer, prioritize the most important information and add "ask for more detail if needed" at the end.
6. **Localization quality**: machine translation is acceptable as a starting point, but translations should be reviewed by a community member over time and common phrases should be stored in the workspace for reuse.
7. **Format consistency**: when producing numbered steps, always use the format "Step 1: [action]." This makes it easy to follow along whether reading or listening.
8. **Tone**: calm, clear, supportive. For outage situations, acknowledge the problem briefly and move directly to what can be done. Do not dramatize or minimize.
