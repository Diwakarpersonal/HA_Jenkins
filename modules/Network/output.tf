output "vpc_id" {
  value = aws_vpc.ninja_vpc.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "instance_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "elb_dns_name" {
  value = aws_lb.my_lb02.dns_name
}
