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

# ----------------------
# Provider
# ----------------------

# Setup provider information
provider "aws" {
  region = "us-east-1"
}

# ----------------------
# Networks
# ----------------------

# Create the VPC to create the instance, with two subnets
module "network" {
  source = "git@github.com:dbgoytia/networks-tf.git"
  vpc_cidr_block     = "10.0.0.0/16"
  public_subnets_cidrs  = ["10.0.101.0/24", "10.0.102.0/24"]
}
 

# ----------------------
# Network Filesystems EFS
# ----------------------

# Mount the EFS volumes in required subnets in VPC
module "efs_mount" {
  source = "git@github.com:dbgoytia/aws-mount-efs-module-tf.git"
  name    = "my-efs-mount"
  subnets = module.network.public_subnets_ids
  vpc_id  = module.network.vpc_id
  depends_on = [module.network]
}

# ----------------------
# Security groups
# ----------------------

# Create a security group for allowing ssh traffic
resource "aws_security_group" "ec2" {
  name        = "ssh-access-to-test"
  description = "Allow ssh inbound traffic"
  vpc_id      = module.network.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  depends_on = [module.network]

}

# ----------------------
# EC2
# ----------------------

# Retrieve Amazon Linux 2 AMI
data "aws_ssm_parameter" "linuxAmi" {
  name     = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

# Create two EC2 instances
resource "tls_private_key" "tmp" {
  algorithm   = "RSA"
}

resource "aws_key_pair" "user-ssh-key" {
  key_name   = "my-efs-mount-key"
  public_key = tls_private_key.tmp.public_key_openssh
}

resource "aws_instance" "instances-with-efs" {

  count = 2
  ami                    = data.aws_ssm_parameter.linuxAmi.value
  subnet_id              = module.network.public_subnets_ids[count.index]
  vpc_security_group_ids = [
    aws_security_group.ec2.id,
    module.efs_mount.ec2_security_group_id, # EFS access
  ]
  instance_type          = "t2.micro"

  key_name = aws_key_pair.user-ssh-key.key_name


  provisioner "remote-exec" {
    inline = [
      # mount EFS volume
      # https://docs.aws.amazon.com/efs/latest/ug/gs-step-three-connect-to-ec2-instance.html
      # create a directory to mount our efs volume to
      "sudo mkdir -p /mnt/efs",
      # mount the efs volume
      "sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${module.efs_mount.file_system_dns_name}:/ /mnt/efs",
      # create fstab entry to ensure automount on reboots
      # https://docs.aws.amazon.com/efs/latest/ug/mount-fs-auto-mount-onreboot.html#mount-fs-auto-mount-on-creation
      "sudo su -c \"echo '${module.efs_mount.file_system_dns_name}:/ /mnt/efs nfs4 defaults,vers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport 0 0' >> /etc/fstab\"" #create fstab entry to ensure automount on reboots
    ]
  }

  connection {
    host        = self.public_ip
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.tmp.private_key_pem
  }

  depends_on = [module.network]


}



