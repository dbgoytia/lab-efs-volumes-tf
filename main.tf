terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      region = "us-east-1"
    }
  }
  backend "s3" {
    bucket = "691e4876-f921-0542-c9c7-0989c184fe8c-backend"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}

# Setup provider information
provider "aws" {
  region = "us-east-1"
}

# Create the VPC to create the instance, with two subnets
module "network" {
  source = "git@github.com:dbgoytia/networks-tf.git"
  vpc_cidr_block     = "10.0.0.0/16"
  public_subnets_cidrs  = ["10.0.101.0/24", "10.0.102.0/24"]
}

data "aws_subnet_ids" "subnet" {
  vpc_id = module.network.vpc_id
}

locals {                                                            
  subnet_ids_string = join(",", data.aws_subnet_ids.subnet.ids)
  subnet_ids_list = split(",", local.subnet_ids_string)             
} 

# Mount the EFS  volumes in the public cidrs from the networking module 
module "efs_mount" {
  source = "git@github.com:dbgoytia/aws-mount-efs-module-tf.git"
  name    = "my-efs-mount"
  subnets = module.network.public_subnets_ids
  vpc_id  = module.network.vpc_id
  depends_on = [module.network]
}


