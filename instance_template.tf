# Random MongoDB password
resource "random_password" "mongodb" {
  length           = 14
  special          = true
  override_special = "&8h8a9QogDb3y"
}


# Instance Template
resource "google_compute_instance_template" "mongodb_template" {
  name        = "${local.prefix_name}-mongodb-template"
  description = "Template for MongoDB ReplicaSet instances"

  tags = ["${local.prefix_name}-mongodb-node"]

  machine_type = var.machine_type

  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2004-lts"
    auto_delete  = true
    boot         = true
    disk_size_gb = 30
    disk_type    = "pd-ssd"
  }

  disk {
    auto_delete  = true
    boot         = false
    disk_size_gb = var.mongodb_data_disk_size
    disk_type    = "pd-ssd"
    device_name  = "mongodb-data"
    interface    = "SCSI"
  }

  disk {
    auto_delete  = true
    boot         = false
    disk_size_gb = var.mongodb_logs_disk_size
    disk_type    = "pd-ssd"
    device_name  = "mongodb-logs"
    interface    = "SCSI"
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
  }

  metadata = {
    ssh-keys = "ubuntu:${var.ssh_public_key}"  # Adicionando a chave SSH
    startup-script = <<EOF
#!/bin/bash
set -e

# Instalação do MongoDB 6.0
wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
apt-get update
apt-get install -y mongodb-org

# Função para esperar disco ficar disponível
wait_for_disk() {
  local disk_name=$1
  local max_attempts=60
  local attempt=1
  
  while [ $attempt -le $max_attempts ]; do
    if [ -b "$disk_name" ]; then
      return 0
    fi
    echo "Aguardando disco $disk_name ficar disponível... tentativa $attempt"
    sleep 5
    attempt=$((attempt + 1))
  done
  
  echo "Timeout esperando pelo disco $disk_name"
  return 1
}

# Configuração dos discos
DATA_DISK="/dev/sdb"
LOGS_DISK="/dev/sdc"

# Aguarda os discos ficarem disponíveis
wait_for_disk $DATA_DISK
wait_for_disk $LOGS_DISK

# Disco de dados
if [ -b "$DATA_DISK" ]; then
  echo "Formatando disco de dados..."
  mkfs.xfs $DATA_DISK
  mkdir -p /data/mongodb
  mount $DATA_DISK /data/mongodb
  echo "$DATA_DISK /data/mongodb xfs defaults,nofail 0 2" >> /etc/fstab
else
  echo "ERRO: Disco de dados não encontrado!"
  exit 1
fi

# Disco de logs
if [ -b "$LOGS_DISK" ]; then
  echo "Formatando disco de logs..."
  mkfs.xfs $LOGS_DISK
  mkdir -p /var/log/mongodb
  mount $LOGS_DISK /var/log/mongodb
  echo "$LOGS_DISK /var/log/mongodb xfs defaults,nofail 0 2" >> /etc/fstab
else
  echo "ERRO: Disco de logs não encontrado!"
  exit 1
fi

# Ajuste das permissões
chown -R mongodb:mongodb /data/mongodb
chown -R mongodb:mongodb /var/log/mongodb
chmod 755 /data/mongodb
chmod 755 /var/log/mongodb

# Configuração do MongoDB
cat > /etc/mongod.conf <<EOL
storage:
  dbPath: /data/mongodb
  journal:
    enabled: true
systemLog:
  destination: file
  path: /var/log/mongodb/mongod.log
  logAppend: true
net:
  port: 27017
  bindIp: 0.0.0.0
replication:
  replSetName: "rs0"
EOL

# Inicialização do MongoDB
systemctl start mongod
systemctl enable mongod

sleep 30

# Inicializa o Replica Set
INSTANCE_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/name" -H "Metadata-Flavor: Google")

# Inicializa o Replica Set se for o primeiro node
if [[ $INSTANCE_NAME == *"-0" ]]; then
  mongosh --eval "
    rs.initiate({
      _id: 'rs0',
      members: [{
        _id: 0,
        host: '$(hostname -f):27017',
        priority: 1
      }]
    })
  "

  sleep 30

  mongosh admin --eval "
    db.createUser({
      user: 'admin',
      pwd: '${random_password.mongodb.result}',
      roles: ['root']
    })
  "
else
  until mongosh --eval "rs.status()" &>/dev/null; do
    sleep 10
  done

  PRIMARY_HOST=$(mongosh --quiet --eval "rs.isMaster().primary")
  mongosh --host $PRIMARY_HOST --eval "
    rs.add('$(hostname -f):27017')
  "
fi

# Configuração do logrotate
cat > /etc/logrotate.d/mongodb <<EOL
/var/log/mongodb/mongod.log {
  daily
  rotate 7
  compress
  missingok
  notifempty
  copytruncate
}
EOL

# Log completion
echo "Startup script completed successfully"
EOF
  }  
  # O resto do template permanece igual
  service_account {
    scopes = [
      "compute-ro",
      "storage-ro",
      "cloud-platform"
    ]
  }

  labels = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}
