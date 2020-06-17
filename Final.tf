provider "aws" {
	region  = "ap-south-1"
	profile = "Ayush"
}

data "aws_vpc" "selected"{
	default = true
}

locals{
	vpc_id = data.aws_vpc.selected.id 
}

resource "tls_private_key" "oskey" {
	algorithm   = "RSA"
}

resource "local_file" "myterrakey" {
    content     = tls_private_key.oskey.private_key_pem
    filename = "myterrakey.pem"
}

resource "aws_key_pair" "key121" {
	key_name   = "myterrakey"
	public_key = tls_private_key.oskey.public_key_openssh
}

resource "aws_security_group" "SGforterra" {
	name        = "SGforterra"
	description = "Security group for ec2 instance with https, http, ssh"
	vpc_id      = local.vpc_id

	ingress {
		description = "HTTPS"
		from_port   = 443
		to_port     = 443
		protocol    = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}

	ingress {
		description = "HTTP"
		from_port   = 80
		to_port     = 80
		protocol    = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
    }

	ingress {
		description = "SSH"
		from_port   = 22
		to_port     = 22
		protocol    = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
    }

	egress {
		description = "HTTPS"
		from_port   = 443
		to_port     = 443
		protocol    = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
    }

	egress {
		description = "HTTP"
		from_port   = 80
		to_port     = 80
		protocol    = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}

	egress {
		description = "SSH"
		from_port   = 22
		to_port     = 22
		protocol    = "tcp"
		cidr_blocks = ["0.0.0.0/0"] 
    }

    tags = {
        Name = "SGforterra"
    }
}

/*
variable "enter_your_keyname"{
    type = string
    default = "key121"
}
*/


resource "aws_instance" "testinst1" {
	ami             = "ami-0447a12f28fddb066"
    instance_type   = "t2.micro"
    key_name        = aws_key_pair.key121.key_name
    security_groups = ["${aws_security_group.SGforterra.name}"]

    tags = {
        Name = "Terratest1"
    }
  
    connection {
        type     = "ssh"
        user     = "ec2-user"
        private_key = tls_private_key.oskey.private_key_pem
        host     = aws_instance.testinst1.public_ip
    }
  
    provisioner "remote-exec" {
        inline = [
            "sudo yum install httpd  php git -y",
            "sudo systemctl restart httpd",
			"sudo systemctl enable httpd",
        ]
    }
}

resource "aws_ebs_volume" "test_terra_ebs1" {
    availability_zone = aws_instance.testinst1.availability_zone
    size              = 1
	type = "gp2"
    tags = {
        Name = "test_terra_ebs1"
    }
}

resource "aws_volume_attachment" "test_terra_ebs1_att" {
    device_name = "/dev/sdz"
    volume_id   = aws_ebs_volume.test_terra_ebs1.id
    instance_id = aws_instance.testinst1.id
	force_detach = true
}

output "myos_ip" {
    value = aws_instance.testinst1.public_ip
}

resource "null_resource" "remote_resource" {

    depends_on = [
        aws_volume_attachment.test_terra_ebs1_att,
    ]
  
    connection {
        type     = "ssh"
        user     = "ec2-user"
        private_key = tls_private_key.oskey.private_key_pem
        host     = aws_instance.testinst1.public_ip
    }
  
    provisioner "remote-exec"  {
        inline = [
          "sudo mkfs.ext4  /dev/xvdz",
          "sudo mount  /dev/xvdz  /var/www/html",
          "sudo rm -rf /var/www/html/*",
          "sudo git clone https://github.com/Ayush-Gith/Terraform_trail.git /var/www/html/"
        ]
    }
	
	provisioner "remote-exec"  {
        when = destroy
	    inline = [
          "sudo umount /var/www/html/"
        ]
    }
}

resource "aws_s3_bucket" "task1_bucket" {

	depends_on = [
        null_resource.remote_resource,
    ] 
	
    bucket = "buket-for-terra-images"
    acl    = "public-read"
	 
	tags = {
    Name        = "buket-for-terra-images"
    Environment = "Dev"
    }

	provisioner "local-exec"  {	
		command = "git clone https://github.com/Ayush-Gith/Terraform_trail.git server "
	}
	
	provisioner "local-exec"  {
        when = destroy
		command = "echo Y | rmdir /s server "
    }
}

resource "aws_s3_bucket_object" "task1_bucket-obj" {
     
	depends_on = [
    aws_s3_bucket.task1_bucket,
    ]
	 
	 bucket = aws_s3_bucket.task1_bucket.bucket
     key    = "Eagle.jpg"
	 source = "C:/Users/AyushC~1/Desktop/Terraform/task1/images/Demo/Eagle.jpg"
	 acl  =  "public-read-write"
     content_type = "image/jpg"
}

variable "var1"{
	default=" S3-"
}


locals {
  s3_origin_id = "${var.var1}${aws_s3_bucket.task1_bucket.bucket}"
}


resource "aws_cloudfront_distribution" "s3_config" {

	depends_on = [
    aws_s3_bucket_object.task1_bucket-obj,
    ]
	
	origin{
		domain_name = aws_s3_bucket.task1_bucket.bucket_regional_domain_name
		origin_id   = local.s3_origin_id
	}
	
	enabled             = true
	
	default_cache_behavior {
		allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
		cached_methods   = ["GET", "HEAD"]
		target_origin_id = local.s3_origin_id
		
		forwarded_values {
			query_string = false

			cookies {
				forward = "none"
        }
    }
	
	viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 120
    max_ttl                = 86400
    }
	
	restrictions {
		geo_restriction {
			restriction_type = "none"
        }
    }
	
	viewer_certificate {
		cloudfront_default_certificate = true
    }
	
}


	
resource "null_resource" "deploy" {

    depends_on = [
    null_resource.remote_resource, aws_cloudfront_distribution.s3_config,
    ]

    provisioner "local-exec" {
     command = "start chrome ${aws_instance.testinst1.public_ip} "
    }
}