## Repositório público de Shell Scripts

> #### Script: install-server.sh
> Este script é responsável por realizar a instalação das seguintes aplicações:
> - PostgreSQL 12 (tunning e liberações no pg_hba automatizados)
> - pgBadger (log analyzer para postgresql)
> - Samba server com compartilhamento público e compartilhamento com senha
> - Utilitários básicos: vim, curl, mlocate, sysstat, perl e bc
> - Ele também pode realizar funções isoladamente como: ajuste de tunning, hba e instalação padrão do PostgreSQL 12

> #### Script: script_dump.sh
> Este script é uma sugestão de script via binário pg_dump e pode ser utilizado via agendamento crontab. Ele também remove arquivos mais antigos que sete dias.