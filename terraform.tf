# providers
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.0.0"
    }
  }
}

# init provider
provider "google" {
  credentials = file("gcp-cred.json")
  project     = "direct-branch-331219"
  region      = "us-west1"
  zone        = "us-west1-a"
}

data "google_client_config" "current" {
  provider = google
}

# declare some variables
variable "gce_ssh_user" {
  type        = string
  default     = "she110ck"
  description = "gce ssh user"
}

variable "gce_ssh_pub_key_file" {
  type        = string
  default     = "/home/she110ck/.ssh/google_compute_engine.pub"
  description = "gce ssh public key file"
}

### 

# network things
resource "google_compute_network" "cstack_network" {
  auto_create_subnetworks = false
  name                    = "cstack-network"
}

resource "google_compute_subnetwork" "cstack_subnet" {
  name          = "cstack-subnet"
  ip_cidr_range = "10.240.0.0/24"
  network       = google_compute_network.cstack_network.self_link
}

# firewalls
resource "google_compute_firewall" "cstack_internal_firewall" {
  name    = "cstack-internal-firewall"
  network = google_compute_network.cstack_network.name

  allow {
    protocol = "tcp"
    ports = ["8080","8250","8443","9090"]
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }
  source_ranges = ["10.240.0.0/24"]
}
# management ports
# 8080 8250 8443 9090

resource "google_compute_firewall" "cstack_external_firewall" {
  name    = "cstack-external-firewall"
  network = google_compute_network.cstack_network.name

  allow {
    protocol = "tcp"
    ports    = ["22", "8080", "80", "443"]
  }

  allow {
    protocol = "icmp"
  }
  source_ranges = ["0.0.0.0/0"]
}


# external ip (not attached yet)
#resource "google_compute_address" "cstack_address" {
#  name = "cstack-address"
# subnetwork = google_compute_subnetwork.cstack_subnet.id
#  region = data.google_client_config.current.region
#}

# VM
resource "google_compute_instance" "cstack_single" {
  name                      = "cstack-single"
  machine_type              = "n1-standard-4"
  allow_stopping_for_update = true
  tags                      = ["cloudstack", "allin1"]
  boot_disk {
    initialize_params {
      image = "centos-cloud/centos-7"
      # image = "centos-7-v20211105"
      size = "200"

    }
  }
  service_account {
    scopes = ["compute-rw", "storage-ro", "service-management", "service-control", "logging-write", "monitoring"]
  }

  advanced_machine_features {
    enable_nested_virtualization = true
  }

  can_ip_forward = true

  network_interface {
    access_config {}
    subnetwork = google_compute_subnetwork.cstack_subnet.name
    network_ip = "10.240.0.2"
    nic_type   = "VIRTIO_NET"
  }
  metadata = {
    pod-cidr = "10.200.0.0/24"
    ssh-keys = "${var.gce_ssh_user}:${file(var.gce_ssh_pub_key_file)}"
  }

  #  connection {
  #    host        = self.network_interface.0.access_config.0.nat_ip
  #  user        = var.gce_ssh_user
  #  type        = "ssh"
  #  private_key = file(replace(var.gce_ssh_pub_key_file, ".pub", ""))
  #  timeout     = "2m"
  #}

  provisioner "remote-exec" {
    connection {
      host        = self.network_interface.0.access_config.0.nat_ip
      user        = var.gce_ssh_user
      agent       = false
      type        = "ssh"
      private_key = file(replace(var.gce_ssh_pub_key_file, ".pub", ""))
      timeout     = "2m"
    }
    inline = [
    "sudo yum install python3 -y",
    ]
  }

  provisioner "local-exec" {
    command = "ansible-playbook -i '${google_compute_instance.cstack_single.network_interface.0.access_config.0.nat_ip},' --private-key ${replace(var.gce_ssh_pub_key_file, ".pub", "")} singlenode.yaml"
  }

}

