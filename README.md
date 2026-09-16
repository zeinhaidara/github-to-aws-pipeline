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
Push Image to Amazon ECR