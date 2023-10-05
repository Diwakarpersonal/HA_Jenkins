
resource "aws_vpc" "ninja_vpc" {
  cidr_block = "10.0.0.0/22"
  enable_dns_hostnames = true
  tags = {
    Name = var.vpc_name
  }
}

resource "tls_private_key" "example_key02" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "example_keypair02" {
  key_name   = "example-keypair02"
  public_key = tls_private_key.example_key02.public_key_openssh
}

resource "local_file" "private_key" {
  filename = "private_key.pem"
  content  = tls_private_key.example_key02.private_key_pem
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_names)
  cidr_block              = "10.0.${count.index}.0/24"
  vpc_id                  = aws_vpc.ninja_vpc.id
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = var.public_subnet_names[count.index]
  }
}

resource "aws_subnet" "private" {
  count                   = length(var.private_subnet_names)
  cidr_block              = "10.0.${count.index + 2}.0/24"
  vpc_id                  = aws_vpc.ninja_vpc.id
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = false
  tags = {
    Name = var.private_subnet_names[count.index]
  }
}

resource "aws_security_group" "bastion_sg02" {
  name        = "bastion-sg02"
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.ninja_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
    egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "private_instance_sg02" {
  name        = "private-instance-sg"
  description = "Security group for private instance"
  vpc_id      = aws_vpc.ninja_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8080
    to_port     = 8090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
    egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "bastion" {
  ami           = var.instance_ami
  instance_type = var.instance
  subnet_id     = aws_subnet.public[0].id
  key_name      = aws_key_pair.example_keypair02.key_name
  security_groups = [aws_security_group.bastion_sg02.id]

  tags = {
    Name = "bastion"
  }
}

resource "aws_internet_gateway" "ninja_igw" {
  vpc_id = aws_vpc.ninja_vpc.id
  tags = {
    Name = var.igw_name
  }
}

resource "aws_eip" "nat" {
  instance = null
}

resource "aws_nat_gateway" "ninja_nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
}

resource "aws_route_table" "public" {
  count  = 1
  vpc_id = aws_vpc.ninja_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ninja_igw.id
  }
  tags = {
    Name = "ninja-route-pub-01/02"
  }
}

resource "aws_route_table" "private" {
  count  = 1
  vpc_id = aws_vpc.ninja_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.ninja_nat.id
  }
  tags = {
    Name = "ninja-route-priv-01/02"
  }
}

resource "aws_route_table_association" "private_subnets" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}

resource "aws_route_table_association" "public_subnets" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_security_group" "load_balancer_sg" {
  name        = "load-balancer-sg"
  description = "Security group for the load balancer"
  vpc_id      = aws_vpc.ninja_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
    egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_efs_file_system" "ninja" {
  creation_token = "jenkins-data"
  encrypted = true 
  tags = {
    Name = "jenkins-data"
  }
}
resource "aws_efs_mount_target" "ninja" {
  count     = 2
  file_system_id  = aws_efs_file_system.ninja.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.private_instance_sg02.id]
}

resource "aws_lb" "my_lb02" {
  name               = "my-load-balancer02"
  internal           = false  
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  enable_deletion_protection = false
  security_groups = [aws_security_group.load_balancer_sg.id]
}

resource "aws_lb_target_group" "my_target_group02" {
  name        = "my-target-group02"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ninja_vpc.id
}

resource "aws_lb_listener" "my_listener02" {
  load_balancer_arn = aws_lb.my_lb02.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group02.arn
  }
}

resource "aws_lb_listener_rule" "my_rule02" {
  listener_arn = aws_lb_listener.my_listener02.arn

  action {
    type             = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      status_code  = "200"
    }
  }
  condition {
    path_pattern {
      values = ["/health"]
    }
  }
}

resource "aws_launch_template" "jenkins_template" {
  depends_on = [aws_efs_mount_target.ninja]
  name_prefix = "Jenkins-"
  image_id = var.jenkins_ami
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.private_instance_sg02.id]
  key_name = aws_key_pair.example_keypair02.key_name
  user_data = base64encode(<<EOF
#!/bin/bash
sudo apt-get update -y
sudo apt-get install nfs-common -y
sudo mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_file_system.ninja.dns_name}:/ /var/lib/jenkins/
config_file="/var/lib/jenkins/config.xml"
if [ ! -e "$config_file" ]; then
  sudo rsync -a /usr/local/jenkins_data/ /var/lib/jenkins/
fi
sudo systemctl restart jenkins.service
EOF
   )
}
resource "aws_autoscaling_group" "asg" {
  depends_on = [ aws_efs_file_system.ninja ]
  name_prefix                 = "Ninja-"
  launch_template {
    id = aws_launch_template.jenkins_template.id
    version = "$Latest"
  }
  min_size                    = 1
  max_size                    = 1
  desired_capacity            = 1
  target_group_arns           = [aws_lb_target_group.my_target_group02.arn]
  vpc_zone_identifier = [aws_subnet.private[0].id, aws_subnet.private[1].id]
}