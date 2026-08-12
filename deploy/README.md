# Deploy

Status: reference implementation for Sprint 11 (`cloud-deploy`). Everything under `deploy/` exists to get the Angular build from `ui/` into a browser over HTTPS, and nothing else. The rest of the platform stays on Docker Compose.

## What is here

| File | Purpose |
|---|---|
| `deploy/setup-aws.md` | One-time walkthrough: create the S3 bucket, the CloudFront distribution and its origin access control, and the least-privilege deploy user. Run once per team, before any automated deploy. |
| `deploy/iam/deploy-policy.json` | The least-privilege IAM policy for the deploy user: `s3 sync` on one bucket, `cloudfront:CreateInvalidation` and `cloudfront:GetInvalidation` on one distribution. Referenced from `setup-aws.md`, step 6. |
| `deploy/deploy-ui.sh` | The build-sync-invalidate script: `npm ci`, `ng build`, `aws s3 sync` with the correct cache headers, `aws cloudfront create-invalidation`, then wait for it to finish. |

## How the pieces fit

```
setup-aws.md  ──creates──▶  S3 bucket, CloudFront distribution, deploy user
      │                              │
      └─deploy-policy.json──────────▶│ (the policy attached to that user)
                                      │
deploy-ui.sh  ──build, sync, invalidate──▶  the bucket and distribution above
```

`setup-aws.md` runs once and creates infrastructure. `deploy-ui.sh` runs every time the UI changes and pushes a new build into that infrastructure, run by hand from a terminal against a local AWS CLI profile.

## What is given, and what Sprint 11 builds

This is a reference implementation: an instructor answer key, not starter material handed to a team on day one of Sprint 11. Two of the three items above are handed out; the third is what the sprint assesses.

**Given to teams:**

- `deploy/setup-aws.md`. Infrastructure setup is not the learning objective of Sprint 11, IAM and S3 and CloudFront concepts are, and getting the bucket, the OAC and the distribution wrong before a team's own script is even written wastes the time the sprint has. The walkthrough is handed out so every team starts from the same working infrastructure.
- `deploy/iam/deploy-policy.json`. The shape of a least-privilege policy is exactly what a team should copy when scoping their own deploy user; it is also the marking reference for the Sprint 11 acceptance criterion "IAM user or role scoped to the bucket and distribution only". Handing out the target answer for this one file is deliberate, in the same way `contracts/database-schema.sql` is deliberately not handed out for Sprint 3: this file is closer to a contract than to a build task.

**Built by the team in Sprint 11, with this repository's copy serving only as the instructor's marking reference:**

- `deploy/deploy-ui.sh`. Writing the build, sync and invalidate sequence, and getting the two cache-control families right, is the scripting exercise the sprint is assessed on. A team that is handed a working script has not demonstrated the acceptance criterion "deployment is a single script covering build, upload and invalidation".

A team converges on something functionally equivalent to the built item above; it does not need to match this reference line for line. What is graded is the acceptance criteria in `docs/CURRICULUM_MAP.md`: the app reachable over HTTPS through CloudFront, direct S3 access denied, origin access control in place rather than a public bucket policy, the deploy automated in one script, and no long-lived AWS key committed to the repository.

## Local use

```bash
deploy/deploy-ui.sh \
  --bucket my-team-bucket \
  --distribution-id E1234567890 \
  --profile et-platform-deploy \
  --region eu-west-2 \
  --dry-run
```

Drop `--dry-run` once the plan looks right. See the comment block at the top of `deploy-ui.sh` for the full flag and environment variable list.
