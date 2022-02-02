#----------------------------------------------------------
# Provision Highly Available Web in any Region Default VPC
# Create:
#    - Security Group for Web Server
#    - Launch Configuration with Auto AMI Lookup
#    - Auto Scaling Group using 2 Availability Zones
#    - Classic Load Balancer in 2 Availability Zones
#     terraform version used wget https://releases.hashicorp.com/terraform/0.12.1/terraform_0.12.1_linux_amd64.zip
#
# Made by Sahib Gasimov 01-August-2021
#-----------------------------------------------------------

provider "aws" {
  region = "us-east-1"
}
# ec2 instance-ami for web server
data "aws_availability_zones" "available" {}
output "AZ" {
  value = data.aws_availability_zones.available.names
}
data "aws_ami" "latest_amazon_linux" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
#------------------------------------------------
#sec group 
resource "aws_security_group" "web" {
  name = "Dynamic Security Group"
  dynamic "ingress" {
    for_each = ["80", "443"]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name  = "Dynamic SecurityGroup"
    Owner = "Sahib Gasimov"
  }
}

#launch configuration
resource "aws_launch_configuration" "web" {
  name_prefix = "WebServer1-Highly-Available-LC-"
  image_id        = data.aws_ami.latest_amazon_linux.id
  instance_type   = "t3.micro"
  security_groups = [aws_security_group.web.id]
  user_data       = file("user_data.sh")
  lifecycle {
    create_before_destroy = true #made for hig availability
  }
}
#---------------------------------------------------
# auto-scaling group
resource "aws_autoscaling_group" "web" {
  name              = "ASG-${aws_launch_configuration.web.name}" #name depends on launch conf name so it will be ASG- and any new name from launch config
  launch_configuration = aws_launch_configuration.web.name
  min_size             = 2                                                                      # minimum of desired web servers, so we'll always have at least 2 servers
  max_size             = 2                                                                      # maximum of desired web servers
  min_elb_capacity     = 2                                                                      #when asg knows 2 good servers are good , after LB health check in confirm
  health_check_type    = "ELB"                                                                  # it will ping our page if not respond then it will kill instances
  vpc_zone_identifier  = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id] #which subnets allowed to launch servers
  load_balancers       = [aws_elb.web.name]
  dynamic "tag" {
    for_each = {
      Name   = "WebServer in ASG"
      Owner  = "Sahib Gasimov"
      TAGKEY = "TAGVALUE"
    }
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true # this will make sure attaching to every new created ec2

    }
  }
  lifecycle {
    create_before_destroy = true
  }
}
# load balancer 

resource "aws_elb" "web" {
  name               = "WebServer-HA-ELB"
  availability_zones = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1]]
  security_groups    = [aws_security_group.web.id]
  listener {
    lb_port           = 80 #traffic coming to 80 protocol 
    lb_protocol       = "http"
    instance_port     = 80 # na kakoi port na instance otsilat traffic kotoriy priwel na port 80
    instance_protocol = "http"
  }
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 10
  }
}


resource "aws_default_subnet" "default_az1" {
  availability_zone = data.aws_availability_zones.available.names[0]
}
resource "aws_default_subnet" "default_az2" {
  availability_zone = data.aws_availability_zones.available.names[1]
}
output "elb" {
  value = aws_elb.web.dns_name
}

#-----------------------------------------------------

resource "aws_route53_record" "blog" {
zone_id = "Z0909795NKPTIPFAGOKO"
  name    = "blog.sahibgasimov.net"
  type    = "A"
 

  alias {
    name                   = aws_elb.web.dns_name
    zone_id                = aws_elb.web.zone_id
    evaluate_target_health = true
  }
}
