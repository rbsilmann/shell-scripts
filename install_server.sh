#!/bin/bash

# Todas as funções aqui desenvolvidas trabalham utilizando o retorno como método de validação do sucesso
# ou da falha de alguma função, leve isso em consideração para a implementação de novos recursos.

# Desenvolvido e testado para distribuições Linux RedHat-Based 7+.

function SET()
{
    qtde=$(( ( `tput cols` - `echo -n $txt | wc -c` ) / 2 ))
    esp=$(for ((X=0;X<=qtde;X++)) { echo -n " " ; })
    echo -e "\033[1;$cor$esp$txt\033[0m\n"
}

function SETR()
{
    qtde=$(( ( `tput cols` - `echo -n $txt | wc -c` ) / 2 ))
    esp=$(for ((X=0;X<=qtde;X++)) { echo -n " " ; })
    echo -e -n "\n\033[1;$cor$esp$txt\033[0m"
}

function preto()
{
    txt=$@;cor="30m";SET; 
}

function vermelho()
{
    txt=$@;cor="31m";SET; 
}

function verde()
{
    txt=$@;cor="32m";SET; 
}

function amarelo()
{
    txt=$@;cor="33m";SET; 
}

function azul()
{
    txt=$@;cor="34m";SET; 
}

function purple()
{
    txt=$@;cor="35m";SET; 
}

function ciano()
{
    txt=$@;cor="36m";SET; 
}

function branco()
{
    txt=$@;cor="37m";SET; 
}

function readBranco()
{
    txt=$@;cor="37m";SETR; 
}

function testeConexao()
{
    # O código realiza um teste simples de ping, caso o teste de ping falhe ele interrompe a execução e
    # verifica se o DNS está configurado.
    ping 8.8.8.8 -c4 &> /dev/null
    case $? in
        0) return 0
        ;;
        1)  vermelho "O teste de ping falhou para o endereço DNS do Google (8.8.8.8)"
            cat /etc/resolv.conf | grep nameserver | cut -d" " -f2 > /tmp/dns
            DNS=$(ls -l /tmp/dns | awk '{print $5}')
            if [ $DNS -eq 0 ] 
            then
                branco "Dica: não identificamos o DNS configurado. Configure e tente novamente."
                sleep 5
                rm -rf /tmp/dns
            fi
            branco "Encerrando configuração."
            sleep 5
            return 1
        ;;
        *)  vermelho "Um erro inesperado aconteceu efetuando o teste de ping para o endereço configurado para teste."
            sleep 5
            return 1
        ;;
    esac
}

function verificarUsuario()
{
    # Esse script foi desenvolvido para administradores de sistemas, por conta disso deve ser executado
    # apenas com o super usuário do sistema (root).
    if [ $UID -eq 0 ] 
    then
        return 0
    else
        vermelho "O script só pode ser executado com o super usuário (root)."
        return 1
    fi
}

function configurarHostname()
{
    # A função realiza a alteração do hostname da máquina desde que o nome inserido não tenha caracteres
    # especiais.
    readBranco "Digite o nome que deseja colocar para o dispositivo: "
    read NOMEMAQUINA
    if [[ $NOMEMAQUINA =~ ['!@/\#$%^&*()_+'] ]] 
    then
        return 1
    else
        hostnamectl set-hostname $NOMEMAQUINA
        return 0
    fi
}

function gerenciadorPacotes()
{
    VERSAO=$(cat /etc/os-release | grep VERSION_ID | cut -d'"' -f2 | cut -d'.' -f1)
    case $VERSAO in
        7)  GERENCIADOR=yum
            return 0
        ;;
        8)  GERENCIADOR=dnf
            return 0
        ;;
        9)  GERENCIADOR=dnf
            return 0
        ;;
        *)  vermelho "Não foi possível definir a versão utilizando o arquivo /etc/os-release."
            branco "Dica: verifique se a versão que está entre as versões compatíveis: RHEL (7, 8, 9) | CentOS (7, 8 e 9) | RockyLinux (7, 8 e 9)"
            return 1
    esac
    
}

function instalarUtilitarios()
{
    # Função que será responsável por gerir os pacotes que serão instalados.
    # Essa função só deve ser chamada caso a função gerenciadorPacotes retorne 0.
    $GERENCIADOR update -y && \
    $GERENCIADOR install -y mlocate \
                            curl \
                            bc \
                            vim \
                            samba \
                            cifs-utils \
                            sysstat \
                            perl \
                            firewalld
    if [ $? -eq 0 ] 
    then
        return 0
    else
        return 1
    fi
}

