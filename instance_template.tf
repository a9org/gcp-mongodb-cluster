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
      mkfs.xfs /dev/disk/by-id/google-mongodb-data
      mkdir -p /data/mongodb
      mount /dev/disk/by-id/google-mongodb-data /data/mongodb
      
      mkfs.xfs /dev/disk/by-id/google-mongodb-logs
      mkdir -p /var/log/mongodb
      mount /dev/disk/by-id/google-mongodb-logs /var/log/mongodb

      # Adicionar ao fstab
      echo "/dev/disk/by-id/google-mongodb-data /data/mongodb xfs defaults,nofail 0 2" >> /etc/fstab
      echo "/dev/disk/by-id/google-mongodb-logs /var/log/mongodb xfs defaults,nofail 0 2" >> /etc/fstab

      # Ajuste das permissões
      chown -R mongodb:mongodb /data/mongodb
      chown -R mongodb:mongodb /var/log/mongodb
      chmod 755 /data/mongodb
      chmod 755 /var/log/mongodb

      # Obtém o número do shard do nome da instância
      SHARD_NUMBER=$(echo $INSTANCE_NAME | grep -o '[0-9]*$')
      
      # Configuração do MongoDB com autenticação e sharding
      cat > /etc/mongod.conf <<EOL
      storage:
        dbPath: /data/mongodb
        journal:
          enabled: true
        wiredTiger:
          engineConfig:
            cacheSizeGB: 1
      
      systemLog:
        destination: file
        path: /var/log/mongodb/mongod.log
        logAppend: true
        logRotate: reopen
      
      net:
        port: 27018
        bindIp: 0.0.0.0
        maxIncomingConnections: 20000
      
      security:
        keyFile: /data/mongodb/keyfile
        authorization: enabled
      
      replication:
        replSetName: "rs-shard-$SHARD_NUMBER"
      
      sharding:
        clusterRole: shardsvr
      
      operationProfiling:
        mode: slowOp
        slowOpThresholdMs: 100
      EOL

      # Criar keyfile para autenticação entre membros do cluster
      openssl rand -base64 756 > /data/mongodb/keyfile
      chmod 400 /data/mongodb/keyfile
      chown mongodb:mongodb /data/mongodb/keyfile

      # Iniciar MongoDB
      systemctl start mongod
      systemctl enable mongod

      # Aguardar o MongoDB iniciar
      sleep 30

      # Obter informações da instância
      INSTANCE_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/name" -H "Metadata-Flavor: Google")
      CONFIG_SERVER_URL="${google_compute_forwarding_rule.mongodb_config.ip_address}:27019"

      # Se for o primeiro node do shard
      if [[ $INSTANCE_NAME == *"-0" ]]; then
        # Inicializar o replica set
        mongosh --port 27018 admin --eval "
          rs.initiate({
            _id: 'rs-shard-$SHARD_NUMBER',
            members: [{
              _id: 0,
              host: '$(hostname -f):27018',
              priority: 1
            }]
          });
        "

        # Aguardar a inicialização
        sleep 30

        # Criar usuário admin
        mongosh --port 27018 admin --eval "
          db.createUser({
            user: 'admin',
            pwd: '${random_password.mongodb.result}',
            roles: ['root']
          });
        "

        # Criar usuário para sharding
        mongosh --port 27018 admin -u admin -p '${random_password.mongodb.result}' --eval "
          db.createUser({
            user: 'sharduser',
            pwd: '${random_password.mongodb_shard.result}',
            roles: ['clusterAdmin']
          });
        "
      else
        # Se não for o primeiro node, aguardar o primary
        until mongosh --port 27018 --eval "rs.status()" &>/dev/null; do
          sleep 10
        done

        # Adicionar ao replica set
        PRIMARY_HOST=$(mongosh --port 27018 --quiet --eval "rs.isMaster().primary")
        mongosh --host $PRIMARY_HOST --port 27018 --eval "
          rs.add('$(hostname -f):27018');
        "
      fi

      # Configurar logrotate
      cat > /etc/logrotate.d/mongodb <<EOL
      /var/log/mongodb/mongod.log {
        daily
        rotate 30
        compress
        dateext
        missingok
        notifempty
        sharedscripts
        postrotate
          /bin/kill -SIGUSR1 \$(cat /var/lib/mongodb/mongod.pid)
        endscript
      }
      EOL

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

