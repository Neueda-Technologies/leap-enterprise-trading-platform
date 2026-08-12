# Sprint 11: cloud deployment and the showcase

Eight sprints of platform run on your laptops. That is not a criticism of the
build. It is the reason nobody outside this room has ever used it, and it is the
one property a trading platform cannot keep. Somebody has to be able to open a
browser, anywhere, and reach the application over a link you can send them.

This week you put the front end somewhere that link works from, and then you
stand in front of a panel and demonstrate the whole platform. The two halves are
not separate: the deployed link is what the panel loads while you talk.

Only the Angular application is deployed. Postgres, Kafka, the Trade REST API,
the Auth service, the Trade Executor, the poller, the pipeline and your extension
all stay on Docker Compose, on your machines, exactly as they are. Deploying them
is out of scope for this programme and it is not what the criteria ask for. Read
the section on verification before you decide that sounds easier than it is.

## What changes when the front end leaves localhost

Two things that never mattered before start to matter on the Monday.

**The build has to be reproducible.** Until now, `ng serve` on your machine was
the product. The bundle in `dist/` was a by-product of a command somebody ran
once, on a laptop with a particular `node_modules`, and if it was subtly wrong
you found out by refreshing. From this week the bundle is the artefact. What is
in the bucket is what every user gets, so the command that produced it has to
produce the same thing when a teammate runs it, when a runner runs it, and when
you run it again on Friday morning with the panel waiting. That is why the
deployment cycle below starts at `npm ci` and not at "the files that happen to be
in `dist/`".

**A secret in the bundle is now published.** Sprint 9 checked your bundle for
keys and secrets, and a team who scraped through that check on the argument that
the bundle only ever loaded on localhost has run out of argument. The bundle is
now a public object on a CDN, fetched by anyone who opens the link and cached at
edge locations you do not control. A key that reaches it has been disclosed, and
disclosure is not undone by a later commit that removes it. The same rule applies
to the credentials that do the deploying, which is what the IAM section is about.

## The target architecture

Three components, and one rule that fixes how they fit together.

| Component | What it is |
|---|---|
| An S3 bucket | Holds the built Angular application. Private. Blocks all public access. Never addressed directly by a browser. |
| An origin access control | The credential CloudFront presents to S3 when it fetches an object. It is what the bucket trusts. |
| A CloudFront distribution | The public face. Terminates TLS, serves over HTTPS, caches at the edge, and is the only reader the bucket accepts. |

The rule is that the bucket is unreachable except through the distribution. A
browser that resolves your bucket's own endpoint gets access denied. A browser
that loads your `*.cloudfront.net` domain gets the application. That is not a
detail of configuration, it is the shape being assessed.

### Why a public bucket policy fails this sprint

S3 will happily host a static site on its own. Enable website hosting, attach a
bucket policy granting `s3:GetObject` to `"Principal": "*"`, and the application
loads in a browser. It works. It is also the wrong answer here, and a team who
does it fails the sprint with a working site on screen.

Three reasons, in the order they would bite you in a real organisation.

The bucket endpoint serves over plain HTTP as well as HTTPS, so a public bucket
means your login form is reachable unencrypted. Anything you put in the bucket is
world-readable by anyone who guesses the name, not only the files you meant to
publish, which turns an accidental upload into a disclosure. And you cannot put a
cache, a compression setting or an error-page rule in front of a bucket that is
being read directly, so every one of those decisions disappears.

The general principle is worth more than the three reasons: origin access control
means the origin trusts exactly one caller, named and verified. A public policy
means the origin trusts the internet and hopes that the only thing pointing at it
is your CDN. The first is a control. The second is a convention.

There is a second consequence you will meet on the first deep link. Behind an
origin access control, a request for a key that does not exist comes back as
`403`, not `404`, because an anonymous caller is not permitted to know whether an
object exists. Your Angular router owns paths like `/dashboard` and `/orders/42`,
and there is no object at either key. Work out what that does to a page refresh
on any route but the root, and what the distribution has to be told to do about
it. It is one setting and it will be the first thing the panel finds if you have
not.

## Region and cost