function particoesSistema()
{
    # O código abaixo testa a existência de partições chamadas data ou dados.
    # O retorno 0 corresponde a existência dessas partições, já o retorno 1 corresponde a ausência delas.
    if [ 1 -eq 1 ] 
    then
        df -h | grep /dados | awk '{print $6}' > /tmp/particao
        PARTICAO=$(ls -l /tmp/particao | awk '{print $5}')
        if [ $PARTICAO -gt 0 ]
        then
            return 0
        elif [ $PARTICAO -eq 0 ] 
        then
            df -h | grep /data | awk '{print $6}' > /tmp/particao
            PARTICAO=$(ls -l /tmp/particao | awk '{print $5}')
            if [ $PARTICAO -gt 0 ]
            then
                return 0
            else
                return 1
            fi
        fi
    fi
}

function instalarPostgres()
{
    # Instalação do PostgreSQL 12.
    # Essa função só pode ser chamada caso o retorno da gerenciadorPacotes seja 0.
    $GERENCIADOR install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-$VERSAO-x86_64/pgdg-redhat-repo-latest.noarch.rpm
    if [ $VERSAO -gt 7 ]
    then
        $GERENCIADOR -qy module disable postgresql  
    fi
    $GERENCIADOR install -y postgresql12-server \
                            postgresql12-contrib
    # A função chamada aqui verifica a existência de partições de dados personalizadas
    # caso ele encontre /data ou /dados, utilizará elas para realizar a instalação do
    # cluster PostgreSQL.
    particoesSistema
    if [ $? -eq 0 ]
    then
        DIRETORIO=$(cat /tmp/particao)
        mkdir -p $DIRETORIO/pgsql/12/main
        chown -R postgres:postgres $DIRETORIO/pgsql
        chmod -R 770 $DIRETORIO/pgsql
        mkdir /etc/systemd/system/postgresql-12.service.d
        echo -e "[Service]\nEnvironment=PGDATA=$DIRETORIO/pgsql/12/main" | tee -a /etc/systemd/system/postgresql-12.service.d/override.conf
        clear
        azul "Inicializando o banco de dados..."
        sleep 5
        /usr/pgsql-12/bin/postgresql-12-setup initdb
        systemctl enable --now postgresql-12
        return 0
    else
        # Caso ele não encontre a partição /data ou /dados ele disponibiliza que seja personalizado
        # o local da instalação.
        menuInstalarPostgres
        if [ $? -eq 0 ] 
        then
            /usr/pgsql-12/bin/postgresql-12-setup initdb
            systemctl enable --now postgresql-12
            return 0
        else
            return 1
        fi
    fi
}

function menuInstalarPostgres()
{
    # Esse menu é chamado durante a instalação do PostgreSQL caso não encontre a partição /dados ou /data,
    # ele possibilita que seja personalizado o diretório de criação do cluster.
    vermelho "Partição data ou dados não encontrada."
    branco "1. Instalação padrão do PostgreSQL;"
    branco "2. Instalar em /home;"
    branco "3. Personalizar um diretório na raiz;"
    branco "4. Sair."
    readBranco "Selecione uma das opções acima: "
    read OPC
    case $OPC in
        1) return 0
        ;;
        2)  mkdir -p /home/pgsql/12/main
            chown -R postgres:postgres /home/pgsql
            chmod -R 770 /home/pgsql
            mkdir /etc/systemd/system/postgresql-12.service.d
            echo -e "[Service]\nEnvironment=PGDATA=/home/pgsql/12/main" | tee -a /etc/systemd/system/postgresql-12.service.d/override.conf
            clear
            return 0
        ;;
        3)  readBranco "Digite apenas o nome do diretório na raiz sem caracteres especiais: "
            read DIRETORIO
            if [[ $DIRETORIO =~ ['!@/\#$%^&*()_+'] ]] 
            then
                vermelho "Nome inválido."
                sleep 5
                menuInstalarPostgres
            else
                DIRETORIO=/$DIRETORIO
                mkdir -p $DIRETORIO/pgsql/12/main
                chown -R postgres:postgres $DIRETORIO/pgsql
                chmod -R 770 $DIRETORIO/pgsql
                mkdir /etc/systemd/system/postgresql-12.service.d
                echo -e "[Service]\nEnvironment=PGDATA=$DIRETORIO/pgsql/12/main" | tee -a /etc/systemd/system/postgresql-12.service.d/override.conf
                clear
                return 0
            fi
        ;;
        4)  return 1
            break
        ;;
        *)  vermelho "Opção inválida."
            sleep 5
            menuInstalarPostgres
    esac
}

