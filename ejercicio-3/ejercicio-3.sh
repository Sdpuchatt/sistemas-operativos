#!/usr/bin/env bash

# Archivos de base de datos SQLite3, reportes y logs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "data.sq3" ]]; then
    DB_FILE="data.sq3"
elif [[ -f "$SCRIPT_DIR/data.sq3" ]]; then
    DB_FILE="$SCRIPT_DIR/data.sq3"
else
    DB_FILE="data.sq3"
fi

SYSTEM_LOG="system.log"
ERROR_LOG="error.log"
REPORTE_HTML="productos.html"

# Variables de sesión para registro en logs
SESSION_USER_ID="-"
SESSION_USERNAME="-"

# Constantes de menú inicial
declare -r -i OPCION_INICIO_LOGIN=1
declare -r -i OPCION_INICIO_REGISTRO=2
declare -r -i OPCION_INICIO_SALIR=3

# Constantes de menú principal de acciones
declare -r -i OPCION_ALTA=1
declare -r -i OPCION_BAJA=2
declare -r -i OPCION_MODIFICAR=3
declare -r -i OPCION_MOSTRAR=4
declare -r -i OPCION_REPORTE=5
declare -r -i OPCION_SALIR=6

# Registro en log de sistema (TSV: fecha/hora, ID usuario, nombre usuario, acción)
log_system() {
    declare uid="${1:-${SESSION_USER_ID:--}}"
    declare uname="${2:-${SESSION_USERNAME:--}}"
    declare accion="$3"
    declare fecha_hora
    fecha_hora=$(date '+%Y-%m-%d %H:%M:%S')

    printf "%s\t%s\t%s\t%s\n" "$fecha_hora" "$uid" "$uname" "$accion" >> "$SYSTEM_LOG"
}

# Registro en log de errores
log_error() {
    declare mensaje="$1"
    declare uid="${SESSION_USER_ID:--}"
    declare uname="${SESSION_USERNAME:--}"
    declare fecha_hora
    fecha_hora=$(date '+%Y-%m-%d %H:%M:%S')

    printf "%s\t%s\t%s\t%s\n" "$fecha_hora" "$uid" "$uname" "$mensaje" >> "$ERROR_LOG"
}

# Verificar disponibilidad de SQLite3 en el sistema
verificar_dependencias() {
    if ! command -v sqlite3 &>/dev/null; then
        printf "Error: sqlite3 no se encuentra instalado en el sistema.\n" >&2
        printf "Por favor, instale sqlite3 ejecutando: sudo apt install sqlite3\n" >&2
        log_error "sqlite3 no esta instalado en el sistema"
        return 1
    fi
    return 0
}

