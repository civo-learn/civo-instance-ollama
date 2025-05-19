# Create a new instance
resource "civo_instance" "workspace-instance" {
    hostname = "${var.name_prefix}-instance"
    notes = "An Example Machine Learning Development Environment"
    size = var.node_size
    disk_image = "ubuntu-cuda12-6" # or ubuntu-cuda11-8
    script = file("script.sh")
}