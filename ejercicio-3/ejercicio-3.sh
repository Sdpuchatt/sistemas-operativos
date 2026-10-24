#!/usr/bin/env bash


DB_FILE="data.sq3"
LOG_SYSTEM="system.log"
LOG_ERROR="error.log"
FILE_REPORTE="productos.html"


SESSION_ID="-"
SESSION_USER="-"


log_system() {
    local accion="$1"
    local fecha_hora=$(date '+%Y-%m-%d %H:%M:%S')
    printf "%s\t%s\t%s\t%s\n" "$fecha_hora" "$SESSION_ID" "$SESSION_USER" "$accion" >> "$LOG_SYSTEM"
}

log_error() {
    local mensaje="$1"
    local fecha_hora=$(date '+%Y-%m-%d %H:%M:%S')
    printf "%s\t%s\t%s\t%s\n" "$fecha_hora" "$SESSION_ID" "$SESSION_USER" "$mensaje" >> "$LOG_ERROR"
}


inicializar_db() {

    if ! command -v sqlite3 &>/dev/null; then
        echo "Error: sqlite3 no está instalado. Ejecute: sudo apt install sqlite3"
        exit 1
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
}

cifrar_clave() {
    local clave="$1"
    local raw=$(echo "$clave" | sha256sum)
    echo "${raw:0:64}"
}

registrar_usuario() {
    local user="" clave=""
    read -rp "Ingrese nombre de usuario: " user

    if [[ -z "$user" ]]; then
        echo "Error: El usuario no puede estar vacío."
        log_error "Registro fallido: usuario vacío"
        return
    fi

    local existe=$(sqlite3 "$DB_FILE" "SELECT count(*) FROM usuarios WHERE usuario='$user';")
    if [[ "$existe" -gt 0 ]]; then
        echo "Error: El usuario '$user' ya existe."
        log_error "Registro fallido: usuario '$user' ya existe"
        return
    fi

    read -rp "Ingrese contraseña: " clave
    if [[ -z "$clave" ]]; then
        echo "Error: La contraseña no puede estar vacía."
        log_error "Registro fallido: contraseña vacía para usuario '$user'"
        return
    fi

    local hash=$(cifrar_clave "$clave")
    sqlite3 "$DB_FILE" "INSERT INTO usuarios (usuario, clave) VALUES ('$user', '$hash');"

    echo "Usuario '$user' registrado con éxito."
    log_system "Registro de nuevo usuario: $user"
}

autenticar() {
    local total=$(sqlite3 "$DB_FILE" "SELECT count(*) FROM usuarios;")
    if [[ "$total" -eq 0 ]]; then
        echo "No hay usuarios registrados. Por favor registre un usuario primero."
        log_error "Intento de inicio de sesión sin usuarios en la base de datos"
        return 1
    fi

    local intentos=0 user="" clave=""
    while (( intentos < 3 )); do
        read -rp "Usuario: " user
        read -rp "Contraseña: " clave

        local hash_ingresado=$(cifrar_clave "$clave")
        local fila=$(sqlite3 -separator '|' "$DB_FILE" "SELECT id, usuario FROM usuarios WHERE usuario='$user' AND clave='$hash_ingresado' LIMIT 1;")

        if [[ -n "$fila" ]]; then
            SESSION_ID=$(echo "$fila" | cut -d'|' -f1)
            SESSION_USER=$(echo "$fila" | cut -d'|' -f2)

            echo "Acceso concedido. Bienvenido/a $SESSION_USER!"
            log_system "Inicio de sesión exitoso"
            return 0
        fi

        intentos=$((intentos + 1))
        echo "Credenciales incorrectas ($intentos/3 intentos)."
        log_error "Credenciales incorrectas para usuario '$user' ($intentos/3)"
    done

    log_error "Acceso denegado: superado límite de intentos para usuario '$user'"
    return 1
}

alta_producto() {
    local id="" nombre="" precio=""
    read -rp "Ingrese ID: " id

    if [[ -z "$id" ]]; then
        echo "Error: El ID no puede estar vacío."
        log_error "Alta fallida: ID vacío"
        return
    fi

    local existe=$(sqlite3 "$DB_FILE" "SELECT count(*) FROM productos WHERE id='$id';")
    if [[ "$existe" -gt 0 ]]; then
        echo "Error: Ya existe un producto con el ID '$id'."
        log_error "Alta fallida: ID '$id' ya existente"
        return
    fi

    read -rp "Ingrese Nombre: " nombre
    read -rp "Ingrese Precio: " precio

    sqlite3 "$DB_FILE" "INSERT INTO productos (id, nombre, precio) VALUES ('$id', '$nombre', '$precio');"
    echo "Producto '$nombre' agregado con éxito."
    log_system "Alta producto (ID: $id, Nombre: $nombre, Precio: $precio)"
}