function tunningConfiguracaoPostgres()
{
    # Função responsável por realizar o tunning das configurações do PostgreSQL com basendo-se no hardware.
    # Informações de hardware.
    PORTA=$1
    TIPODISCO=$(cat /sys/block/sda/queue/rotational)
    CPUS=$(lscpu | grep 'CPU(s):' | head -n1 | awk '{print $2}')
    MEMORIACONVERTIDAKB=$(cat /proc/meminfo | grep MemTotal | grep -o '[0-9]*')
    # Configuração de parâmetros baseados nas recomendações da documentação.
    SHARED_BUFFERS=$(($MEMORIACONVERTIDAKB/8/4))
    CACHE_SIZE=$(($MEMORIACONVERTIDAKB/8/4*3))
    MAINTANANCE_MEM=$(($MEMORIACONVERTIDAKB/8/8))
    MAX_PARALLEL_WORKERS=$(($CPUS/2))
    # Parâmetros maleáveis de acordo com o tipo de hardware precisam da verificação abaixo para
    # que o tunning seja preciso.
    if [ $MAX_PARALLEL_WORKERS > 4 ] 
    then
        MAX_PARALLEL_WORKERS=4
    fi
    if [ $TIPODISCO -eq 1 ] 
    then
        IO=2
        PAGE_COST=4
    else
        IO=200
        PAGE_COST=1.1
    fi
    # Criação do arquivo de source.
    echo "PORTA=$PORTA" | tee -a /tmp/infotunning
    echo "TIPODISCO=$TIPODISCO" | tee -a /tmp/infotunning
    echo "CPUS=$CPUS" | tee -a /tmp/infotunning
    echo "MEMORIACONVERTIDAKB=$MEMORIACONVERTIDAKB" | tee -a /tmp/infotunning
    echo "SHARED_BUFFERS=$SHARED_BUFFERS" | tee -a /tmp/infotunning
    echo "CACHE_SIZE=$CACHE_SIZE" | tee -a /tmp/infotunning
    echo "MAINTANANCE_MEM=$MAINTANANCE_MEM" | tee -a /tmp/infotunning
    echo "MAX_PARALLEL_WORKERS=$MAX_PARALLEL_WORKERS" | tee -a /tmp/infotunning
    echo "IO=$IO" | tee -a /tmp/infotunning
    echo "PAGE_COST=$PAGE_COST" | tee -a /tmp/infotunning
    echo '"*"' > /tmp/alladdress
    clear
    # Os comandos abaixo realizam a alteração através do metacomando "ALTER SYSTEM" do PostgreSQL.
    # Eles ficam disponíveis para serem consultados no arquivo postgresql.auto.conf ou até mesmo na
    # view especial do PostgreSQL pg_settings.
    # Caso seja necessário é possível desfazer as alterações utilizando o "ALTER SYSTEM RESET ALL".
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET shared_buffers = $SHARED_BUFFERS;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET effective_cache_size = $CACHE_SIZE;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET maintenance_work_mem = $MAINTANANCE_MEM;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET max_worker_processes = $CPUS;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET max_parallel_workers_per_gather = $MAX_PARALLEL_WORKERS;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET max_parallel_workers = $CPUS;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET max_parallel_maintenance_workers = $MAX_PARALLEL_WORKERS;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET effective_io_concurrency = $IO;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET random_page_cost = $PAGE_COST;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET listen_addresses = $(cat /tmp/alladdress);"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET max_connections = 200;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET checkpoint_completion_target = 0.9;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET wal_buffers = 2048;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET default_statistics_target = 2000;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET work_mem = 10240;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET min_wal_size = 1024;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "ALTER SYSTEM SET max_wal_size = 4096;"'
    if [ $? -eq 0 ] 
    then
        return 0
    else
        return 1
    fi
    systemctl restart postgresql-12
}