CloudFront is a global edge network, so the region you choose only decides where
the bucket lives. Pick the one nearest the cohort, `eu-west-2` for Ireland and the
UK, `us-east-1` for the US, and use the same one everywhere for the rest of the
week. Region names appear in bucket endpoints, in ARNs and in CLI calls, and a
distribution pointed at a bucket in a region you have half-migrated away from
produces error messages that read like something else entirely. If a call reports
that your bucket must be addressed using a different endpoint, you have two
regions in play, not a broken bucket.

The deployment itself costs close to nothing. One Angular build is a few
megabytes of storage, and a training cohort generates a request volume that sits
inside the free usage allowances comfortably. Confirm the current terms before
relying on them, because they change. The real cost risk is not the deployment,
it is forgetting it exists: a bucket and a distribution per team, left running
after the showcase, is a bill that arrives quietly for months. So one instruction
matters more than any of the numbers. Tear it down when you are told to, on the
day you are told to, and check it is gone rather than assuming it is.

## The deployment cycle as a contract

Deployment is one command. Not a sequence of commands in a teammate's shell
history, not a runbook of five steps that a person executes in order, and not a
console upload.

That single entry point does three things, in this order:

1. **Build.** A clean, reproducible install and a production build of the Angular
   application.
2. **Upload.** The build output into the bucket, so that the bucket ends up
   holding this build and not a mixture of this build and the last one.
3. **Invalidate.** The CloudFront cache, so that the next request gets what you
   just uploaded rather than what the edge is still holding.

The third step is the one teams skip, and skipping it produces the most expensive
bug of the week: you deploy a fix, you load the link, you see the old
application, and you spend an hour debugging code that is not running. Cached
objects are served until they expire or until you invalidate them.

Step two carries a decision worth taking deliberately. Your build produces two
families of file. The hashed assets, `main.<hash>.js` and its neighbours, are
content-addressed: a given filename never changes content, so they can be cached
for a very long time. `index.html` is not hashed, and it is the pointer to which
hashed assets are current, so it must never be served stale. Set the cache
headers accordingly on upload, and your invalidation shrinks to a single path.

**A second run must be safe.** Running your entry point twice, against the same
commit, has to leave the deployment in the same state as running it once, and it
has to leave a working site both times. That is the property that makes a deploy
something you can do at four o'clock on a Friday with a panel in the room. Test it
by running it twice and loading the site in between, not by reasoning about it.

The entry point is a shell script you run locally. A team that splits it across
more than one file should keep one script that calls the others, so that the
stages cannot drift apart. Declare its path in `manifest.env`.

## IAM scoping

**Nothing in this section is attempted before the guardrails briefing.** A
Fidelity platform SME briefs the cohort on how Fidelity governs its own AWS
estate before any hands-on cloud work starts. That session is a briefing, not a
lab: you deploy nothing to anything belonging to Fidelity. Attend it first,
because the reason the criteria below are shaped the way they are is a great deal
clearer afterwards.

Two identities are in play this week and they must not be the same one.

The **setup identity** creates the bucket, the origin access control, the
distribution and the deploy user. It is broad by necessity, it is used by a human,
by hand, once.

The **deploy identity** is what the automation runs as. It can write objects into
one named bucket and create an invalidation on one named distribution. It cannot
create a bucket, cannot read another bucket, cannot touch another distribution,
and cannot create a user. If your deploy credentials were pasted into a public
issue tomorrow, the worst an attacker could do is replace the contents of a
training front end. That containment is the whole point of the exercise.

`iam/policy-skeleton.json` in this folder is the shape, not the answer. It has
three statements, and the resource ARNs are placeholders you replace with your
own bucket name, account id and distribution id. The actions are left for you to
work out, and working them out is the exercise:

| Statement | What it has to permit, and why |
|---|---|
| `ListTargetBucket` | The bucket-level action a sync needs in order to work out what is already there and what has to change. Note the resource ARN has no `/*` on the end: this is a permission on the bucket, not on objects in it. |
| `WriteObjectsInTargetBucket` | The object-level actions an upload needs. Work out from your own upload command which ones it calls, including what happens when a file present in the last build is absent from this one. The resource ARN ends `/*` because these act on objects. |
| `InvalidateTargetDistribution` | Creating an invalidation, and reading its status if your script waits for it to finish. Scoped to your one distribution ARN. |

