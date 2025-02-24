#   # Random MongoDB password
#   resource "random_password" "mongodb" {
#     length           = 14
#     special          = true
#     override_special = "&8h8a9QogDb3y"
#   }

#   # Random MongoDB KeyFile com caracteres válidos
#   resource "random_password" "mongodb_keyfile_content" {
#     length           = 756 # Tamanho recomendado pelo MongoDB
#     special          = true
#     override_special = "=+.-_" # Apenas caracteres especiais aceitos pelo MongoDB
#     min_lower        = 10
#     min_upper        = 10
#     min_numeric      = 10
#     min_special      = 4
#   }

#   # Local KeyFile
#   resource "local_file" "mongodb_keyfile" {
#     content  = base64encode(random_password.mongodb_keyfile_content.result)
#     filename = "${path.module}/mongodb-keyfile"
#   }


#   # Instance Template
#   resource "google_compute_instance_template" "mongodb_template" {
#     name        = "${local.prefix_name}-mongodb-template"
#     description = "Template for MongoDB ReplicaSet instances"

#     tags = ["${local.prefix_name}-mongodb-node"]

#     machine_type = var.machine_type

#     disk {
#       source_image = "ubuntu-os-cloud/ubuntu-2004-lts"
#       auto_delete  = true
#       boot         = true
#       disk_size_gb = 30
#       disk_type    = "pd-ssd"
#     }

#     disk {
#       auto_delete  = true
#       boot         = false
#       disk_size_gb = var.mongodb_data_disk_size
#       disk_type    = "pd-ssd"
#       device_name  = "mongodb-data"
#       interface    = "SCSI"
#     }

#     disk {
#       auto_delete  = true
#       boot         = false
#       disk_size_gb = var.mongodb_logs_disk_size
#       disk_type    = "pd-ssd"
#       device_name  = "mongodb-logs"
#       interface    = "SCSI"
#     }

#     network_interface {
#       network    = var.network
#       subnetwork = var.subnetwork
#     }

#     metadata = {
#       ssh-keys           = "ubuntu:${var.ssh_public_key}"
#       prefix_name        = local.prefix_name  # Passar prefix_name como metadado
#       startup-script     = <<-EOF
#   #!/bin/bash
#   set -e
#   set -x  # Ativar depuração para rastrear execução

#   # Funções utilitárias
#   log() {
#       echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/mongodb/startup.log
#       echo "$1"
#   }

#   get_instance_metadata() {
#       curl -s "http://metadata.google.internal/computeMetadata/v1/$1" -H "Metadata-Flavor: Google"
#   }

#   # Instalação do MongoDB 6.0
#   wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add -
#   echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
#   apt-get update
#   apt-get install -y mongodb-org

#   # Função para esperar disco ficar disponível
#   wait_for_disk() {
#     local disk_name=$1
#     local max_attempts=60
#     local attempt=1

#     while [ $attempt -le $max_attempts ]; do
#       if [ -b "$disk_name" ]; then
#         return 0
#       fi
#       sleep 5
#       attempt=$((attempt + 1))
#     done
#     return 1
#   }

#   # Configuração dos discos
#   DATA_DISK="/dev/sdb"
#   LOGS_DISK="/dev/sdc"

#   # Aguarda os discos ficarem disponíveis
#   wait_for_disk $DATA_DISK
#   wait_for_disk $LOGS_DISK

#   # Disco de dados
#   if [ -b "$DATA_DISK" ]; then
#     echo "Formatando disco de dados..."
#     mkfs.xfs $DATA_DISK
#     mkdir -p /data/mongodb
#     mount $DATA_DISK /data/mongodb
#     echo "$DATA_DISK /data/mongodb xfs defaults,nofail 0 2" >> /etc/fstab
#   else
#     echo "ERRO: Disco de dados não encontrado!"
#     exit 1
#   fi

#   # Disco de logs
#   if [ -b "$LOGS_DISK" ]; then
#     echo "Formatando disco de logs..."
#     mkfs.xfs $LOGS_DISK
#     mkdir -p /var/log/mongodb
#     mount $LOGS_DISK /var/log/mongodb
#     echo "$LOGS_DISK /var/log/mongodb xfs defaults,nofail 0 2" >> /etc/fstab
#   else
#     echo "ERRO: Disco de logs não encontrado!"
#     exit 1
#   fi

#   # Ajuste das permissões
#   chown -R mongodb:mongodb /data/mongodb
#   chown -R mongodb:mongodb /var/log/mongodb
#   chmod 755 /data/mongodb
#   chmod 755 /var/log/mongodb

#   # Configuração do MongoDB
# cat > /etc/mongod.conf <<EOL
# storage:
#   dbPath: /data/mongodb
#   journal:
#     enabled: true
# systemLog:
#   destination: file
#   path: /var/log/mongodb/mongod.log
#   logAppend: true
# net:
#   port: 27017
#   bindIp: 0.0.0.0
# replication:
#   replSetName: "rs0"
# security:
#   keyFile: /etc/mongodb-keyfile
#   authorization: enabled
# EOL