function alterarHostBasedAuth()
{
    # Função responsável por identificar as redes da máquina e realizar a autorização no arquivo pg_hba.conf
    # utilizando o método md5.
    PORTA=$1
    echo "PORTA=$PORTA" | tee -a /tmp/porta
    clear
    DIRETORIODATA=$(runuser -l postgres -c 'source /tmp/porta && /usr/pgsql-12/bin/psql -p $PORTA -c "SELECT setting FROM pg_settings"' | grep pg_hba.conf)
    REDES=$(hostname -I | sed 's/ /\n/g' | grep -v ":" | wc -l | bc)
    CONTADOR=1
    if [ $REDES -gt 2 ]; then
        while [ $CONTADOR -lt $REDES ]; do
            IPADDRESS=$(hostname -I | sed 's/ /\n/g' | sed -n "$CONTADOR p")
		    echo -e "host\tall\t\tall\t\t$IPADDRESS/24\t\tmd5" >> $DIRETORIODATA
		    LAST_IP=$(tail -n1 $DIRETORIODATA | cut -d . -f 4)
		    ALTER_IP=$(echo -e "0/24\t\tmd5")
		    sed -i "s|$LAST_IP|$ALTER_IP|g" $DIRETORIODATA
		    CONTADOR=$(($CONTADOR+1))
        done
    else
	    IPADDRESS=$(hostname -I | sed 's/ /\n/g' | sed -n "$CONTADOR p")
	    echo -e "host\tall\t\tall\t\t$IPADDRESS/24\t\tmd5" >> $DIRETORIODATA
	    LAST_IP=$(tail -n1 $DIRETORIODATA | cut -d . -f 4)
	    ALTER_IP=$(echo -e "0/24\t\tmd5")
	    sed -i "s|$LAST_IP|$ALTER_IP|g" $DIRETORIODATA
    fi
}

function instalarMonitoramentoPostgres()
{
    # Instalação do pgBadger e da ferramenta para envio de e-mail, uma ferramenta de monitoramento pontual.
    # A instalação dessa ferramenta é opcional, por conta disso propositalmente o arquivo .variables_badger
    # deve ser preenchido manualmente.
    mkdir /pg_badger
    $GERENCIADOR update -y
    $GERENCIADOR install -y git
    curl https://storage.googleapis.com/linux-pdv/vrserver/centos/bin/pgbadger -o /pg_badger/pgbadger
    if [ $? -eq 0 ] 
    then
        return 0
    else
        return 1
    fi
    chown -R root:postgres /pg_badger
    chmod -R 770 /pg_badger
    git clone https://github.com/rbsilmann/pg-badger.git /pg_badger
}

function configurarSamba()
{
    # Função responsável por realizar a criação do compartilhamento público e restringir o acesso
    # a pasta de backup somente para o usuário criado.
    PADRAOBACKUP=B4ckup@Software
    groupadd vrsamba
    useradd vrsoftware
    usermod -aG vrsamba vrsoftware
    usermod -p $(openssl passwd -1 $PADRAOBACKUP) vrsoftware
    mkdir -p /vr/backup
    chgrp vrsamba /vr/backup
    chmod 777 /vr
    chmod 770 /vr/backup
    chcon -t samba_share_t -R /vr
    mv /etc/samba/smb.conf /etc/samba/smb.conf.backup
    curl https://storage.googleapis.com/linux-pdv/vrserver/centos/files/smb.conf -o /etc/samba/smb.conf
    if [ $? -eq 0 ] 
    then
        return 0
    else
        return 1
    fi
}

function configurarFirewall()
{
    # Configuração de firewall alterando o perfil para ambiente corporativo e adicionando os serviços: samba
    # e do PostgreSQL nas exceções
    ciano "Configurando zona padrão: "
    firewall-cmd --set-default-zone=work
    sleep 2
    ciano "Configurando serviço samba: "
    firewall-cmd --add-service=samba --permanent
    sleep 2
    ciano "Configurando serviço PostgreSQL: "
    firewall-cmd --add-service=postgresql --permanent
    sleep 2
    ciano "Recarregando firewalld: "
    firewall-cmd --reload
    sleep 2
    ciano "Habilitando inicialização automática SMB e NMB: "
    sleep 2
    systemctl enable smb nmb firewalld
    systemctl restart smb nmb firewalld
    if [ $? -eq 0 ] 
    then
        return 0
    else
        return 1
    fi
}

