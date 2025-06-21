#!/bin/bash

# =============================================================================
# USER DATA SCRIPT - PROJETO VM
# =============================================================================

set -e

# Variables
PROJECT_NAME="${project_name}"
ENVIRONMENT="${environment}"
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Logging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting user data script for ${PROJECT_NAME}-${ENVIRONMENT}"

# =============================================================================
# SYSTEM UPDATE
# =============================================================================

echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# =============================================================================
# INSTALL ESSENTIAL PACKAGES
# =============================================================================

echo "Installing essential packages..."
apt-get install -y \
    curl \
    wget \
    git \
    unzip \
    jq \
    htop \
    nginx \
    docker.io \
    docker-compose \
    python3 \
    python3-pip \
    nodejs \
    npm

# =============================================================================
# CONFIGURE DOCKER
# =============================================================================

echo "Configuring Docker..."
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# =============================================================================
# CONFIGURE NGINX
# =============================================================================

echo "Configuring Nginx..."

cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80;
    server_name _;

    location / {
        return 200 "Hello from ${PROJECT_NAME}-${ENVIRONMENT} instance ${INSTANCE_ID}";
        add_header Content-Type text/plain;
    }

    location /health {
        return 200 "healthy";
        add_header Content-Type text/plain;
    }

    location /metadata {
        return 200 '{"instance_id":"${INSTANCE_ID}","region":"${REGION}","project":"${PROJECT_NAME}","environment":"${ENVIRONMENT}"}';
        add_header Content-Type application/json;
    }
}
EOF

systemctl enable nginx
systemctl restart nginx

# =============================================================================
# INSTALL CLOUDWATCH AGENT
# =============================================================================

echo "Installing CloudWatch agent..."
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/user-data.log",
                        "log_group_name": "/aws/ec2/${PROJECT_NAME}-${ENVIRONMENT}",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/nginx/access.log",
                        "log_group_name": "/aws/ec2/${PROJECT_NAME}-${ENVIRONMENT}/nginx",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/nginx/error.log",
                        "log_group_name": "/aws/ec2/${PROJECT_NAME}-${ENVIRONMENT}/nginx",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    },
    "metrics": {
        "metrics_collected": {
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# =============================================================================
# CREATE APPLICATION DIRECTORY
# =============================================================================

echo "Creating application directory..."
mkdir -p /opt/${PROJECT_NAME}
cd /opt/${PROJECT_NAME}

# Create a simple Node.js application
cat > app.js << 'EOF'
const express = require('express');
const app = express();
const port = 3000;

app.get('/', (req, res) => {
    res.json({
        message: `Hello from ${PROJECT_NAME}-${ENVIRONMENT}`,
        instance_id: process.env.INSTANCE_ID || 'unknown',
        region: process.env.REGION || 'unknown',
        timestamp: new Date().toISOString()
    });
});

app.get('/health', (req, res) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.get('/metadata', (req, res) => {
    res.json({
        instance_id: process.env.INSTANCE_ID || 'unknown',
        region: process.env.REGION || 'unknown',
        project: process.env.PROJECT_NAME || 'unknown',
        environment: process.env.ENVIRONMENT || 'unknown'
    });
});

app.listen(port, () => {
    console.log(`App listening at http://localhost:${port}`);
});
EOF

# Create package.json
cat > package.json << 'EOF'
{
  "name": "${PROJECT_NAME}-app",
  "version": "1.0.0",
  "description": "Projeto VM Application",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

# Install dependencies
npm install

# Create systemd service
cat > /etc/systemd/system/${PROJECT_NAME}.service << EOF
[Unit]
Description=${PROJECT_NAME} Application
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/${PROJECT_NAME}
Environment=INSTANCE_ID=${INSTANCE_ID}
Environment=REGION=${REGION}
Environment=PROJECT_NAME=${PROJECT_NAME}
Environment=ENVIRONMENT=${ENVIRONMENT}
ExecStart=/usr/bin/node app.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl enable ${PROJECT_NAME}
systemctl start ${PROJECT_NAME}

# =============================================================================
# CONFIGURE NGINX PROXY
# =============================================================================

echo "Configuring Nginx proxy..."

cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    location /health {
        proxy_pass http://localhost:3000/health;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /metadata {
        proxy_pass http://localhost:3000/metadata;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

systemctl restart nginx

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

echo "Configuring security..."

# Configure firewall
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp

# =============================================================================
# MONITORING SETUP
# =============================================================================

echo "Setting up monitoring..."

# Create monitoring script
cat > /opt/${PROJECT_NAME}/monitor.sh << 'EOF'
#!/bin/bash

# Check application health
if ! curl -f http://localhost:3000/health > /dev/null 2>&1; then
    echo "Application health check failed"
    systemctl restart ${PROJECT_NAME}
fi

# Check nginx health
if ! systemctl is-active --quiet nginx; then
    echo "Nginx is not running"
    systemctl restart nginx
fi

# Check disk usage
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 80 ]; then
    echo "Disk usage is high: ${DISK_USAGE}%"
fi
EOF

chmod +x /opt/${PROJECT_NAME}/monitor.sh

# Add to crontab
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/${PROJECT_NAME}/monitor.sh") | crontab -

# =============================================================================
# FINAL SETUP
# =============================================================================

echo "Final setup..."

# Create info file
cat > /opt/${PROJECT_NAME}/info.txt << EOF
Project: ${PROJECT_NAME}
Environment: ${ENVIRONMENT}
Instance ID: ${INSTANCE_ID}
Region: ${REGION}
Deployed: $(date)
EOF

# Set proper permissions
chown -R ubuntu:ubuntu /opt/${PROJECT_NAME}

echo "User data script completed successfully!"
echo "Application is running at http://localhost:3000"
echo "Nginx is serving at http://localhost:80" 