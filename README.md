# Project 1: GitHub Actions to AWS CI/CD

This project demonstrates a secure, traceable CI/CD connection between GitHub Actions and AWS. A change moves through GitHub branches, is tested and security-scanned, and is then deployed to an Amazon S3 static website using short-lived AWS credentials obtained through GitHub OIDC.

## Executive summary

The lab implements a small Python/Flask application and a static landing page. GitHub Actions performs continuous integration on pull requests and branch pushes. Pushes to `dev` deploy after CI; pushes to `stage` and `main` must pass an additional security gate before deployment. The deployment job assumes an AWS IAM role through OpenID Connect (OIDC), verifies the resulting AWS identity, uploads a deployment proof, and synchronizes the static website to S3.

The main security objective was to connect GitHub to AWS without storing long-lived AWS access keys in GitHub.

## Learning objectives

- Build a working GitHub Actions CI/CD pipeline.
- Authenticate GitHub Actions to AWS with OIDC and short-lived credentials.
- Use IAM trust policies and least-privilege permissions.
- Build and test a Docker image.
- Add source, dependency, secret, and container security checks.
- Deploy a static website to Amazon S3.
- Use protected branches and pull requests as promotion controls.
- Troubleshoot real CI/CD, IAM, Docker, Git, and S3 failures.

## Architecture

```text
Developer
   |
   v
GitHub feature branch -> Pull request -> dev -> stage -> main
                                      |
                                      v
                         GitHub Actions workflow
                         - checkout
                         - Python tests
                         - Docker build
                         - security gates
                                      |
                                      v
                         GitHub OIDC token
                                      |
                                      v
                    AWS STS AssumeRoleWithWebIdentity
                                      |
                                      v
                         IAM deployment role
                                      |
                                      v
                    Amazon S3 static website bucket
```

## AWS resources

| Resource | Value |
|---|---|
| AWS account | `866934333672` |
| AWS Region | `us-east-2` |
| S3 bucket | `cloudbatch818` |
| IAM role | `GitHubActionsCICDRole-cloudbatch818-zein` |
| OIDC provider | `token.actions.githubusercontent.com` |
| GitHub repository | `zeinhaidara/github-to-aws-pipeline` |
| GitHub secret | `AWS_ROLE_ARN` |
| Website prefix | `s3://cloudbatch818/github-to-aws-pipeline/site/` |
| Deployment proof | `s3://cloudbatch818/github-to-aws-pipeline/deployment-proof.txt` |

Important ARNs:

```text
arn:aws:iam::866934333672:role/GitHubActionsCICDRole-cloudbatch818-zein

arn:aws:iam::866934333672:oidc-provider/token.actions.githubusercontent.com
```

Static website endpoint used by the lab:

```text
http://cloudbatch818.s3-website.us-east-2.amazonaws.com
```

## Repository structure

```text
.
├── .github/workflows/ci-cd.yml   # CI, security, and S3 deployment workflow
├── app/app.py                    # Flask application
├── app/templates/index.html      # Flask-rendered application page
├── site/index.html               # Static landing page deployed to S3
├── site/style.css                # Landing page styles
├── site/script.js                # Landing page behavior
├── tests/                        # Python tests
├── Dockerfile                    # Python application image
├── requirements.txt              # Pinned Python dependencies
└── README.md                     # Project documentation
```

## Application and Docker image

The application is a small Flask service listening on port `8080`. The Docker image is based on `python:3.13-slim` and:

1. Installs operating-system updates.
2. Upgrades vulnerable or stale Python packaging components.
3. Installs the pinned application dependencies.
4. Copies the Flask application into `/app`.
5. Exposes port `8080`.
6. Starts the service with `python app/app.py`.

The application uses a configurable host:

```python
app.run(host=os.getenv("APP_HOST", "127.0.0.1"), port=8080)
```

The container sets `APP_HOST=0.0.0.0` so the service is reachable from the container network. Keeping the local default at `127.0.0.1` avoided a false-positive security finding during local execution while still supporting container networking.

## GitHub Actions pipeline

The workflow is defined in `.github/workflows/ci-cd.yml`.

### Triggers

The workflow runs for:

- Pull requests targeting `dev`, `stage`, or `main`.
- Pushes to `dev`, `stage`, or `main`.

### Continuous Integration job

The `ci` job runs on pull requests and pushes. It:

1. Checks out the repository.
2. Installs Python `3.13`.
3. Installs dependencies from `requirements.txt`.
4. Runs `python -m pytest`.
5. Builds a Docker image tagged with the GitHub commit SHA.

Example image tag:

```text
github-to-aws-pipeline:${{ github.sha }}
```

### Security and Quality Gate job

The `stage-security` job runs only on pushes to `stage` and `main`. Pull requests run CI only, which keeps developer feedback fast while protected branches receive the full gate before deployment.

