# Setting up AWS for the deployment

Status: instructor-reviewed. Follow this runbook literally. It is the only material for Sprint 11 (`cloud-deploy`), and on the India branch it is the only material for the alumni-supported cloud week, so it has to work without anyone in the room to fill a gap.

## Why the platform needs any of this

Everything built before Sprint 11 runs on your machine, under Docker Compose. That proves the platform works, but nobody outside your laptop can reach it. `deploy-ui.sh` and this walkthrough put the one component with no server-side state, the Angular build, somewhere a browser anywhere can load it over HTTPS. The rest of the platform, Postgres, Kafka, the Trade REST API, the auth service, the executor, stays on Docker Compose. Do not attempt to deploy them to AWS: it is out of scope, and the acceptance criteria in `CURRICULUM_MAP.md` do not ask for it.

The shape is fixed by one rule: the bucket holding the build is never reachable directly. Every request goes through CloudFront, which is the only thing the bucket trusts. That is what an origin access control (OAC) does, and it is why the steps below create the OAC before they touch the bucket policy.

## Scope

In scope: IAM, the AWS CLI, S3, CloudFront. Nothing else. If a step below appears to need Route 53, Certificate Manager, or a custom domain, it does not: those are concept-level topics for this programme, covered in the SME briefing, not built by hand. See `docs/DECISIONS.md`, decision 4.

## Before you start

You need:

- An AWS account with console and CLI access. On the `india` cloud week this is provisioned by Fidelity; on `us-ireland` it is the account set up in the Sprint 11 material.
- The AWS CLI installed and configured (`aws configure`) with credentials that can create S3 buckets, CloudFront distributions and IAM policies. This is a broader permission set than the one you hand to the deploy automation. Use it only for the one-off setup below, then switch to the narrow deploy user for every deploy from that point on.
- Your Angular build passing locally (`npm ci && npm run build` inside `ui/`) before you spend any time on AWS.

Set these once, in the shell you run the commands from:

```bash
export BUCKET_NAME=et-platform-ui-yourname     # must be globally unique across all of S3
export AWS_REGION=eu-west-2                    # see "choosing a region" below
```

### Choosing a region

CloudFront is a global edge network regardless of which region you pick, so the region choice only fixes where the S3 bucket itself lives. Pick one and stay consistent for the rest of the walkthrough:

| Cohort | Suggested region |
|---|---|
| Ireland or UK | `eu-west-2` (London) |
| US | `us-east-1` (N. Virginia) |
| India | `ap-south-1` (Mumbai) |

`us-east-1` is a special case for the `create-bucket` call: it does not accept a `LocationConstraint`. The command below has a note where this matters.

## Step 1: create the S3 bucket

```bash
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"
```

Drop `--create-bucket-configuration` entirely if `AWS_REGION` is `us-east-1`.

## Step 2: block all public access

The bucket is never addressed directly, so nothing in it should ever be public.

```bash
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

Confirm it later with:

```bash
curl -I "https://$BUCKET_NAME.s3.$AWS_REGION.amazonaws.com/index.html"
```

This must return `403 Forbidden`, both now and after the site is live. If it ever returns `200`, the bucket policy has gone wrong: stop and fix it before deploying anything else.

## Step 3: create the origin access control

The OAC is the credential CloudFront presents to S3. Create it before the distribution, because the distribution needs its ID.

```bash
aws cloudfront create-origin-access-control \
  --origin-access-control-config \
  Name="$BUCKET_NAME-oac",SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3
```

Note the `Id` in the response. You need it in the next step.

## Step 4: create the CloudFront distribution

Use the console for this step: the distribution configuration has more fields than are worth typing by hand, and the console fills in sensible defaults for the ones that do not matter here. Set:

| Field | Value |
|---|---|
| Origin domain | the bucket's REST endpoint, `$BUCKET_NAME.s3.$AWS_REGION.amazonaws.com`, not the static-website-hosting endpoint. OAC only works against the REST endpoint. |
| Origin access | Origin access control settings, select the OAC created in step 3 |
| Viewer protocol policy | Redirect HTTP to HTTPS |
| Cache policy | CachingOptimized (AWS managed) |
| Default root object | `index.html` |
| Price class | Use only North America and Europe (or the class covering your cohort's region), to keep the distribution on the cheapest edge tier |

Add two custom error responses. The Angular router handles paths like `/dashboard` or `/orders/42` client-side; the bucket has no object at that key, and a private bucket returns `403`, not `404`, for a missing key behind OAC. Without this, a deep link or a page refresh on any route but `/` breaks.

| HTTP error code | Response page path | Response code | TTL |
|---|---|---|---|
| 403 | `/index.html` | 200 | 10 |
| 404 | `/index.html` | 200 | 10 |

If you prefer the CLI, the equivalent is `aws cloudfront create-distribution --distribution-config file://distribution-config.json` with a config file shaped like this (replace the three placeholders):

