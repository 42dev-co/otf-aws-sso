terraform {
  backend "s3" {
    bucket = "iac.42dev.co"
    key    = "management/otf-iac-aws-sso/ap-southeast-1/state.tfstate"
    region = "ap-southeast-1"
    profile = "devops"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "ap-southeast-1"
}