Two rules on the credentials themselves, and neither is negotiable.

**No long-lived key goes into the repository, ever, in any branch.** Not in a
config file, not in a `.env` that slipped past `.gitignore`, not in a comment, not
in a screenshot pasted into a document, not in a test fixture. The harness
searches your working tree for the shape of an access key, and it also searches
the history of this sprint's files, because a key that was committed and then
deleted is still a disclosed key and still fails the review.

**Store the pair where the thing that needs it can read it and nobody else can.**
Configure a named AWS CLI profile rather than exporting keys into your shell
history, and let the script pick that profile up by name. Non-secret identifiers,
the region, the bucket name and the distribution id, are arguments or environment
variables rather than secrets, and treating them as secrets only makes the real
secrets harder to find.

The AWS CLI command families this week needs are small: `aws s3api` and `aws s3`
for the bucket and the upload, `aws cloudfront` for the origin access control,
the distribution and the invalidation, `aws iam` for the deploy user and its
policy, and `aws sts get-caller-identity` when you need your own account id.
Everything else in the CLI is out of scope.

## Verifying against the deployed front end

A deployed page that renders is not a deployed application. The criterion is that
the authenticated flows work against the deployed URL: sign in as a real user,
place an order, watch it reach the blotter, all of it driven from the CloudFront
domain rather than from `localhost:4200`.

That is the point at which the architecture bites, and it is meant to. Your API
is still on your machine. The application is now served from an origin that is
not your machine. Two consequences follow, and you own both of them.

**The API base URL.** The bundle you upload contains whatever address it was
built with. Built one way, the deployed page asks a host that has nothing on it.
Built another way, it asks a host only the person who built it can reach. Decide
what the deployed build points at, decide how that address gets into the build
without becoming a value someone edits by hand before every deploy, and be ready
to explain the choice. Sprint 9 gave you Angular environments and the same rule
about secrets applies: an address is not a secret, a key is.

**Cross-origin requests.** The page's origin is now your distribution domain over
HTTPS. Your Trade REST API and your Auth service have, until this week, only ever
been asked for data by a page served from the same machine that served them. They
are about to be asked by a page served from somewhere else, over HTTPS, by a
browser that will not deliver the response to your JavaScript unless the service
says it may. Work out what has to change, where it has to change,
whether allowing every origin is an acceptable answer for a service that holds
customer positions, and what the mixed-content rule does to an HTTPS page calling
a plain HTTP API.

Neither problem has a single right answer, both have several wrong ones, and both
are exactly the class of problem that turns up on the first day of a real
deployment. Solve them, write down what you chose in your decision log, and
expect the panel to ask why.

If you reach Thursday with the deployed page loading but the authenticated flow
only working against the local development server, say so plainly at the
showcase, demonstrate what does work from the deployed URL, and explain the
blocker. A team that understands its own gap is in a better position than a team
that hides it behind a screen recording.

## The showcase

The final demonstration is to a panel, live, against your running platform and
your deployed link. It covers five things, and a team that prepares only the
first is the team that runs out of things to say after ten minutes.

| What the panel expects | What that means in practice |
|---|---|
| The platform | A customer signs in, places an order, and sees it filled. Show the path through the services while it happens, not a diagram of it afterwards. |
| The extension | What you chose in Sprint 10, why that one, what you deliberately left out, and it running on live data. |
| Design decisions | Two or three choices you would defend, from your decision log. The partition key, the fill rule, the authorisation model, the API base URL decision you took this week. What you rejected matters as much as what you chose. |
| Copilot usage | Where it helped, where it was wrong, and what you did to know the difference. A team that says it was useful everywhere has not been paying attention, and a team that says it was never used has not either. |
| The code-quality story | The SonarQube gate, the security reviews, the tests, the refactoring you did in Sprint 7 and the findings you closed in Sprint 10. Bring the numbers rather than the adjectives. |