function alterarPorta()
{
    # Essa função recebe um parâmetro para realizar a troca da porta padrão, ela atua somente quando o arquivo postgresql.conf
    # não sofreu nenhuma alteração.
    PORTA=$1
    sed -i "/#port/s/5432/$PORTA/g" $DIRETORIO/pgsql/12/main/postgresql.conf
    sed -i "/#port/s/#port/port/g" $DIRETORIO/pgsql/12/main/postgresql.conf
    if [ $? -eq 0 ] 
    then
        return 0
    else
        return 1
    fi
    systemctl restart postgresql-12
}

function criarRoles()
{
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE DATABASE vr;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE ROLE pgsql LOGIN SUPERUSER INHERIT CREATEDB CREATEROLE REPLICATION;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER arcos;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER arquitetura;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER desenvolvimento;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER implantacao;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER mercafacil;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER mixfiscal;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER pagpouco;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER projeto;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER suporte;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER vr;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER yandeh;"'
    runuser -l postgres -c 'source /tmp/infotunning && /usr/pgsql-12/bin/psql -p $PORTA -c "CREATE USER smarket;"'
    if [ $? -eq 0 ] 
    then
        return 0
    else
        return 1
    fi
}

function instalacaoPadrao()
{
    # A instalação padrão gera um relatório de sucessos e falhas em /tmp/relatorio_instalacao.txt
    # 01 - Boas-vindas.
    amarelo "Olá, bem vindo ao assistente de configuração!"
    sleep 5
    branco "O assistente se encarregará de auxiliar nas seguintes configurações:"
    branco "- Instalação/configuração do SGBD PostgreSQL e pgBadger"
    branco "- Instalação/configuração do samba"
    branco "- Instalação de utilitários básicos"
    branco "- Liberações de firewall"
    sleep 10
    # 01
    #
    # 02 - Validações iniciais.
    clear
    azul "Inicialmente vamos validar se há acesso com a internet, beleza?"
    sleep 2
    testeConexao
    if [ $? -eq 0 ] 
    then
        verde "Tudo certo com a sua conexão! =D"
        echo "Conexão com a internet: OK" > /tmp/relatorio_instalacao.txt
    else
        echo "Conexão com a internet: FALHOU" > /tmp/relatorio_instalacao.txt
    fi
    azul "Agora validaremos a permissão do usuário conectado."
    sleep 5
    verificarUsuario
    if [ $? -eq 0 ]
    then
        verde "Tudo certo também com o seu usuário! =)"
        echo "Validação de usuário: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Validação de usuário: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
        exit
    fi
    # 02
    #
    # 03 - Início da instalação
    configurarHostname
    if [ $? -eq 0 ]
    then
        verde "Hostname configurado com sucesso!"
        echo "Configuração de hostname: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        vermelho "Falha ao configurar o novo hostname. Caracteres especiais identificados."
        echo "Configuração de hostname: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    clear
    azul "Iniciando a instalação dos componentes necessários."
    sleep 5
    gerenciadorPacotes
    if [ $? -eq 0 ]
    then
        verde "Sistema operacional compatível com o script!"
        echo "Sistema compatível: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Sistema compatível: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
        exit
    fi
    instalarUtilitarios
    if [ $? -eq 0 ]
    then
        echo "Instalação de pré-requisitos: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Instalação de pré-requisitos: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    # 03
    #
    # 04 - Início das instalações/configurações do PostgreSQL e samba.
    clear
    azul "Iniciando a instalação do PostgreSQL 12..."
    sleep 5
    instalarPostgres
    if [ $? -eq 0 ]
    then
        verde "Instalação do PostgreSQL realizada corretamente."
        echo "Instalação do PostgreSQL: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
        clear
        azul "Aguarde enquanto ajustamos o tunning."
        sleep 5
        tunningConfiguracaoPostgres 5432
        if [ $? -eq 0 ]
        then
            echo "Tunning do PostgreSQL: OK" >> /tmp/relatorio_instalacao.txt
        else
            echo "Tunning do PostgreSQL: FALHOU" >> /tmp/relatorio_instalacao.txt
        fi
        clear
        azul "Criando database inicial e roles..."
        criarRoles
        if [ $? -eq 0 ]
        then
            echo "Criação de database e roles: OK" >> /tmp/relatorio_instalacao.txt
        else
            echo "Criação de database e roles: FALHOU" >> /tmp/relatorio_instalacao.txt
        fi
        sleep 5
        clear
    else
        echo "Instalação do PostgreSQL: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    configurarSamba
    if [ $? -eq 0 ]
    then
        echo "Configuração do SAMBA: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Configuração do SAMBA: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    # 04
    #
    # 05 - Ajustes finais.
    instalarMonitoramentoPostgres
    if [ $? -eq 0 ]
    then
        echo "Instalação do pgBadger: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Instalação do pgBadger: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    clear
    configurarFirewall
    if [ $? -eq 0 ]
    then
        echo "Configuração de firewall: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Configuração de firewall: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    alterarHostBasedAuth 5432
    if [ $? -eq 0 ]
    then
        echo "Configuração do pg_hba.conf: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Configuração do pg_hba.conf: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    alterarPorta 8745
    if [ $? -eq 0 ]
    then
        echo "Configuração da porta: OK" >> /tmp/relatorio_instalacao.txt
        sleep 5
    else
        echo "Configuração do porta: FALHOU" >> /tmp/relatorio_instalacao.txt
        sleep 5
    fi
    # 05
}

