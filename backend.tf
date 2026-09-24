# Remote state in the pre-existing S3 bucket "sara.aranda", using the
# "academy" AWS profile. Uses Terraform's native S3 state locking
# (use_lockfile, TF >= 1.10) so no DynamoDB lock table is needed.
terraform {
  backend "s3" {
    bucket       = "sara.aranda"
    key          = "lab4/terraform.tfstate"
    region       = "us-east-1"
    profile      = "academy"
    encrypt      = true
    use_lockfile = true
  }
}
