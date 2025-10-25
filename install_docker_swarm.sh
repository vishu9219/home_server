# For cluster management
sudo ufw allow 2377/tcp
sudo ufw allow 7946/tcp
sudo ufw allow 7946/udp
sudo ufw allow 4789/tcp
sudo ufw allow 4789/udp
sudo ufw reload

# Package installation
sudo apt update
sudo apt upgrade -y
sudo apt install ca-certificates curl gnupg

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the Docker repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine and components
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# Verify Docker is running
sudo systemctl status docker

# Add vishal to docker group
sudo usermod -aG docker vishal

# Init docker swarn
docker swarm init --advertise-addr <MANAGER_IP>

# Stop the Docker service
systemctl stop docker

# Edit or create the daemon.json file
cat <<EOF > /etc/docker/daemon.json
{
  "data-root": "/mnt/external/docker"
}
EOF

# Copy existing Docker data
rsync -aP /var/lib/docker/ /mnt/external/docker

# Restart Docker
sudo systemctl daemon-reload
sudo systemctl start docker

# Cleanup
rm -rf /var/lib/docker

# Command to run at child cluster
docker swarm join --token <SWARM_TOKEN> <MANAGER_IP>:2377