**Timing is part of the assessment.** Your instructor confirms the slot length in
the first session of the week. Whatever it is, roughly half of it belongs to the
live platform demonstration, a quarter to the design decisions and the
quality story, and the rest to questions. Rehearse against a clock, at least
twice, with the stack actually running. A demonstration that overruns is stopped,
and what gets cut is the end, which is where the quality story lives.

**Everybody talks and everybody can be asked about anything.** Split the
demonstration so that every member of the team presents a section. That is the
minimum, not the target: the panel may ask any member about any component,
including the parts they did not write, and "that was someone else's bit" is the
answer this programme has spent twelve weeks making sure you do not need. Rotate
who explains what during rehearsal and you will find the gaps while there is
still time to close them.

**Prepare for the demonstration to misbehave.** Live data means the thing you
show can move under you, the quota can bite, and a container can be down. Have
your fallback agreed before you are standing up: what you show instead, who
notices, who says it. Write it in the checklist rather than improvising it.

`showcase/CHECKLIST.md` is a committed file. Fill it in and commit it during the
week, not on the morning: it is the artefact the panel reads before you start and
the thing your team argues over while there is still time for the argument to be
useful.

## What is in this folder

```
README.md                 this brief
showcase/CHECKLIST.md     the panel-facing plan, filled in and committed
iam/policy-skeleton.json  the shape of the deploy policy, ARNs as placeholders
manifest.env              the names the harness reads
scripts/check.sh          the acceptance harness
```

Your deployment entry point does not live here. A script belongs at a sensible
path in the repository, and `deploy/deploy-ui.sh` is a reasonable one. Name its
path in `manifest.env` so the harness can find it.

## The harness

`scripts/check.sh` runs in two modes.

```bash
scripts/check.sh
scripts/check.sh --live
```

Static mode reads `manifest.env`, checks the shape of your declared bucket name
and CloudFront domain, confirms your deployment entry point exists at the path
you declared and covers the build, upload and invalidate stages, and searches the
repository for anything shaped like an AWS access key.

Live mode needs the deployment to exist and needs network access. It fetches your
CloudFront domain over HTTPS and confirms the answer is your Angular application
rather than an error page, probes your bucket's own endpoints and confirms they
refuse, then fetches the JavaScript bundles the deployed page references and runs
the Sprint 9 secret patterns over them.

Two things about this harness are worth saying plainly.

It is lighter than every harness before it. Most of what this sprint is assessed
on happens in an AWS account the harness has no credentials for and in a room it
is not in. It cannot see your origin access control, it cannot see your IAM
policy, it cannot see whether a human approved the deploy, and it cannot watch
your showcase.

It depends on the network, so it can fail for reasons that are nothing to do with
you. A distribution that has just been created takes minutes to reach `Deployed`
and answers oddly until it does. An invalidation in flight can serve you the
previous build. A failure in live mode is worth a second run before it is worth
an hour of debugging.

Every skip names itself and says what would make it run. A skip is honest. A
green run against something that was not there is not.

## Acceptance criteria

These are the criteria your instructor assesses against.

1. The application is reachable over HTTPS through the CloudFront distribution.
2. The S3 bucket is private and returns access denied when it is addressed
   directly.
3. Origin access control is configured. A public bucket policy does not satisfy
   this, whether or not the site loads.
4. Deployment is a single script covering build, upload and invalidation.
5. The authenticated flows are verified against the deployed front end.
6. The IAM user or role is scoped to the bucket and the distribution only, and no
   long-lived key is in the repository.
7. The team gives a live demonstration to the panel covering the platform, the
   extension, design decisions, Copilot usage and the code-quality story.

## What a person assesses

Say it plainly, because the harness is short enough to be mistaken for the
assessment. The harness can tell you that a URL answered, that a bucket refused,
that a file exists and mentions three stages, and that no key-shaped string is in
your tree.

Everything the criteria turn on is read by a person. Whether the bucket is
private because of an origin access control or because you have not yet made it
public. Whether the deploy policy is scoped to your two resources or to `*`.
Whether the deployment is one command or a runbook that one member of the team
can execute. Whether a second run leaves it working. Whether the authenticated
flow ran from the deployed URL or from a development server with the deployed URL
open in another tab. Whether you can explain the choices behind any of it.

Then the panel asks you about the twelve weeks, and that part has no harness at
all.
