# Create a firewall
resource "civo_firewall" "firewall-ingress" {
  # name the firewall resource
  name                 = "${var.name_prefix}-firewall"
  # change this to false to configure your own rules
  create_default_rules = true

  # ingress_rule {
  #   protocol    = "tcp"
  #   port_range   = "22"
  #   cidr        = ["0.0.0.0/0"]
  #   label       = "SSH access port"
  #   action      = "allow"
  # }
}
