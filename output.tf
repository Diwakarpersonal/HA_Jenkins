output "Public_instance_ip" {
  value = module.Assignment.instance_public_ip
}

output "elb_dns_name" {
  value = module.Assignment.elb_dns_name
}
