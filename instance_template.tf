# Random MongoDB password
resource "random_password" "mongodb" {
  length           = 14
  special          = true
  override_special = "&8h8a9QogDb3y"
}


# Instance Template
resource "google_compute_instance_template" "mongodb_template" {
  name        = "${local.prefix_name}-mongodb-template"
  description = "Template for MongoDB instances"

  tags = ["${local.prefix_name}-mongodb-node"]

  machine_type = var.machine_type

  # Disco do sistema operacional
  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2004-lts"
    auto_delete  = true
    boot         = true
    disk_size_gb = 30
    disk_type    = "pd-ssd"
  }

  # Disco para dados do MongoDB
  disk {
    auto_delete  = true
    boot         = false
    disk_size_gb = var.mongodb_data_disk_size
    disk_type    = "pd-ssd"
    device_name  = "mongodb-data"
    interface    = "SCSI"
  }

  # Disco para logs do MongoDB
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
    startup-script = <<-EOF
      #!/bin/bash
      set -e

      # Instalação do MongoDB 6.0
      wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add -
      echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
      apt-get update
      apt-get install -y mongodb-org

      # Configuração dos discos
      # Disco de dados
      mkfs.xfs /dev/disk/by-id/google-mongodb-data
      mkdir -p /data/mongodb
      mount /dev/disk/by-id/google-mongodb-data /data/mongodb
      echo "/dev/disk/by-id/google-mongodb-data /data/mongodb xfs defaults,nofail 0 2" >> /etc/fstab

      # Disco de logs
      mkfs.xfs /dev/disk/by-id/google-mongodb-logs
      mkdir -p /var/log/mongodb
      mount /dev/disk/by-id/google-mongodb-logs /var/log/mongodb
      echo "/dev/disk/by-id/google-mongodb-logs /var/log/mongodb xfs defaults,nofail 0 2" >> /etc/fstab

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
        replSetName: "rs-shard-\${SHARD_NUMBER}"
      sharding:
        clusterRole: shardsvr
      EOL

      # Inicialização do MongoDB
      systemctl start mongod
      systemctl enable mongod

      # Aguarda o MongoDB iniciar
      sleep 30

      # Inicializa o Replica Set
      INSTANCE_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/name" -H "Metadata-Flavor: Google")
      INSTANCE_ZONE=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor: Google" | cut -d'/' -f4)
      PROJECT_ID=$(curl -s "http://metadata.google.internal/computeMetadata/v1/project/project-id" -H "Metadata-Flavor: Google")

      # Obtém o número do shard a partir do nome da instância
      SHARD_NUMBER=$(echo $INSTANCE_NAME | grep -o '[0-9]*$')

      # Inicializa o Replica Set se for o primeiro node do shard
      if [[ $INSTANCE_NAME == *"-0" ]]; then
        mongosh --eval "
          rs.initiate({
            _id: 'rs-shard-${SHARD_NUMBER}',
            members: [{
              _id: 0,
              host: '$(hostname -f):27017',
              priority: 1
            }]
          })
        "

        # Aguarda a inicialização do replica set
        sleep 30

        # Configura autenticação
        mongosh admin --eval "
          db.createUser({
            user: 'admin',
            pwd: '${random_password.mongodb.result}', # Usa o password gerado
            roles: ['root']
          })
        "
      else
        # Se não for o primeiro node, aguarda o primary estar disponível
        until mongosh --eval "rs.status()" &>/dev/null; do
          sleep 10
        done

        # Adiciona este node ao replica set
        PRIMARY_HOST=$(mongosh --quiet --eval "rs.isMaster().primary")
        mongosh --host $PRIMARY_HOST --eval "
          rs.add('$(hostname -f):27017')
        "
      fi

      # Configuração do logrotate para o MongoDB
      echo "
      /var/log/mongodb/mongod.log {
      daily
      rotate 7
      compress
      missingok
      notifempty
      copytruncate
      }
      " > /etc/logrotate.d/mongodb

      EOF
  }

  service_account {
    scopes = [
      "compute-ro",    # Para metadata
      "storage-ro",    # Para logs
      "cloud-platform" # Para outras integrações GCP
    ]
  }

  labels = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}