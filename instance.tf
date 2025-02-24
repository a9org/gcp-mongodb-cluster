# Random MongoDB password
resource "random_password" "mongodb" {
  length           = 14
  special          = true
  override_special = "&8h8a9QogDb3y"
}

# Random MongoDB KeyFile com caracteres válidos
resource "random_password" "mongodb_keyfile_content" {
  length           = 756 # Tamanho recomendado pelo MongoDB
  special          = true
  override_special = "=+.-_" # Apenas caracteres especiais aceitos pelo MongoDB
  min_lower        = 10
  min_upper        = 10
  min_numeric      = 10
  min_special      = 4
}

# Local KeyFile
resource "local_file" "mongodb_keyfile" {
  content  = base64encode(random_password.mongodb_keyfile_content.result)
  filename = "${path.module}/mongodb-keyfile"
}

# Discos adicionais para dados
resource "google_compute_disk" "mongodb_data_disk" {
  count = var.replica_count
  name  = "${local.prefix_name}-mongodb-data-disk-${format("%04d", count.index)}"
  type  = "pd-ssd"
  size  = var.mongodb_data_disk_size
  zone  = "${var.region}-${element(["a", "b", "c"], count.index % 3)}"
}

# Discos adicionais para logs
resource "google_compute_disk" "mongodb_logs_disk" {
  count = var.replica_count
  name  = "${local.prefix_name}-mongodb-logs-disk-${format("%04d", count.index)}"
  type  = "pd-ssd"
  size  = var.mongodb_logs_disk_size
  zone  = "${var.region}-${element(["a", "b", "c"], count.index % 3)}"
}

# Cluster MongoDB
resource "google_compute_instance" "mongodb_nodes" {
  count        = var.replica_count
  name         = "${local.prefix_name}-mongodb-node-${format("%04d", count.index)}"
  machine_type = var.machine_type
  zone         = "${var.region}-${element(["a", "b", "c"], count.index % 3)}" # Distribui entre zonas

  tags = ["${local.prefix_name}-mongodb-node", "mongodb-node"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = 30
      type  = "pd-ssd"
    }
    auto_delete = true
  }

  # Disco de dados
  attached_disk {
    source      = google_compute_disk.mongodb_data_disk[count.index].self_link
    device_name = "mongodb-data"
    mode        = "READ_WRITE"
  }

  # Disco de logs
  attached_disk {
    source      = google_compute_disk.mongodb_logs_disk[count.index].self_link
    device_name = "mongodb-logs"
    mode        = "READ_WRITE"
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
  }

  metadata = {
    ssh-keys       = "ubuntu:${var.ssh_public_key}"
    startup-script = <<-EOF
    #!/bin/bash
    set -e
    set -x

    # Funções utilitárias
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/mongodb/startup.log
        echo "$1"
    }

    get_instance_metadata() {
        curl -s "http://metadata.google.internal/computeMetadata/v1/$1" -H "Metadata-Flavor: Google"
    }

wait_for_disk() {
        local disk_path=$1
        local max_attempts=30
        local attempt=1
        while [ $attempt -le $max_attempts ]; do
            if [ -b "$disk_path" ]; then
                log "Disco $disk_path encontrado"
                return 0
            fi
            log "Aguardando disco $disk_path... tentativa $attempt"
            sleep 2
            attempt=$((attempt + 1))
        done
        log "ERRO: Disco $disk_path não encontrado após $max_attempts tentativas"
        exit 1
    }

  # Instalação do MongoDB 6.0
  wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add -
  echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
  apt-get update
  apt-get install -y mongodb-org

  # Configuração dos discos
  DATA_DISK="/dev/disk/by-id/google-mongodb-data"
  LOGS_DISK="/dev/disk/by-id/google-mongodb-logs"

  # Aguarda os discos estarem disponíveis
  wait_for_disk "$DATA_DISK"
  wait_for_disk "$LOGS_DISK"

  # Formata e monta o disco de dados
  if ! file -s $DATA_DISK | grep -q "XFS"; then
      log "Formatando disco de dados $DATA_DISK como XFS"
      mkfs.xfs $DATA_DISK || { log "ERRO: Falha ao formatar $DATA_DISK"; exit 1; }
  else
      log "Disco $DATA_DISK já formatado como XFS"
  fi
  mkdir -p /data/mongodb
  mount $DATA_DISK /data/mongodb || { log "ERRO: Falha ao montar $DATA_DISK em /data/mongodb"; exit 1; }
  echo "$DATA_DISK /data/mongodb xfs defaults,nofail 0 2" >> /etc/fstab

  # Formata e monta o disco de logs
  if ! file -s $LOGS_DISK | grep -q "XFS"; then
      log "Formatando disco de logs $LOGS_DISK como XFS"
      mkfs.xfs $LOGS_DISK || { log "ERRO: Falha ao formatar $LOGS_DISK"; exit 1; }
  else
      log "Disco $LOGS_DISK já formatado como XFS"
  fi
  mkdir -p /var/log/mongodb
  mount $LOGS_DISK /var/log/mongodb || { log "ERRO: Falha ao montar $LOGS_DISK em /var/log/mongodb"; exit 1; }
  echo "$LOGS_DISK /var/log/mongodb xfs defaults,nofail 0 2" >> /etc/fstab

  # Ajusta permissões
  chown -R mongodb:mongodb /data/mongodb /var/log/mongodb
  chmod 755 /data/mongodb /var/log/mongodb
    
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
security:
  keyFile: /etc/mongodb-keyfile
  authorization: enabled
