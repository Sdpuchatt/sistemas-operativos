#!/usr/bin/env bash


source "./model.sh"

CURRENT_USER_ID="-"
CURRENT_USER_NAME="-"


api_hash() {
    local raw=$(echo "$1" | sha256sum)
    echo "${raw:0:64}"
}


api_init() {
    if ! command -v sqlite3 &>/dev/null; then
        echo "Error: sqlite3 no está instalado. Ejecute: sudo apt install sqlite3"
        return 1
    fi
    model_init_db
    return 0
}

api_user_register() {
    local user="$1" clave="$2"

    if [[ -z "$user" || -z "$clave" ]]; then
        model_log_error "$CURRENT_USER_ID" "$CURRENT_USER_NAME" "Registro fallido: campos vacíos"
        echo "ERROR: Usuario y clave son obligatorios."
        return 1
    fi

    if model_user_exists "$user"; then
        model_log_error "$CURRENT_USER_ID" "$CURRENT_USER_NAME" "Registro fallido: el usuario '$user' ya existe"
        echo "ERROR: El usuario '$user' ya existe."
        return 1
    fi

    local hash=$(api_hash "$clave")
    model_user_add "$user" "$hash"
    model_log_system "$CURRENT_USER_ID" "$CURRENT_USER_NAME" "Registro de usuario: $user"
    echo "OK: Usuario '$user' registrado con éxito."
    return 0
}

api_user_login() {
    local user="$1" clave="$2"

    if [[ $(model_user_count) -eq 0 ]]; then
        model_log_error "-" "-" "Login fallido: sin usuarios registrados"
        echo "ERROR: No hay usuarios registrados."
        return 2
    fi

    local hash=$(api_hash "$clave")
    local auth_data=$(model_user_auth "$user" "$hash")

    if [[ -n "$auth_data" ]]; then
        CURRENT_USER_ID=$(echo "$auth_data" | cut -d'|' -f1)
        CURRENT_USER_NAME=$(echo "$auth_data" | cut -d'|' -f2)
        model_log_system "$CURRENT_USER_ID" "$CURRENT_USER_NAME" "Inicio de sesión exitoso"
        echo "OK: Acceso concedido."
        return 0
    fi

    model_log_error "-" "$user" "Credenciales incorrectas"
    echo "ERROR: Credenciales incorrectas."
    return 1
}

api_user_logout() {
    model_log_system "$CURRENT_USER_ID" "$CURRENT_USER_NAME" "Cierre de sesión"
    CURRENT_USER_ID="-"
    CURRENT_USER_NAME="-"
}

api_product_add() {
    local id="$1" nombre="$2" precio="$3"

    if [[ -z "$id" || -z "$nombre" || -z "$precio" ]]; then
        model_log_error "$CURRENT_USER_ID" "$CURRENT_USER_NAME" "Alta producto: campos incompletos"
        echo "ERROR: Todos los campos son obligatorios."
        return 1
    fi

    if model_product_exists "$id"; then
        model_log_error "$CURRENT_USER_ID" "$CURRENT_USER_NAME" "Alta producto: ID '$id' duplicado"
        echo "ERROR: Ya existe un producto con el ID '$id'."
        return 1
    fi

    model_product_add "$id" "$nombre" "$precio"
    model_log_system "$CURRENT_USER_ID" "$CURRENT_USER_NAME" "Alta producto ID: $id"
    echo "OK: Producto '$nombre' agregado con éxito."
    return 0
}

api_product_delete() {
    local id="$1"

    if ! model_product_exists "$id"; then
        model_log_error "$CURRENT_USER_ID" "$CURRENT_USER_NAME" "Baja producto: ID '$id' no encontrado"
        echo "ERROR: El producto con ID '$id' no existe."
        return 1
    fi

    model_product_delete "$id"
    model_log_system "$CURRENT_USER_ID" "$CURRENT_USER_NAME" "Baja producto ID: $id"
    echo "OK: Producto '$id' eliminado con éxito."
    return 0
}

api_product_modify() {
    local id="$1" nombre="$2" precio="$3"

    if ! model_product_exists "$id"; then
        model_log_error "$CURRENT_USER_ID" "$CURRENT_USER_NAME" "Modificar producto: ID '$id' no encontrado"
        echo "ERROR: El producto con ID '$id' no existe."
        return 1
    fi

    model_product_update "$id" "$nombre" "$precio"
    model_log_system "$CURRENT_USER_ID" "$CURRENT_USER_NAME" "Modificar producto ID: $id"
    echo "OK: Producto '$id' modificado con éxito."
    return 0
}

api_product_list() {
    model_log_system "$CURRENT_USER_ID" "$CURRENT_USER_NAME" "Consulta de inventario"
    model_product_list
}

api_generate_report() {
    echo "<html><head><meta charset='UTF-8'><title>Reporte de Productos</title></head><body>" > "$CONFIG_REPORT_HTML"
    echo "<h1>Reporte de Productos</h1><table border='1' cellpadding='8'><tr><th>ID</th><th>Nombre</th><th>Precio</th></tr>" >> "$CONFIG_REPORT_HTML"

    model_product_list | while IFS=$'\t' read -r id nom pre; do
        if [[ -n "$id" ]]; then
            echo "<tr><td>$id</td><td>$nom</td><td>$$pre</td></tr>" >> "$CONFIG_REPORT_HTML"
        fi
    done

    echo "</table></body></html>" >> "$CONFIG_REPORT_HTML"
    model_log_system "$CURRENT_USER_ID" "$CURRENT_USER_NAME" "Generar reporte HTML"
    echo "OK: Reporte generado en $CONFIG_REPORT_HTML"
}