#   # Cria o arquivo de chave
#   echo "${random_password.mongodb_keyfile_content.result}" | base64 > /etc/mongodb-keyfile
#   chmod 600 /etc/mongodb-keyfile
#   chown mongodb:mongodb /etc/mongodb-keyfile

# # Inicia o MongoDB
#   systemctl start mongod
#   systemctl enable mongod

#   # Aguarda o MongoDB iniciar
#   for i in {1..30}; do
#     if mongosh --quiet --eval "db.adminCommand('ping')" &>/dev/null; then
#       log "MongoDB iniciado com sucesso"
#       break
#     fi
#     sleep 5
#   done

#   # Definir variáveis de autenticação
#   MONGO_ADMIN_USER="admin"
#   MONGO_ADMIN_PWD="${random_password.mongodb.result}"

#   # Obter informações da instância e do MIG
#   INSTANCE_NAME=$(hostname -f)
#   prefix_name="${local.prefix_name}"
#   project=$(get_instance_metadata "project/project-id")
#   zone=$(get_instance_metadata "instance/zone" | cut -d'/' -f4)
#   region=${var.region}

#   # Depuração
#   log "Valor de prefix_name: $prefix_name"
#   if [ -z "$prefix_name" ]; then
#     log "ERRO: prefix_name está vazio!"
#     exit 1
#   fi
#   log "Valor de region: $region"
#   if [ -z "$region" ]; then
#     log "ERRO: region está vazio!"
#     exit 1
#   fi

#   mig_name="${local.prefix_name}-mongodb-nodes"
#   log "Valor de mig_name: $mig_name"

#   # Configurar o gcloud
#   gcloud config set project "$project"
#   gcloud config set compute/zone "$zone"

#   # Listar todas as instâncias do MIG
#   INSTANCES=$(gcloud compute instance-groups managed list-instances "$mig_name" \
#               --region="$region" \
#               --format="value(name)" | sort)
#   log "Instâncias encontradas: $INSTANCES"

#   # Determinar o primário (menor hostname alfanumérico)
#   PRIMARY_INSTANCE=$(echo "$INSTANCES" | head -n 1)
#   log "Instância primária: $PRIMARY_INSTANCE"

#   if [ "$INSTANCE_NAME" = "$PRIMARY_INSTANCE" ]; then
#     log "Esta é a instância primária. Iniciando ReplicaSet..."

#     # Construir configuração do ReplicaSet
#     rs_config='{"_id": "rs0", "members": ['
#     i=0
#     for instance in $INSTANCES; do
#       if [ $i -gt 0 ]; then
#         rs_config="$${rs_config},"
#       fi
#       if [ "$instance" = "$PRIMARY_INSTANCE" ]; then
#         rs_config="$${rs_config}{\"_id\": $i, \"host\": \"$instance:27017\", \"priority\": 2}"
#       else
#         rs_config="$${rs_config}{\"_id\": $i, \"host\": \"$instance:27017\", \"priority\": 1}"
#       fi
#       i=$((i + 1))
#     done
#     rs_config="$${rs_config}]}"

#     log "Configuração do ReplicaSet: $${rs_config}"
#     mongosh --eval "rs.initiate($${rs_config})" --quiet

#     # Aguarda o primário estar pronto e cria usuário admin
#     for i in {1..60}; do
#       if mongosh --quiet --eval "rs.isMaster().ismaster" 2>/dev/null | grep -q "true"; then
#         log "ReplicaSet iniciado com sucesso"
#         mongosh admin --eval "db.createUser({user: '$${MONGO_ADMIN_USER}', pwd: '$${MONGO_ADMIN_PWD}', roles: ['root']})"
#         log "Usuário admin criado"
#         break
#       fi
#       sleep 5
#     done
#   else
#     log "Esta é uma instância secundária. Tentando se juntar ao ReplicaSet..."

#     # Aguarda o primário estar disponível
#     for i in {1..120}; do
#       if mongosh --host "$PRIMARY_INSTANCE" \
#         -u "$${MONGO_ADMIN_USER}" \
#         -p "$${MONGO_ADMIN_PWD}" \
#         --authenticationDatabase admin \
#         --quiet \
#         --eval "rs.isMaster().ismaster" 2>/dev/null | grep -q "true"; then

#         log "Primário encontrado em $PRIMARY_INSTANCE. Adicionando esta instância..."
#         mongosh --host "$PRIMARY_INSTANCE" \
#               -u "$${MONGO_ADMIN_USER}" \
#               -p "$${MONGO_ADMIN_PWD}" \
#               --authenticationDatabase admin \
#               --eval "rs.add('$${INSTANCE_NAME}:27017')"
#         break
#       fi
#       sleep 5
#     done
#   fi

#   log "Configuração concluída com sucesso"
#   EOF
#   }
#     service_account {
#       scopes = [
#         "compute-ro",
#         "storage-ro",
#         "cloud-platform"
#       ]
#     }

#     labels = local.common_tags

#     lifecycle {
#       create_before_destroy = true
#     }
#   }