# Inicialización de la base de datos data.sq3 y sus tablas
inicializar_db() {
    declare db_existia=1
    if [[ ! -f "$DB_FILE" ]]; then
        db_existia=0
    fi

    sqlite3 "$DB_FILE" << 'EOF'
CREATE TABLE IF NOT EXISTS usuarios (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    usuario TEXT UNIQUE NOT NULL,
    clave TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS productos (
    id TEXT PRIMARY KEY,
    nombre TEXT NOT NULL,
    precio NUMERIC NOT NULL
);
EOF

    declare status_sql=$?
    if [[ $status_sql -ne 0 ]]; then
        log_error "Fallo al inicializar la base de datos '$DB_FILE'"
        return 1
    fi

    if [[ $db_existia -eq 0 ]]; then
        log_system "-" "SYSTEM" "Base de datos '$DB_FILE' creada e inicializada exitosamente"
    fi

    return 0
}

bienvenida() {
    printf "Bienvenido/a al sistema\n\n"
}

# Autenticación de usuarios contra tabla SQL 'usuarios' usando sha256
autenticar() {
    declare -i intentos=0
    declare usuario=""
    declare clave=""

    declare total_usuarios
    total_usuarios=$(sqlite3 "$DB_FILE" "SELECT count(*) FROM usuarios;" 2>/dev/null)

    if [[ -z "$total_usuarios" || "$total_usuarios" -eq 0 ]]; then
        printf "No existen usuarios registrados. Por favor registre un usuario primero.\n\n"
        log_error "Intento de inicio de sesion sin usuarios registrados"
        return 2
    fi

    while (( intentos < 3 )); do
        read -rp "Ingrese usuario: " usuario
        read -rp "Ingrese clave: " clave

        declare raw_hash raw_hash_n
        raw_hash=$(echo "$clave" | sha256sum)
        declare hash_ingresado=${raw_hash:0:64}
        raw_hash_n=$(echo -n "$clave" | sha256sum)
        declare hash_ingresado_n=${raw_hash_n:0:64}

        declare usuario_sql="${usuario//\'/\'\'}"
        declare row
        row=$(sqlite3 -separator $'\t' "$DB_FILE" "SELECT id, usuario, clave FROM usuarios WHERE usuario = '$usuario_sql' LIMIT 1;" 2>/dev/null)

        if [[ -n "$row" ]]; then
            declare u_id u_name u_hash
            u_id=$(printf "%s" "$row" | cut -f1)
            u_name=$(printf "%s" "$row" | cut -f2)
            u_hash=$(printf "%s" "$row" | cut -f3)

            u_hash="${u_hash%$'\r'}"

            if [[ "$u_hash" == "$hash_ingresado" || "$u_hash" == "$hash_ingresado_n" ]]; then
                SESSION_USER_ID="$u_id"
                SESSION_USERNAME="$u_name"
                printf "Acceso concedido.\n"
                log_system "$SESSION_USER_ID" "$SESSION_USERNAME" "Inicio de sesion exitoso"
                return 0
            fi
        fi

        intentos=$((intentos + 1))
        printf "Credenciales incorrectas (%d/3 intentos).\n" "$intentos"
        log_error "Credenciales incorrectas para usuario: '$usuario' (intento $intentos/3)"
    done

    log_error "Acceso denegado: superado limite de 3 intentos para usuario: '$usuario'"
    return 1
}

# Registro de nuevos usuarios en base de datos SQLite con clave cifrada sha256
registrar_usuario() {
    declare usuario=""
    declare clave=""

    read -rp "Ingrese nombre de usuario: " usuario

    if [[ -z "$usuario" ]]; then
        printf "Error: El nombre de usuario no puede estar vacio.\n"
        log_error "Registro fallido: el nombre de usuario no puede estar vacio"
        return 1
    fi

    # Validar que no se agregue un usuario ya existente
    declare usuario_sql="${usuario//\'/\'\'}"
    declare existe
    existe=$(sqlite3 "$DB_FILE" "SELECT count(*) FROM usuarios WHERE usuario = '$usuario_sql';" 2>/dev/null)

    if [[ "$existe" -gt 0 ]]; then
        printf "Error: El usuario ya existe.\n"
        log_error "Registro fallido: el usuario '$usuario' ya existe"
        return 1
    fi

    read -rp "Ingrese contraseña: " clave

    if [[ -z "$clave" ]]; then
        printf "Error: La contraseña no puede estar vacia.\n"
        log_error "Registro fallido para '$usuario': la contraseña no puede estar vacia"
        return 1
    fi

    # Cifrado sha256 usando buffer y extracción de subcadena
    declare raw_hash
    raw_hash=$(echo "$clave" | sha256sum)
    declare hash_cifrado=${raw_hash:0:64}
    declare clave_sql="${hash_cifrado//\'/\'\'}"

    sqlite3 "$DB_FILE" "INSERT INTO usuarios (usuario, clave) VALUES ('$usuario_sql', '$clave_sql');" 2>/dev/null
    declare status_sql=$?

    if [[ $status_sql -ne 0 ]]; then
        printf "Error al guardar el usuario en la base de datos.\n"
        log_error "Error al ejecutar INSERT en tabla usuarios para usuario '$usuario'"
        return 1
    fi

    declare nuevo_id
    nuevo_id=$(sqlite3 "$DB_FILE" "SELECT id FROM usuarios WHERE usuario = '$usuario_sql' LIMIT 1;" 2>/dev/null)
    log_system "$nuevo_id" "$usuario" "Registro de nuevo usuario"

    printf "Usuario '%s' registrado exitosamente.\n" "$usuario"
    return 0
}

# Comprobar existencia de producto por ID en SQLite
producto_existe() {
    declare id_buscar="$1"
    declare id_sql="${id_buscar//\'/\'\'}"
    declare count
    count=$(sqlite3 "$DB_FILE" "SELECT count(*) FROM productos WHERE id = '$id_sql';" 2>/dev/null)

    if [[ "$count" -gt 0 ]]; then
        return 0
    fi
    return 1
}

# Alta de producto en base de datos SQLite
alta() {
    declare id="$1"
    declare nombre="$2"
    declare precio="$3"

    if [[ -z "$id" || -z "$nombre" || -z "$precio" ]]; then
        printf "Error: Todos los campos (ID, Nombre, Precio) son obligatorios.\n"
        log_error "Alta fallida: campos obligatorios incompletos (ID='$id', Nombre='$nombre', Precio='$precio')"
        return 1
    fi

    if producto_existe "$id"; then
        printf "Error: El producto con ID '%s' ya existe.\n" "$id"
        log_error "Alta fallida: el producto con ID '$id' ya existe"
        return 1
    fi

    declare id_sql="${id//\'/\'\'}"
    declare nombre_sql="${nombre//\'/\'\'}"
    declare precio_sql="${precio//\'/\'\'}"

    sqlite3 "$DB_FILE" "INSERT INTO productos (id, nombre, precio) VALUES ('$id_sql', '$nombre_sql', '$precio_sql');" 2>/dev/null
    declare status_sql=$?

    if [[ $status_sql -ne 0 ]]; then
        printf "Error al guardar el producto en la base de datos.\n"
        log_error "Error al ejecutar INSERT en tabla productos para ID '$id'"
        return 1
    fi

    log_system "$SESSION_USER_ID" "$SESSION_USERNAME" "Alta producto (ID: $id, Nombre: $nombre, Precio: $precio)"
    printf "Producto %s guardado correctamente.\n" "$id"
    return 0
}

# Baja de producto en base de datos SQLite
baja() {
    declare id="$1"

    if [[ -z "$id" ]]; then
        printf "Error: Debe ingresar un ID.\n"
        log_error "Baja fallida: ID de producto no ingresado"
        return 1
    fi

    if ! producto_existe "$id"; then
        printf "El producto no existe.\n"
        log_error "Baja fallida: el producto con ID '$id' no existe"
        return 1
    fi

    declare id_sql="${id//\'/\'\'}"
    sqlite3 "$DB_FILE" "DELETE FROM productos WHERE id = '$id_sql';" 2>/dev/null
    declare status_sql=$?

    if [[ $status_sql -ne 0 ]]; then
        printf "Error al eliminar el producto de la base de datos.\n"
        log_error "Error al ejecutar DELETE en tabla productos para ID '$id'"
        return 1
    fi

    log_system "$SESSION_USER_ID" "$SESSION_USERNAME" "Baja producto (ID: $id)"
    printf "Producto %s eliminado.\n" "$id"
    return 0
}

# Modificar producto en base de datos SQLite
modificar() {
    declare id="$1"

    if [[ -z "$id" ]]; then
        printf "Error: Debe ingresar un ID.\n"
        log_error "Modificacion fallida: ID de producto no ingresado"
        return 1
    fi

    if ! producto_existe "$id"; then
        printf "El producto no existe.\n"
        log_error "Modificacion fallida: el producto con ID '$id' no existe"
        return 1
    fi

    declare id_sql="${id//\'/\'\'}"
    declare row
    row=$(sqlite3 -separator $'\t' "$DB_FILE" "SELECT nombre, precio FROM productos WHERE id = '$id_sql' LIMIT 1;" 2>/dev/null)

    declare actual_nombre actual_precio
    actual_nombre=$(printf "%s" "$row" | cut -f1)
    actual_precio=$(printf "%s" "$row" | cut -f2)

    declare nuevo_nombre=""
    declare nuevo_precio=""
    read -rp "Ingrese nuevo Nombre: " nuevo_nombre
    read -rp "Ingrese nuevo Precio: " nuevo_precio

    if [[ -z "$nuevo_nombre" ]]; then
        nuevo_nombre="$actual_nombre"
    fi
    if [[ -z "$nuevo_precio" ]]; then
        nuevo_precio="$actual_precio"
    fi

    declare nuevo_nombre_sql="${nuevo_nombre//\'/\'\'}"
    declare nuevo_precio_sql="${nuevo_precio//\'/\'\'}"

    sqlite3 "$DB_FILE" "UPDATE productos SET nombre = '$nuevo_nombre_sql', precio = '$nuevo_precio_sql' WHERE id = '$id_sql';" 2>/dev/null
    declare status_sql=$?

    if [[ $status_sql -ne 0 ]]; then
        printf "Error al modificar el producto en la base de datos.\n"
        log_error "Error al ejecutar UPDATE en tabla productos para ID '$id'"
        return 1
    fi

    log_system "$SESSION_USER_ID" "$SESSION_USERNAME" "Modificar producto (ID: $id, Nombre: $nuevo_nombre, Precio: $nuevo_precio)"
    printf "Producto %s modificado con precio $%s.\n" "$id" "$nuevo_precio"
    return 0
}

# Mostrar inventario listando los productos desde la base de datos SQLite
mostrar() {
    declare total_prods
    total_prods=$(sqlite3 "$DB_FILE" "SELECT count(*) FROM productos;" 2>/dev/null)

    if [[ -z "$total_prods" || "$total_prods" -eq 0 ]]; then
        printf "\nLISTADO:\n"
        printf "No hay productos registrados.\n"
        log_system "$SESSION_USER_ID" "$SESSION_USERNAME" "Mostrar inventario (vacio)"
        return 0
    fi

    printf "\nLISTADO:\n"
    sqlite3 -separator $'\t' "$DB_FILE" "SELECT id, nombre, precio FROM productos;" 2>/dev/null | while IFS=$'\t' read -r col1 col2 col3; do
        col3="${col3%$'\r'}"
        col2="${col2%$'\r'}"
        col1="${col1%$'\r'}"
        [[ -z "$col1" ]] && continue
        printf "ID %s : %s - $%s\n" "$col1" "$col2" "$col3"
    done

    log_system "$SESSION_USER_ID" "$SESSION_USERNAME" "Mostrar inventario"
    return 0
}

# Generar archivo de reporte productos.html en formato de tabla
generar_reporte() {
    cat << 'EOF' > "$REPORTE_HTML"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Reporte de Productos</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 30px;
            background-color: #f8f9fa;
        }
        h1 {
            color: #333333;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            max-width: 650px;
            background-color: #ffffff;
            border: 1px solid #dee2e6;
        }
        th, td {
            border: 1px solid #dee2e6;
            padding: 10px 14px;
            text-align: left;
        }
        th {
            background-color: #007bff;
            color: #ffffff;
        }
        tr:nth-child(even) {
            background-color: #f2f2f2;
        }
    </style>
</head>
<body>
    <h1>Reporte de Productos</h1>
    <table>
        <thead>
            <tr>
                <th>ID</th>
                <th>Nombre</th>
                <th>Precio</th>
            </tr>
        </thead>
        <tbody>
EOF

    sqlite3 -separator $'\t' "$DB_FILE" "SELECT id, nombre, precio FROM productos;" 2>/dev/null | while IFS=$'\t' read -r col1 col2 col3; do
        col3="${col3%$'\r'}"
        col2="${col2%$'\r'}"
        col1="${col1%$'\r'}"
        [[ -z "$col1" ]] && continue
        printf "            <tr><td>%s</td><td>%s</td><td>$%s</td></tr>\n" "$col1" "$col2" "$col3" >> "$REPORTE_HTML"
    done

    cat << 'EOF' >> "$REPORTE_HTML"
        </tbody>
    </table>
</body>
</html>
EOF

    log_system "$SESSION_USER_ID" "$SESSION_USERNAME" "Generar reporte HTML: $REPORTE_HTML"
    printf "Reporte '%s' generado exitosamente.\n" "$REPORTE_HTML"
    return 0
}

