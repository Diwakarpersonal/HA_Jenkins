
resource "aws_vpc" "ninja_vpc" {
  cidr_block = "10.0.0.0/22"
  tags = {
    Name = var.vpc_name
  }
}

resource "tls_private_key" "example_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "example_keypair" {
  key_name   = "example-keypair"
  public_key = tls_private_key.example_key.public_key_openssh
}

resource "local_file" "private_key" {
  filename = "private_key.pem"
  content  = tls_private_key.example_key.private_key_pem
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

resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
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

resource "aws_security_group" "private_instance_sg" {
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
  key_name      = aws_key_pair.example_keypair.key_name
  security_groups = [aws_security_group.bastion_sg.id]

  tags = {
    Name = "bastion"
  }
}

resource "aws_instance" "private_instance" {
  ami           = var.instance_ami
  instance_type = var.instance
  subnet_id     = aws_subnet.private[0].id
  key_name      = aws_key_pair.example_keypair.key_name
  security_groups = [aws_security_group.private_instance_sg.id]

  tags = {
    Name = "private_instance"
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
resource "aws_lb" "my_lb" {
  name               = "my-load-balancer"
  internal           = false  
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  enable_deletion_protection = false
  security_groups = [aws_security_group.load_balancer_sg.id]
}

resource "aws_lb_target_group" "my_target_group" {
  name        = "my-target-group"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ninja_vpc.id
}

resource "aws_lb_listener" "my_listener" {
  load_balancer_arn = aws_lb.my_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
}

resource "aws_lb_listener_rule" "my_rule" {
  listener_arn = aws_lb_listener.my_listener.arn

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
resource "aws_lb_target_group_attachment" "private_instance_attachments" {
  count         = length(aws_instance.private_instance)
  target_group_arn = aws_lb_target_group.my_target_group.arn
  target_id     = aws_instance.private_instance.id
}
