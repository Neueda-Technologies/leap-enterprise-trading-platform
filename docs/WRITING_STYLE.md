# Writing style

Status: binding. Every authored file in this repository follows this guide. That includes week briefs, READMEs, contract descriptions, SQL comment headers, commit-adjacent documentation and any instructor-facing note.

## Why this exists

Participants read these documents while they are under time pressure and already carrying a heavy cognitive load. Prose that sounds generated, hedges, or pads its word count costs them attention they need for the code. A consistent voice also lets a dozen different authors, human and agent, produce material that reads as one course rather than a folder of drafts.

## Voice

Write as an expert instructor briefing engineers who are capable but new to the domain. Assume competence. Explain the reasoning, then the instruction. Stop when the point is made.

## Rules

### Punctuation and characters

- No em-dashes anywhere. Use a comma, a colon, parentheses, or split the sentence.
- No exclamation marks.
- No emoji, and no decorative symbols standing in for words.
- Hyphens are for compound modifiers only (event-driven, at-least-once, sentence-case).
- Use straight quotes and apostrophes.

### Banned phrasing

Never use: delve, leverage (as a verb), seamless, robust, comprehensive, "let's", "simply", "just" as a minimiser, "dive in", "in this guide we will", "welcome to", "it's worth noting", "at the end of the day", "unlock", "empower", "game-changer", "best-in-class".

Do not open a section by announcing what the section will do. Start with the content.

### Sentences

- Short and declarative. One idea per sentence.
- Imperative mood for anything the reader must do: "Create the topic with three partitions", not "You will want to create the topic".
- Active voice by default. Passive is acceptable when the actor is genuinely irrelevant.
- No filler praise, no cheerleading, no motivational framing. Do not tell the reader that a task is exciting, easy, or a great opportunity.
- Do not apologise for difficulty either. State the difficulty and move on.

### Structure

- Sentence-case headings. "Order placement flow", not "Order Placement Flow".
- In every week brief, explain the why before the what. Open with the reason this component exists in the platform and what breaks without it, then state the deliverable.
- Prefer tables for anything with more than three parallel attributes.
- Code, endpoint paths, table names, topic names, environment variables and file paths go in backticks.
- Keep lists parallel in grammar and length.

### Spelling and terminology

British spelling, to match the source curriculum: normalised, Dockerised, serialised, initialise, behaviour, catalogue, organisation, analyse, licence (noun).

Keep American spelling only where it is part of a fixed technical token: `analytics`, `authorization` header, `Analytics` schema names, SQL keywords, library names, and anything copied verbatim from an API contract.

Fixed terms used across the programme, spelled exactly this way:

| Term | Use | Do not use |
|---|---|---|
| Trade REST API | The Spring Boot order and account service | trade-api service, Order API |
| Trade Executor | The Kafka consumer that fills orders | executor service, matching engine |
| Fauxnance API | The provided market-data API | pricing API, live pricing service |
| Auth service | The NestJS JWT service | identity service, auth server |
| Extension | A Sprint 10 team-selected microservice | plugin, add-on, module |
| Capstone | The whole platform build | project, assignment |
| Sprint N | The taught week. Folders are named `sprint-NN-slug`, and calendar weeks appear in prose and tables only | week N as the name of a sprint, week numbers in folder names |

## Before and after

Typical generated paragraph:

> Welcome to Sprint 7! In this guide we will dive into the exciting world of event-driven architecture. Kafka is a robust, industry-standard platform that will empower your team to build a seamless real-time backbone. Let's delve into the topics you'll need to create - it's simpler than it looks!

Rewritten to the target voice:

> Until now, an order is placed and filled inside one HTTP request. Real trading systems cannot work that way: execution takes time, it fails, and it must survive a restart of the service that requested it. Sprint 7 separates the two. The Trade REST API records the order and publishes it; a separate consumer executes it and publishes the result.
>
> Create three topics: `orders`, `trade-events` and `market-data`. Key every message by `accountId` so that all events for one account land on the same partition and stay ordered.

What changed: the greeting and the promise of the guide are gone, the product adjectives are gone, the reason for the change is stated before the instruction, and the instruction is imperative and specific.

## Checking your own draft

Before committing authored prose, confirm each of these:

1. No em-dash, exclamation mark or emoji appears in the file.
2. No banned phrase appears.
3. Every heading is sentence case.
4. Every week brief opens with why, not with what.
5. Spelling is British outside fixed technical tokens.
6. No sentence exceeds roughly 30 words without a good reason.
7. Nothing praises the reader or the technology.