The job runs:

- **Bandit**: checks Python source for insecure coding patterns.
- **pip-audit**: checks Python dependencies for known vulnerabilities.
- **Gitleaks**: scans the repository for exposed credentials and secrets.
- **Trivy**: scans the Docker image for high and critical vulnerabilities.

Trivy is configured with:

```yaml
version: v0.74.0
severity: CRITICAL,HIGH
ignore-unfixed: true
exit-code: '1'
```

The embedded pip SBOM file is excluded from the Trivy scan because it produced stale findings about package metadata that did not represent the installed runtime packages:

```text
**/pip/_vendor/bom.cdx.json
```

### CD deployment job

The `cd` job:

- Runs only for pushes, never for pull requests.
- Deploys from `dev` after CI succeeds.
- Deploys from `stage` or `main` only when the security gate succeeds.
- Checks out the repository before accessing the local `site/` directory.
- Assumes the AWS IAM role through OIDC.
- Verifies the AWS identity with `aws sts get-caller-identity`.
- Creates `deployment-proof.txt` containing the deployed Git SHA.
- Uploads the proof file to S3.
- Synchronizes `site/` to the S3 website prefix.

The workflow uses:

```yaml
permissions:
  contents: read
  id-token: write
```

`id-token: write` is required for GitHub Actions to request an OIDC token. It does not grant AWS access by itself; AWS grants access only after the IAM trust policy accepts the token and STS issues temporary credentials.

## GitHub OIDC and IAM connection

### Why OIDC was used

The pipeline does not store an AWS access key and secret key. Instead:

1. GitHub Actions requests an OIDC identity token.
2. The token identifies the repository and workflow context.
3. AWS STS validates the token against the configured GitHub OIDC provider.
4. STS issues short-lived credentials for the IAM role.
5. The workflow uses those temporary credentials to access S3.

This reduces the risk of leaked long-lived cloud credentials and provides a clear audit trail through the assumed-role session.

### IAM trust policy responsibilities

The role trust relationship allows only:

- The GitHub OIDC provider for `token.actions.githubusercontent.com`.
- The action `sts:AssumeRoleWithWebIdentity`.
- The audience `sts.amazonaws.com`.
- The intended GitHub repository and approved subject pattern.

The trust policy is an authentication control. It answers: “Which external identity may assume this role?” It does not define what the role can do after assumption.

### IAM permission policy responsibilities

The role permission policies define what the authenticated workflow may do. For this lab, the deployment permission was limited to S3 operations required to upload the deployment proof and website files.

The role and policy names used during the lab included:

- `GitHubActionsCICDRole-cloudbatch818-zein`
- `GitHubActionsS3Upload-cloudbatch818`
- `Manage-GitHubActionsCICDRole-cloudbatch818`
- `Protect-GitHubActionsCICDRole-cloudbatch818`

The management and protection policies were handled separately from the deployment permission policy. In a production design, the GitHub deployment role should not be given broad IAM administration permissions.

### GitHub secret

The role ARN was stored in the repository secret:

```text
AWS_ROLE_ARN
```

The workflow passes it to `aws-actions/configure-aws-credentials@v4`:

```yaml
role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
aws-region: us-east-2
```

There is no separate GitHub OIDC field where the role ARN is pasted. GitHub issues the token automatically; the repository workflow requests it, and AWS evaluates the trust policy.

## S3 website configuration

The S3 bucket was configured for static website hosting with:

- Index document: `index.html`
- Error document: `error.html`
- Website hosting enabled.
- Website endpoint in `us-east-2`.

For the public static website endpoint to work, Block Public Access had to be disabled for this bucket and a bucket policy had to allow public `s3:GetObject` access to the website objects.

