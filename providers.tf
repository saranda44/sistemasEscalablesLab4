provider "aws" {
  region  = var.aws_region
  profile = "academy"

  default_tags {
    tags = {
      Project = var.project_name
    }
  }
}