baja_producto() {
    local id=""
    read -rp "Ingrese ID a eliminar: " id

    local existe=$(sqlite3 "$DB_FILE" "SELECT count(*) FROM productos WHERE id='$id';")
    if [[ "$existe" -eq 0 ]]; then
        echo "Error: El producto con ID '$id' no existe."
        log_error "Baja fallida: ID '$id' no encontrado"
        return
    fi

    sqlite3 "$DB_FILE" "DELETE FROM productos WHERE id='$id';"
    echo "Producto '$id' eliminado con éxito."
    log_system "Baja producto (ID: $id)"
}

modificar_producto() {
    local id=""
    read -rp "Ingrese ID a modificar: " id

    local existe=$(sqlite3 "$DB_FILE" "SELECT count(*) FROM productos WHERE id='$id';")
    if [[ "$existe" -eq 0 ]]; then
        echo "Error: El producto con ID '$id' no existe."
        log_error "Modificación fallida: ID '$id' no encontrado"
        return
    fi

    local nuevo_nom="" nuevo_pre=""
    read -rp "Ingrese nuevo Nombre: " nuevo_nom
    read -rp "Ingrese nuevo Precio: " nuevo_pre

    sqlite3 "$DB_FILE" "UPDATE productos SET nombre='$nuevo_nom', precio='$nuevo_pre' WHERE id='$id';"
    echo "Producto '$id' modificado con éxito."
    log_system "Modificar producto (ID: $id, NuevoNombre: $nuevo_nom, NuevoPrecio: $nuevo_pre)"
}

mostrar_productos() {
    echo -e "\nLISTADO DE PRODUCTOS:"
    echo -e "ID\tNombre\tPrecio"
    echo "-----------------------------------"

    local total=$(sqlite3 "$DB_FILE" "SELECT count(*) FROM productos;")
    if [[ "$total" -eq 0 ]]; then
        echo "No hay productos registrados."
    else
        sqlite3 -separator $'\t' "$DB_FILE" "SELECT id, nombre, '$' || precio FROM productos;"
    fi

    log_system "Consulta de inventario"
}

generar_reporte_html() {
    echo "<html>" > "$FILE_REPORTE"
    echo "<head><meta charset='UTF-8'><title>Reporte de Productos</title></head>" >> "$FILE_REPORTE"
    echo "<body>" >> "$FILE_REPORTE"
    echo "  <h1>Reporte de Productos</h1>" >> "$FILE_REPORTE"
    echo "  <table border='1' cellpadding='8'>" >> "$FILE_REPORTE"
    echo "    <tr><th>ID</th><th>Nombre</th><th>Precio</th></tr>" >> "$FILE_REPORTE"


    sqlite3 -separator $'\t' "$DB_FILE" "SELECT id, nombre, precio FROM productos;" | while IFS=$'\t' read -r id nom pre; do
        if [[ -n "$id" ]]; then
            echo "    <tr><td>$id</td><td>$nom</td><td>$$pre</td></tr>" >> "$FILE_REPORTE"
        fi
    done

    echo "  </table>" >> "$FILE_REPORTE"
    echo "</body>" >> "$FILE_REPORTE"
    echo "</html>" >> "$FILE_REPORTE"

    echo "Reporte HTML generado exitosamente en '$FILE_REPORTE'."
    log_system "Generación de reporte HTML ($FILE_REPORTE)"
}

menu_principal() {
    local opcion=""
    while [[ "$opcion" != "6" ]]; do
        echo -e "\nACCIONES:"
        echo "1. Alta producto"
        echo "2. Baja producto"
        echo "3. Modificar producto"
        echo "4. Mostrar inventario"
        echo "5. Generar reporte HTML"
        echo "6. Salir"
        read -rp "Opcion: " opcion

        case $opcion in
            1) alta_producto ;;
            2) baja_producto ;;
            3) modificar_producto ;;
            4) mostrar_productos ;;
            5) generar_reporte_html ;;
            6)
                log_system "Cierre de sesión"
                SESSION_ID="-"
                SESSION_USER="-"
                echo "Cerrando sesión..."
                ;;
            *)
                echo "Opción inválida."
                log_error "Opción de menú inválida: $opcion"
                ;;
        esac
    done
}

main() {
    inicializar_db
    echo "Bienvenido/a al sistema"

    local opcion_inicio=""
    while true; do
        echo -e "\nMENU DE INICIO:"
        echo "1. Iniciar sesion"
        echo "2. Registrar usuario"
        echo "3. Salir"
        read -rp "Opcion: " opcion_inicio

        case $opcion_inicio in
            1)
                if autenticar; then
                    menu_principal
                else
                    echo "Acceso denegado."
                fi
                ;;
            2) registrar_usuario ;;
            3)
                log_system "Salida del programa"
                echo "Saliendo del programa..."
                exit 0
                ;;
            *)
                echo "Opción inválida."
                log_error "Opción de menú inicio inválida: $opcion_inicio"
                ;;
        esac
    done
}

main
