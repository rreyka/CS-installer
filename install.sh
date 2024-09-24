#!/bin/bash

ask_password() {
    while true; do
        read -s -p "Enter a password for code-server: " password
        echo
        read -s -p "Confirm password: " password_confirm
        echo
        if [ "$password" == "$password_confirm" ]; then
            echo "Password has been set."
            break
        else
            echo "Passwords do not match. Please try again."
        fi
    done
}

ask_port() {
    while true; do
        read -p "Enter the port number you want to use for code-server (default is 8080): " port
        if [[ -z "$port" ]]; then
            port=8080
        fi
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
            echo "Port has been set to $port."
            break
        else
            echo "Invalid port number. Please enter a valid number between 1 and 65535."
        fi
    done
}

current_user=$(whoami)

ask_password

ask_port

echo "Updating packages..."
sudo apt update -y

if ! [ -x "$(command -v curl)" ]; then
    echo "Installing curl..."
    sudo apt install curl -y
fi

if ! [ -x "$(command -v netstat)" ]; then
    echo "Installing net-tools..."
    sudo apt install net-tools -y
fi

echo "Installing code-server..."
curl -fsSL https://code-server.dev/install.sh | sh

echo "Checking UFW firewall status..."
UFW_STATUS=$(sudo ufw status | grep "Status: active")
if [ -n "$UFW_STATUS" ]; then
    echo "Opening port $port in UFW..."
    sudo ufw allow $port/tcp
else
    echo "UFW is inactive, opening port using iptables..."
    sudo iptables -C INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
    if [ $? -ne 0 ]; then
        sudo iptables -A INPUT -p tcp --dport $port -j ACCEPT
        echo "Port $port has been opened using iptables."
    else
        echo "Port $port is already open."
    fi
fi

echo "Configuring systemd service for code-server..."

SERVICE_FILE="/etc/systemd/system/code-server@.service"
sudo bash -c "cat > $SERVICE_FILE" <<EOL
[Unit]
Description=code-server
After=network.target

[Service]
User=$current_user
WorkingDirectory=/home/$current_user
Environment=PASSWORD=$password
ExecStart=/usr/bin/code-server --bind-addr 0.0.0.0:$port
Restart=always

[Install]
WantedBy=multi-user.target
EOL

if [ "$current_user" == "root" ]; then
    echo "Fixing working directory for root user..."
    sudo sed -i 's|/home/root|/root|' $SERVICE_FILE
fi

echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "Enabling and starting code-server service..."
sudo systemctl enable --now code-server@$current_user

echo "Checking code-server service status..."
sudo systemctl status code-server@$current_user

echo "Verifying that code-server is listening on port $port..."
sudo netstat -tuln | grep $port

echo "Installation and configuration of code-server is complete!"
echo "You can access code-server in your browser at http://<IP-Server>:$port"

echo "Switching shell to Bash and configuring prompt..."
chsh -s /bin/bash $current_user
echo "export PS1='\[\e[32m\]\w\[\e[0m\]$ '" >> ~/.bashrc

exec bash
