# GitHub to AWS CI/CD Pipeline

## Objective

Demonstrate a functional CI/CD connection between GitHub Actions and AWS.

## Pipeline

```text
GitHub
  ↓
Checkout
  ↓
Build Docker Image
  ↓
Test
  ↓
Authenticate to AWS
  ↓
Publish deployment proof to Amazon S3

The workflow uses GitHub OIDC to assume the configured AWS role and uploads a deployment proof to the `cloudbatch818` S3 bucket in `us-east-2`. ECR is out of scope for this lab.