The policy used during the lab was scoped to the project prefix rather than the entire bucket. Because the deployment proof is stored in the same prefix, it is also publicly readable in this lab configuration:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadLandingPageOnly",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::cloudbatch818/github-to-aws-pipeline/*"
    }
  ]
}
```

This lab bucket contains public demonstration content only. Do not place credentials, private files, Terraform state, deployment secrets, or customer data in the public prefix. A tighter variant would expose only `github-to-aws-pipeline/site/*` and store deployment proofs elsewhere. For a production website, CloudFront with HTTPS, Origin Access Control, and S3 Block Public Access would be preferred.

## Branch and promotion behavior

```text
Pull request -> CI only

Push to dev   -> CI -> S3 deployment

Push to stage -> CI -> security gate -> S3 deployment

Push to main  -> CI -> security gate -> S3 deployment
```

Protected branches require changes through pull requests. This created additional merge work but ensures that changes to `stage` and `main` are reviewed and validated before promotion.

## Findings and difficulties

### OIDC role assumption failed

**Symptom:**

```text
Could not assume role with OIDC:
Not authorized to perform sts:AssumeRoleWithWebIdentity
```

**Cause:** The IAM trust policy did not match the claims in the GitHub OIDC token. The repository also had GitHub immutable subject claims enabled, so the subject format was not the older ref-based format initially expected.

**Resolution:** The trust relationship was updated to match the actual GitHub subject claim, while retaining the correct audience `sts.amazonaws.com` and repository restriction.

**Verification:** The workflow successfully returned an assumed-role identity similar to:

```text
arn:aws:sts::866934333672:assumed-role/GitHubActionsCICDRole-cloudbatch818-zein/GitHubActions
```

### The CD runner could not find `site/`

**Symptom:**

```text
aws: [ERROR]: The user-provided path site/ does not exist.
```

**Cause:** The deployment job had not checked out the repository. The AWS credential action does not download repository files.

**Resolution:** Added `actions/checkout@v6` to the CD job before running `aws s3 sync site/`.

### Bandit reported B104

**Symptom:** Bandit flagged:

```text
B104: hardcoded_bind_all_interfaces
```

**Cause:** Flask was configured directly with `host="0.0.0.0"`.

**Resolution:** The application now reads `APP_HOST` from the environment and defaults locally to `127.0.0.1`. The Dockerfile sets `APP_HOST=0.0.0.0` because containerized services need to listen on the container network.

### pip-audit found vulnerable dependencies

**Symptom:** The audit identified findings in Flask `3.1.0` and pytest `8.3.5`.

**Resolution:** Dependencies were upgraded and pinned to:

```text
Flask==3.1.3
pytest==9.0.3
```

### Trivy action version was invalid

**Symptom:** GitHub could not resolve `aquasecurity/trivy-action@0.28.0`.

**Resolution:** The workflow was updated to a valid action version:

```yaml
uses: aquasecurity/trivy-action@v0.36.0
```

Trivy itself was explicitly set to `v0.74.0`.

### Trivy reported stale Python package findings

**Cause:** Trivy scanned pip's embedded vendor SBOM file and reported package metadata that did not match the final installed package versions.

**Resolution:** The Dockerfile explicitly upgraded the relevant packaging components, removed stale metadata, and Trivy was configured to skip only the embedded pip SBOM file. The scan continued to inspect the actual application image.

### Protected branch conflicts

**Symptom:** Pull requests from `stage` to `main` repeatedly reported conflicts in:

```text
.github/workflows/ci-cd.yml
Dockerfile
app/app.py
site/index.html
site/style.css
```

**Cause:** Multiple feature and conflict-resolution branches had diverged, and some files contained nested merge markers after previous conflict attempts.

**Resolution:** The branches were synchronized locally, conflicts were resolved, nested markers were removed, the result was committed to the source branch, and the pull request checks were rerun.

### No ECR access was available

The lab built and scanned the Docker image locally in GitHub Actions but did not push it to ECR because the account access available for the exercise did not include ECR permissions. The static website deployment therefore used S3 directly.

This is intentional scope for Project 1. Project 2 will use ECR for application images and ECS for runtime deployment.

## Verification checklist

Successful completion means:

- Pull request CI completes successfully.
- Python tests pass.
- Docker image builds successfully.
- Bandit, pip-audit, Gitleaks, and Trivy pass on the protected-branch path.
- GitHub Actions assumes the AWS role through OIDC.
- `aws sts get-caller-identity` returns the expected assumed role.
- `deployment-proof.txt` appears in the S3 prefix.
- `site/index.html` and its assets appear under the S3 `site/` prefix.
- The S3 website endpoint renders the landing page.
- Changes to protected branches are made through pull requests.

## Key lessons

1. OIDC authentication has two separate layers: the IAM trust policy and the role permission policy.
2. GitHub workflow permissions must explicitly include `id-token: write` for OIDC.
3. Every job that needs repository files must run a checkout step.
4. Security gates should run before deployment on protected branches.
5. A deployment proof connects an AWS artifact to an exact Git commit.
6. A static S3 website is useful for a first deployment, but public S3 hosting is not the preferred production architecture.
7. Least-privilege policies should be separated by purpose instead of growing one broad policy indefinitely.
8. Branch protection, merge discipline, and conflict resolution are part of delivery engineering—not separate from it.

## Project 2 handoff

Project 2 will extend this foundation into a three-tier application:

```text
GitHub Actions
    -> OIDC
    -> Terraform
    -> VPC / ALB / ECS / ECR / RDS MySQL / Secrets Manager / CloudWatch
```

The recommended runtime is ECS Fargate. The frontend and backend will be containerized, while MySQL will run as Amazon RDS rather than as a database container. The application will use public load-balancer subnets, private application subnets, and private database subnets with security-group rules allowing database access only from the backend.