```json
{
  "CallerReference": "et-platform-ui-2026-01",
  "Comment": "Enterprise Trading Platform UI",
  "Enabled": true,
  "DefaultRootObject": "index.html",
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "s3-origin",
        "DomainName": "REPLACE_BUCKET_NAME.s3.REPLACE_REGION.amazonaws.com",
        "OriginAccessControlId": "REPLACE_OAC_ID",
        "S3OriginConfig": { "OriginAccessIdentity": "" }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "Compress": true
  },
  "CustomErrorResponses": {
    "Quantity": 2,
    "Items": [
      { "ErrorCode": 403, "ResponseCode": "200", "ResponsePagePath": "/index.html", "ErrorCachingMinTTL": 10 },
      { "ErrorCode": 404, "ResponseCode": "200", "ResponsePagePath": "/index.html", "ErrorCachingMinTTL": 10 }
    ]
  },
  "PriceClass": "PriceClass_100"
}
```

`658327ea-f89d-4fab-a63d-7e88639e58f6` is the fixed id of the AWS managed `CachingOptimized` policy. It is the same value in every account and every region.

Note the distribution's `Id`, `ARN` and `DomainName` (the `*.cloudfront.net` hostname) once it is created. The distribution takes several minutes to deploy; do not move on until its status is `Deployed`.

## Step 5: attach the bucket policy

Now that the distribution exists, grant it, and only it, read access to the bucket.

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export DISTRIBUTION_ID=REPLACE_WITH_YOUR_DISTRIBUTION_ID
```

Bucket policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipalReadOnly",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::REPLACE_BUCKET_NAME/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::REPLACE_ACCOUNT_ID:distribution/REPLACE_DISTRIBUTION_ID"
        }
      }
    }
  ]
}
```

Save it as `bucket-policy.json` with the three placeholders replaced, then apply it:

```bash
aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy file://bucket-policy.json
```

The `Condition` block is what makes this least privilege at the resource level: it scopes read access to requests coming from this one distribution, not to CloudFront in general. Skipping it would let any CloudFront distribution in any AWS account read the bucket.

## Step 6: create the least-privilege deploy user

The deploy automation, `deploy/deploy-ui.sh` and the `deploy-ui.yml` workflow, never uses the broad credentials from the setup above. It uses a separate IAM user scoped to exactly two things: syncing this bucket, and invalidating this distribution.