EOL

    # Cria o arquivo de chave
    echo "${random_password.mongodb_keyfile_content.result}" | base64 > /etc/mongodb-keyfile
    chmod 600 /etc/mongodb-keyfile
    chown mongodb:mongodb /etc/mongodb-keyfile

    # Inicia o MongoDB
    systemctl start mongod
    systemctl enable mongod

    # Aguarda o MongoDB iniciar
    for i in {1..30}; do
      if mongosh --quiet --eval "db.adminCommand('ping')" &>/dev/null; then
        log "MongoDB iniciado com sucesso"
        break
      fi
      sleep 5
    done

    # Definir variáveis de autenticação
    MONGO_ADMIN_USER="admin"
    MONGO_ADMIN_PWD="${random_password.mongodb.result}"

    # Obter informações da instância
    INSTANCE_NAME=$(hostname -f | awk -F '.' '{print $1}')
    prefix_name=${local.prefix_name}
    replica_count=${var.replica_count}

    # Depuração
    log "Hostname: $INSTANCE_NAME"

    # Determinar se é o primário (índice 0)
    PRIMARY_NAME="$${prefix_name}-mongodb-node-0000"

    if [ "$PRIMARY_NAME" = "$INSTANCE_NAME" ]; then
      log "Esta é a instância primária (índice 0). Iniciando ReplicaSet..."

# Construção corrigida do rs_config
      rs_config='{"_id": "rs0", "members": ['
      first_member="{\"_id\": 0, \"host\": \"$${INSTANCE_NAME}:27017\", \"priority\": 2}"
      rs_config="$${rs_config}$${first_member}"
      for i in $(seq 1 $((replica_count - 1))); do
        secondary_suffix=$(printf "%04d" $i)
        secondary_name="$${prefix_name}-mongodb-node-$${secondary_suffix}"
        rs_config="$${rs_config},{\"_id\": $i, \"host\": \"$${secondary_name}:27017\", \"priority\": 1}"
      done
      rs_config="$${rs_config}]}"

      log "Configuração do ReplicaSet: $${rs_config}"
      mongosh --eval 'rs.initiate('"$${rs_config}"')' --quiet

      for i in {1..60}; do
        if mongosh --quiet --eval "rs.isMaster().ismaster" 2>/dev/null | grep -q "true"; then
          log "ReplicaSet iniciado com sucesso"
          mongosh admin --eval "db.createUser({user: '$${MONGO_ADMIN_USER}', pwd: '$${MONGO_ADMIN_PWD}', roles: ['root']})"
          log "Usuário admin criado"
          break
        fi
        sleep 5
      done
    else
      log "Esta é uma instância secundária. Tentando se juntar ao ReplicaSet..."

      for i in {1..120}; do
        if mongosh --host "$PRIMARY_NAME" \
          -u "$${MONGO_ADMIN_USER}" \
          -p "$${MONGO_ADMIN_PWD}" \
          --authenticationDatabase admin \
          --quiet \
          --eval "rs.isMaster().ismaster" 2>/dev/null | grep -q "true"; then
          
          log "Primário encontrado em $PRIMARY_NAME. Adicionando esta instância..."
          mongosh --host "$PRIMARY_NAME" \
                -u "$${MONGO_ADMIN_USER}" \
                -p "$${MONGO_ADMIN_PWD}" \
                --authenticationDatabase admin \
                --eval "rs.add('$${INSTANCE_NAME}:27017')"
          break
        fi
        sleep 5
      done
    fi

    log "Configuração concluída com sucesso"
    EOF
  }
  service_account {
    scopes = [
      "compute-ro",
      "storage-ro",
      "cloud-platform"
    ]
  }

  labels = local.common_tags
}