function menuConfiguracao()
{
    clear
    preto "MENU"
    azul "| 1. Instalação completa (PostgreSQL, Tunning, adição de liberações HBA, Samba);"
    ciano "| 2. PostgreSQL;"
    amarelo "| 3. Tunning;"
    branco "| 4. Liberações HBA;"
    purple "| 5. Instalação do Samba;"
    vermelho "| 6. Sair."
    readBranco "Selecione a opção desejada: "
    read MENU
    case $MENU in
        1)  clear
            instalacaoPadrao
            exit
        ;;
        2)  clear
            verificarUsuario
            if [ $? -ne 0 ] 
            then
                vermelho "É necessário que você execute essa função como root."
                sleep 5
                exit
            fi
            gerenciadorPacotes
            if [ $? -eq 0 ] 
            then
                clear
                instalarPostgres
                clear
                verde "PostgreSQL instalado com sucesso! =)"
                sleep 5
            else
                clear
                vermelho "Falha ao instalar o PostgreSQL, não foi possível definir o gerenciador de pacotes."
                sleep 5
            fi
            menuConfiguracao
        ;;
        3)  clear
            verificarUsuario
            if [ $? -ne 0 ] 
            then
                vermelho "É necessário que você execute essa função como root."
                sleep 5
                exit
            fi
            readBranco "Informe a porta do banco de dados: "
            read PORTA
            tunningConfiguracaoPostgres $PORTA
            if [ $? -eq 0 ] 
            then
                verde "Tunning realizado com sucesso."
                sleep 5
            else
                vermelho "Tunning falhou, verifique a porta informada! Porta informada: $PORTA"
                sleep 5
            fi
            menuConfiguracao
        ;;
        4)  clear
            verificarUsuario
            if [ $? -ne 0 ] 
            then
                vermelho "É necessário que você execute essa função como root."
                sleep 5
                exit
            fi
            readBranco "Informe a porta do banco de dados: "
            read PORTA
            alterarHostBasedAuth $PORTA
            if [ $? -ne 0 ] 
            then
                vermelho "Não foi possível adicionar informações no HBA, verifique a interface de rede."
                sleep 5
                exit
            else
                verde "HBA configurado com sucesso, reinicie o serviço do PostgreSQL."
                sleep 5
            fi
            menuConfiguracao
        ;;
        5)  clear
            verificarUsuario
            if [ $? -ne 0 ] 
            then
                vermelho "É necessário que você execute essa função como root."
                sleep 5
                exit
            fi
            gerenciadorPacotes
            if [ $? -eq 0 ] 
            then
                clear
                instalarUtilitarios
                if [ $? -eq 0 ] 
                then
                    configurarSamba
                    configurarFirewall
                fi
            else
                clear
                vermelho "Falha ao instalar o samba, não foi possível definir o gerenciador de pacotes."
                sleep 5
            fi
            menuConfiguracao
        ;;
        6)  echo ""
            vermelho "Saindo do agente de configuração, até logo! =)"
            sleep 5
            exit
        ;;
        *)  clear
            vermelho "Opção inválida!!!"
            sleep 15
            menuConfiguracao
    esac
}

menuConfiguracao