main() {
    if ! verificar_dependencias; then
        return 1
    fi

    if ! inicializar_db; then
        return 1
    fi

    bienvenida

    declare -i sesion_iniciada=0
    declare opcion_inicio=""

    while (( sesion_iniciada == 0 )); do
        printf "1. Iniciar sesion\n"
        printf "2. Registrar usuario\n"
        printf "3. Salir\n"
        read -rp "Opcion: " opcion_inicio

        case $opcion_inicio in
            $OPCION_INICIO_LOGIN)
                autenticar
                declare estado_auth=$?
                if (( estado_auth == 0 )); then
                    sesion_iniciada=1
                elif (( estado_auth == 1 )); then
                    printf "\nAcceso denegado.\n"
                    return 1
                fi
                # Si estado_auth == 2 (no hay usuarios registrados), vuelve al menú
                ;;
            $OPCION_INICIO_REGISTRO)
                registrar_usuario
                printf "\n"
                ;;
            $OPCION_INICIO_SALIR)
                log_system "-" "-" "Salir del menu inicial"
                printf "\nSaliendo del programa...\n"
                return 0
                ;;
            *)
                log_error "Opcion invalida en menu inicial: '$opcion_inicio'"
                printf "\nOpcion invalida.\n\n"
                ;;
        esac
    done

    declare opcion=0

    while [[ "$opcion" != "$OPCION_SALIR" ]]; do
        printf "\nACCIONES:\n"
        printf "1. Alta producto\n"
        printf "2. Baja producto\n"
        printf "3. Modificar producto\n"
        printf "4. Mostrar inventario\n"
        printf "5. Generar reporte HTML\n"
        printf "6. Salir\n"
        read -rp "Opcion: " opcion

        case $opcion in
            $OPCION_ALTA)
                declare id="" nombre="" precio=""
                read -rp "Ingrese ID: " id
                read -rp "Ingrese Nombre: " nombre
                read -rp "Ingrese Precio: " precio
                alta "$id" "$nombre" "$precio"
                ;;
            $OPCION_BAJA)
                declare id=""
                read -rp "Ingrese ID a eliminar: " id
                baja "$id"
                ;;
            $OPCION_MODIFICAR)
                declare id=""
                read -rp "Ingrese ID a modificar: " id
                modificar "$id"
                ;;
            $OPCION_MOSTRAR)
                mostrar
                ;;
            $OPCION_REPORTE)
                generar_reporte
                ;;
            $OPCION_SALIR)
                log_system "$SESSION_USER_ID" "$SESSION_USERNAME" "Salir del sistema"
                printf "\nSaliendo del programa...\n"
                ;;
            *)
                log_error "Opcion invalida en menu principal: '$opcion'"
                printf "\nOpcion invalida.\n"
                ;;
        esac
    done

    return 0
}

main