The policy document is `deploy/iam/deploy-policy.json` in this repository:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListTargetBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::REPLACE_BUCKET_NAME"
    },
    {
      "Sid": "SyncObjectsInTargetBucket",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::REPLACE_BUCKET_NAME/*"
    },
    {
      "Sid": "InvalidateTargetDistribution",
      "Effect": "Allow",
      "Action": ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"],
      "Resource": "arn:aws:cloudfront::REPLACE_ACCOUNT_ID:distribution/REPLACE_DISTRIBUTION_ID"
    }
  ]
}
```

`s3:ListBucket` is a bucket-level permission, hence the resource is the bucket ARN with no trailing `/*`. `GetObject`, `PutObject` and `DeleteObject` are object-level, hence they carry `/*`. `s3 sync --delete`, which `deploy-ui.sh` uses, needs all four: it lists the bucket to compute the diff, then gets, puts and deletes individual objects. `cloudfront:GetInvalidation` is required because the deploy script waits for the invalidation to finish, and the wait polls that action.

Copy the file, replace the three placeholders with your real bucket name, account id and distribution id, then create the user and policy:

```bash
cp deploy/iam/deploy-policy.json deploy-policy.filled.json
# edit deploy-policy.filled.json: replace REPLACE_BUCKET_NAME,
# REPLACE_ACCOUNT_ID and REPLACE_DISTRIBUTION_ID

aws iam create-user --user-name et-platform-deploy

aws iam put-user-policy \
  --user-name et-platform-deploy \
  --policy-name et-platform-deploy-policy \
  --policy-document file://deploy-policy.filled.json

aws iam create-access-key --user-name et-platform-deploy
```

`create-access-key` prints an access key id and a secret. This is the only time the secret is shown. Store it immediately in the location from step 7 and do not paste it anywhere else, including chat, a commit, or a screenshot for the showcase.

Do not delete `deploy-policy.filled.json` before checking it is not tracked by git. It contains real account and resource identifiers, not secrets, but it does not belong in the repository either.

## Step 7: store the deploy credentials

Never commit an access key. Store the pair as GitHub Actions secrets on the repository (or on a `production` environment within it, see the comment in `.github/workflows/deploy-ui.yml`):

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | from step 6 |
| `AWS_SECRET_ACCESS_KEY` | from step 6 |

Store the non-secret identifiers as repository or environment variables, since they are not sensitive on their own:

| Variable | Value |
|---|---|
| `AWS_REGION` | the region from the top of this walkthrough |
| `DEPLOY_BUCKET` | `$BUCKET_NAME` |
| `DEPLOY_DISTRIBUTION_ID` | the distribution id from step 4 |

For a local, manual deploy, configure a named CLI profile instead of exporting keys into your shell history:

```bash
aws configure --profile et-platform-deploy
```

## Step 8: deploy

```bash
deploy/deploy-ui.sh \
  --bucket "$BUCKET_NAME" \
  --distribution-id "$DISTRIBUTION_ID" \
  --profile et-platform-deploy \
  --region "$AWS_REGION" \
  --dry-run
```

Check the dry run output, then run the same command without `--dry-run`. Load `https://<distribution-domain>.cloudfront.net` and confirm the app loads. Load `https://<distribution-domain>.cloudfront.net/some/deep/route` directly and confirm it loads too, rather than a CloudFront error page, which is what the custom error responses from step 4 are for.

## Cost notes: staying in the free tier

This deployment is small enough to sit inside AWS's free usage for the length of the programme, provided you follow these guardrails. Confirm the current terms at `aws.amazon.com/free` before relying on any of this, since AWS revises free tier terms from time to time.

- S3 storage for one Angular build is a few megabytes. The free tier's storage and request allowances comfortably cover a cohort deploying repeatedly for a few weeks.
- CloudFront's free tier covers a data transfer and request volume far beyond what a training exercise generates. `PriceClass_100` from step 4 keeps the distribution on the cheapest edge location tier regardless.
- CloudFront invalidations: the first 1,000 paths invalidated per month cost nothing, then a small per-path charge applies. `deploy-ui.sh` invalidates exactly one path, `/index.html`, per deploy, so this is not a practical concern at cohort scale.
- The largest realistic cost risk is forgetting infrastructure exists after the showcase. A distribution and a bucket left running for months, across a whole cohort, adds up even at pennies each. Tear down promptly, per the next section.

## Teardown

Run this once your deployment is no longer needed, normally right after the showcase or the assessed demonstration.

```bash
# Empty and delete the bucket
aws s3 rm "s3://$BUCKET_NAME" --recursive
aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"

# Disable the distribution before it can be deleted
ETAG=$(aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --query ETag --output text)
aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --query DistributionConfig \
  > distribution-config.json
# edit distribution-config.json: set "Enabled": false
aws cloudfront update-distribution --id "$DISTRIBUTION_ID" \
  --distribution-config file://distribution-config.json --if-match "$ETAG"

# Wait until the console or `aws cloudfront get-distribution` shows status
# Deployed with Enabled: false, then delete it
ETAG=$(aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --query ETag --output text)
aws cloudfront delete-distribution --id "$DISTRIBUTION_ID" --if-match "$ETAG"

# Remove the origin access control
aws cloudfront delete-origin-access-control --id REPLACE_WITH_OAC_ID \
  --if-match $(aws cloudfront get-origin-access-control --id REPLACE_WITH_OAC_ID --query ETag --output text)

# Remove the deploy user's credentials
aws iam delete-user-policy --user-name et-platform-deploy --policy-name et-platform-deploy-policy
aws iam list-access-keys --user-name et-platform-deploy --query 'AccessKeyMetadata[].AccessKeyId' --output text
# for each key id returned:
aws iam delete-access-key --user-name et-platform-deploy --access-key-id REPLACE_WITH_KEY_ID
aws iam delete-user --user-name et-platform-deploy
```

Finally, remove the `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` secrets from the GitHub repository settings.

A CloudFront distribution takes several minutes to move to `Disabled` and `Deployed` before it accepts deletion. Do not skip the wait: the delete call fails with a clear error if you try too early.
