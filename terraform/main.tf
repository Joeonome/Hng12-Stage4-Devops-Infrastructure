provider "aws" {
  region = "eu-north-1"
}

resource "aws_instance" "todo_server" {
  ami           = "ami-09a9858973b288bdd"  # Replace with the latest Ubuntu AMI
  instance_type = "t3.large"
  key_name      = "microservice"
  vpc_security_group_ids = [aws_security_group.micro_service.id]

  user_data = <<-EOF
    #!/bin/bash
    sleep 30  # Ensure the instance is fully initialized
    apt update -y
    apt upgrade -y
    apt install -y software-properties-common
    add-apt-repository --yes --update ppa:ansible/ansible
    sudo apt autoremove -y && sudo apt clean
    apt install -y ansible docker.io git
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    docker network create app_network
  EOF

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/Downloads/microservice.pem")
      host        = self.public_ip
    }
    inline = [
      "echo 'Instance is ready for provisioning!'"
    ]
  }

  tags = {
    Name = "micro_service_server"
  }
}

resource "aws_security_group" "micro_service" {
  name        = "micro_service"
  description = "Allow SSH and Web Traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow SSH (change this for security)
  }

  ingress {
    from_port   = 80
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow HTTP/HTTPS traffic
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
  content  = <<-EOT
  [servers]
  todo_server ansible_host=${aws_instance.todo_server.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/Downloads/microservice.pem
  EOT
  depends_on = [aws_instance.todo_server]
}

# Automatically run Ansible after Terraform deployment
resource "null_resource" "ansible_provision" {
  depends_on = [aws_instance.todo_server, local_file.ansible_inventory]
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ./../ansible/inventory.ini ./../ansible/playbook.yml"
  }
}


