#!/usr/bin/env bash



source "./config.sh"

model_init_db() {
    sqlite3 "$CONFIG_DB" << 'EOF'
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

model_log_system() {
    local uid="$1" user="$2" accion="$3"
    local fecha=$(date '+%Y-%m-%d %H:%M:%S')
    printf "%s\t%s\t%s\t%s\n" "$fecha" "$uid" "$user" "$accion" >> "$CONFIG_LOG_SYSTEM"
}

model_log_error() {
    local uid="$1" user="$2" mensaje="$3"
    local fecha=$(date '+%Y-%m-%d %H:%M:%S')
    printf "%s\t%s\t%s\t%s\n" "$fecha" "$uid" "$user" "$mensaje" >> "$CONFIG_LOG_ERROR"
}


model_user_count() {
    sqlite3 "$CONFIG_DB" "SELECT count(*) FROM usuarios;"
}

model_user_exists() {
    local user="$1"
    local count=$(sqlite3 "$CONFIG_DB" "SELECT count(*) FROM usuarios WHERE usuario='$user';")
    [[ "$count" -gt 0 ]]
}

model_user_add() {
    local user="$1" hash="$2"
    sqlite3 "$CONFIG_DB" "INSERT INTO usuarios (usuario, clave) VALUES ('$user', '$hash');"
}

model_user_auth() {
    local user="$1" hash="$2"
    sqlite3 -separator '|' "$CONFIG_DB" "SELECT id, usuario FROM usuarios WHERE usuario='$user' AND clave='$hash' LIMIT 1;"
}


model_product_exists() {
    local id="$1"
    local count=$(sqlite3 "$CONFIG_DB" "SELECT count(*) FROM productos WHERE id='$id';")
    [[ "$count" -gt 0 ]]
}

model_product_add() {
    local id="$1" nombre="$2" precio="$3"
    sqlite3 "$CONFIG_DB" "INSERT INTO productos (id, nombre, precio) VALUES ('$id', '$nombre', '$precio');"
}

model_product_delete() {
    local id="$1"
    sqlite3 "$CONFIG_DB" "DELETE FROM productos WHERE id='$id';"
}

model_product_update() {
    local id="$1" nombre="$2" precio="$3"
    sqlite3 "$CONFIG_DB" "UPDATE productos SET nombre='$nombre', precio='$precio' WHERE id='$id';"
}

model_product_list() {
    sqlite3 -separator $'\t' "$CONFIG_DB" "SELECT id, nombre, precio FROM productos;"
}
