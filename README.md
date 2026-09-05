# Templo Roblox Panel

Panel web para ejecutar y administrar **4 clientes Roblox simultáneos en Linux** usando Cordial, con perfiles independientes `rb1`–`rb4`, visores noVNC integrados y recuperación automática.

## Estado de esta versión

Validado en Ubuntu 24.04 x86_64 con 4 clientes simultáneos. Cada instancia usa:

- Cordial + Roblox Android x86_64 oficial.
- Perfil persistente independiente (`rb1`–`rb4`).
- Display virtual dedicado (`:201`–`:204`).
- Resolución predeterminada `960x600`.
- noVNC en `6091`–`6094`.
- Supervisor systemd con autorrecuperación.
- Límite predeterminado de 60% de un núcleo por cliente.

El panel corre en el puerto `8090` y permite iniciar, ver y cerrar cada cliente, administrar cuentas y usar correo temporal Mail.tm.

> **Importante:** Cordial es un cliente de terceros y no está aprobado por Roblox. Puede existir riesgo de sanción de cuenta. Este proyecto no modifica Roblox, no incluye ejecutores, hooks, bypasses ni el APK de Roblox.

## Requisitos

- Ubuntu 24.04 LTS x86_64.
- 6 GB RAM mínimo; 8 GB o más recomendado para 4 clientes.
- Aproximadamente 3 GB libres como mínimo.
- Usuario normal con acceso a `sudo` durante la instalación.
- Conexión a Internet durante la instalación y la descarga inicial de Roblox.

No ejecutes el instalador directamente como `root`; ejecútalo desde tu usuario normal.
## Instalación

```bash
git clone --branch cordial-linux-panel --single-branch https://github.com/MMMDbot/RobloxAccountManager.git templo-roblox-panel
cd templo-roblox-panel
./install.sh
```

La rama `cordial-linux-panel` contiene únicamente la distribución Linux del panel; la rama `main` del repositorio mantiene el proyecto original.

El instalador es idempotente: puede volver a ejecutarse para reparar o actualizar dependencias sin borrar `panel.db` ni los perfiles Cordial.

Durante la instalación se realizan comprobaciones de arquitectura, versión de Ubuntu, paquetes del sistema, Cordial, `cordial-run --profile`, Python, systemd y puertos del panel.

### Primera instalación de Roblox

Cordial **no distribuye el APK de Roblox dentro de este repositorio**. Si el motor todavía no existe, el panel mostrará **Preparación inicial de Roblox**.

1. Pulsa **Preparar**.
2. Abre **Ver preparación**.
3. En Cordial pulsa **Download Roblox**.
4. Cordial descarga el Android x86_64 y comprueba la firma de Roblox.
5. Los supervisores detectan el motor y arrancan `rb1`–`rb4` automáticamente.

También puedes iniciar esa pantalla desde terminal:

```bash
templo setup
```

El visor de preparación usa el puerto `6090`.
## Uso

```bash
templo status
templo start 1
templo stop 1
templo restart 1
templo logs 1
templo doctor
```

Abre el panel en:

```text
http://IP_DEL_EQUIPO:8090
```

Los visores de Roblox usan `6091`, `6092`, `6093` y `6094`. El VNC interno está restringido a localhost en `5911`–`5914`.

### Seguridad de las sesiones

El panel **no guarda las contraseñas de Roblox**. Los campos de usuario y contraseña del visor solo escriben en el cliente abierto.

Cordial guarda la sesión de cada perfil en su directorio privado con permisos `0600`. No subas nunca esos directorios, cookies o archivos de identidad a GitHub.

El panel y los puertos noVNC no incluyen autenticación propia. Úsalos únicamente en una red confiable, VPN/Tailscale o detrás de un reverse proxy autenticado. No expongas `8090` ni `6090`–`6094` directamente a Internet.

## Diagnóstico

```bash
templo doctor
```

El diagnóstico revisa dependencias, Cordial, motor Roblox, panel HTTP, cuatro motores, cuatro visores, RAM y espacio libre.
## Actualización y reparación

Si la instalación se hizo desde un clon Git con `origin` configurado:

```bash
templo update
```

La actualización descarga una copia limpia del repositorio y vuelve a ejecutar el instalador conservando la base de datos y los perfiles de Roblox.

Para reparar una instalación también puedes volver a ejecutar `./install.sh` desde un clon actualizado.

## Desinstalación

```bash
./uninstall.sh
```

Por defecto se conserva un backup de `panel.db` y **no** se eliminan los perfiles/login de Cordial.

Para eliminar también los perfiles `rb1`–`rb4` y Cordial:

```bash
./uninstall.sh --purge-data
```

## Configuración

La configuración instalada vive en:

```text
~/.config/templo-roblox-panel/env
```

Puedes cambiar resolución, límite de CPU, puerto del panel y bases de puertos. Después ejecuta `systemctl --user restart templo-panel.service templo-rb@{1..4}.service`.

## Qué NO se incluye en Git

`panel.db`, runtime, logs, PID, perfiles Cordial, cookies, identidad de Roblox, APKs, entornos virtuales y archivos `.env` están excluidos deliberadamente.