# Config Servers - Instance Template
resource "google_compute_instance_template" "mongodb_config" {
  name        = "${local.prefix_name}-mongodb-config-template"
  description = "Template for MongoDB Config Servers"

  tags = ["${local.prefix_name}-mongodb-config"]

  machine_type = "e2-medium" # 2 vCPU, 4GB RAM - adequado para config servers

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
    disk_size_gb = 50
    disk_type    = "pd-ssd"
    device_name  = "mongodb-config-data"
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
  }

  metadata = {
    startup-script = <<-EOF
      #!/bin/bash
      set -e

      # Instalação do MongoDB
      wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add -
      echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
      apt-get update
      apt-get install -y mongodb-org

      # Configuração do disco de dados
      mkfs.xfs /dev/disk/by-id/google-mongodb-config-data
      mkdir -p /data/configdb
      mount /dev/disk/by-id/google-mongodb-config-data /data/configdb
      echo "/dev/disk/by-id/google-mongodb-config-data /data/configdb xfs defaults,nofail 0 2" >> /etc/fstab

      chown -R mongodb:mongodb /data/configdb

      # Configuração do Config Server
      cat > /etc/mongod.conf <<EOL
      storage:
        dbPath: /data/configdb
      systemLog:
        destination: file
        path: /var/log/mongodb/mongod.log
        logAppend: true
      net:
        port: 27019
        bindIp: 0.0.0.0
      replication:
        replSetName: "configReplSet"
      sharding:
        clusterRole: configsvr
      EOL

      systemctl start mongod
      systemctl enable mongod

      sleep 30

      # Inicializa o Replica Set se for o primeiro node
      if [[ $HOSTNAME == *"-0" ]]; then
        mongosh --port 27019 --eval "
          rs.initiate({
            _id: 'configReplSet',
            configsvr: true,
            members: [{
              _id: 0,
              host: '$(hostname -f):27019',
              priority: 1
            }]
          })
        "
      fi
    EOF
  }

  service_account {
    scopes = ["compute-ro", "storage-ro", "cloud-platform"]
  }

  labels = merge(local.common_tags, {
    role = "config-server"
  })
}

# Config Servers - Instance Group
resource "google_compute_region_instance_group_manager" "mongodb_config" {
  name = "${local.prefix_name}-mongodb-config-mig"

  base_instance_name = "${local.prefix_name}-mongodb-config"
  region             = var.region

  version {
    instance_template = google_compute_instance_template.mongodb_config.id
  }

  target_size = 3 # Sempre 3 config servers para redundância

  named_port {
    name = "mongodb-config"
    port = 27019
  }
}

# Mongos Routers - Instance Template
resource "google_compute_instance_template" "mongodb_router" {
  name        = "${local.prefix_name}-mongodb-router-template"
  description = "Template for MongoDB Router (mongos)"

  tags = ["${local.prefix_name}-mongodb-router"]

  machine_type = "e2-standard-2" # 2 vCPU, 8GB RAM

  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2004-lts"
    auto_delete  = true
    boot         = true
    disk_size_gb = 30
    disk_type    = "pd-ssd"
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
  }

  metadata = {
    startup-script = <<-EOF
      #!/bin/bash
      set -e

      # Instalação do MongoDB
      wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add -
      echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
      apt-get update
      apt-get install -y mongodb-org

      # Configuração do Mongos Router
      cat > /etc/mongos.conf <<EOL
      systemLog:
        destination: file
        path: /var/log/mongodb/mongos.log
        logAppend: true
      net:
        port: 27017
        bindIp: 0.0.0.0
      sharding:
        configDB: configReplSet/${google_compute_forwarding_rule.mongodb_config.ip_address}:27019
      EOL

      # Criar serviço para o mongos
      cat > /lib/systemd/system/mongos.service <<EOL
      [Unit]
      Description=MongoDB Router
      After=network.target

      [Service]
      User=mongodb
      Group=mongodb
      ExecStart=/usr/bin/mongos --config /etc/mongos.conf
      Restart=always

      [Install]
      WantedBy=multi-user.target
      EOL

      systemctl daemon-reload
      systemctl start mongos
      systemctl enable mongos

      # Aguardar config servers estarem disponíveis
      sleep 60

      # Adicionar shards ao cluster
      mongosh --port 27017 --eval "
        sh.addShard('rs-shard-1/${google_compute_forwarding_rule.mongodb_forwarding_rule[0].ip_address}:27017')
        sh.addShard('rs-shard-2/${google_compute_forwarding_rule.mongodb_forwarding_rule[1].ip_address}:27017')
        sh.addShard('rs-shard-3/${google_compute_forwarding_rule.mongodb_forwarding_rule[2].ip_address}:27017')
      "
    EOF
  }

  service_account {
    scopes = ["compute-ro", "storage-ro", "cloud-platform"]
  }

  labels = merge(local.common_tags, {
    role = "router"
  })
}

# Mongos Routers - Instance Group
resource "google_compute_region_instance_group_manager" "mongodb_router" {
  name = "${local.prefix_name}-mongodb-router-mig"

  base_instance_name = "${local.prefix_name}-mongodb-router"
  region             = var.region

  version {
    instance_template = google_compute_instance_template.mongodb_router.id
  }

  target_size = 2 # 2 routers para alta disponibilidade

  named_port {
    name = "mongodb"
    port = 27017
  }
}

# Load Balancer para Config Servers
resource "google_compute_region_backend_service" "mongodb_config_backend" {
  name          = "${local.prefix_name}-mongodb-config-backend"
  region        = var.region
  protocol      = "TCP"
  health_checks = [google_compute_health_check.mongodb_config_health_check.id]

  backend {
    group          = google_compute_region_instance_group_manager.mongodb_config.instance_group
    balancing_mode = "CONNECTION"
  }
}

resource "google_compute_forwarding_rule" "mongodb_config" {
  name                  = "${local.prefix_name}-mongodb-config-forwarding"
  region                = var.region
  port_range            = "27019"
  backend_service       = google_compute_region_backend_service.mongodb_config_backend.id
  load_balancing_scheme = "INTERNAL"
  network               = var.network
  subnetwork            = var.subnetwork
}

# Load Balancer para Routers
resource "google_compute_region_backend_service" "mongodb_router_backend" {
  name          = "${local.prefix_name}-mongodb-router-backend"
  region        = var.region
  protocol      = "TCP"
  health_checks = [google_compute_health_check.mongodb_router_health_check.id]

  backend {
    group          = google_compute_region_instance_group_manager.mongodb_router.instance_group
    balancing_mode = "CONNECTION"
  }
}
resource "google_compute_forwarding_rule" "mongodb_router" {
  name                  = "${local.prefix_name}-mongodb-router-forwarding"
  region                = var.region
  port_range            = "27017"
  backend_service       = google_compute_region_backend_service.mongodb_router_backend.id
  load_balancing_scheme = "INTERNAL"
  network               = var.network
  subnetwork            = var.subnetwork
}

# Health Checks
resource "google_compute_health_check" "mongodb_config_health_check" {
  name               = "${local.prefix_name}-mongodb-config-health"
  check_interval_sec = 5
  timeout_sec        = 5

  tcp_health_check {
    port = 27019
  }
}

resource "google_compute_health_check" "mongodb_router_health_check" {
  name               = "${local.prefix_name}-mongodb-router-health"
  check_interval_sec = 5
  timeout_sec        = 5

  tcp_health_check {
    port = 27017
  }
}