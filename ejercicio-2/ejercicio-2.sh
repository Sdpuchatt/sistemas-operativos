#!/usr/bin/env bash

# Archivos de persistencia de datos y reporte
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "productos.tsv" ]]; then
    PRODUCTOS_FILE="productos.tsv"
elif [[ -f "$SCRIPT_DIR/productos.tsv" ]]; then
    PRODUCTOS_FILE="$SCRIPT_DIR/productos.tsv"
else
    PRODUCTOS_FILE="productos.tsv"
fi

if [[ -f "usuarios.tsv" ]]; then
    USUARIOS_FILE="usuarios.tsv"
elif [[ -f "$SCRIPT_DIR/usuarios.tsv" ]]; then
    USUARIOS_FILE="$SCRIPT_DIR/usuarios.tsv"
else
    USUARIOS_FILE="usuarios.tsv"
fi

REPORTE_HTML="productos.html"

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

bienvenida() {
    printf "Bienvenido/a al sistema\n\n"
}

# Autenticación de usuarios contra usuarios.tsv usando cifrado sha256
autenticar() {
    declare -i intentos=0
    declare usuario=""
    declare clave=""

    if [[ ! -f "$USUARIOS_FILE" || ! -s "$USUARIOS_FILE" ]]; then
        printf "No existen usuarios registrados. Por favor registre un usuario primero.\n\n"
        return 2
    fi

    while (( intentos < 3 )); do
        read -rp "Ingrese usuario: " usuario
        read -rp "Ingrese clave: " clave

        # Cifrado de la clave ingresada mediante sha256
        declare raw_hash raw_hash_n
        raw_hash=$(echo "$clave" | sha256sum)
        declare hash_ingresado=${raw_hash:0:64}

        # Variante sin salto de linea por compatibilidad
        raw_hash_n=$(echo -n "$clave" | sha256sum)
        declare hash_ingresado_n=${raw_hash_n:0:64}

        declare autenticado=0
        declare u="" h=""
        while IFS=$'\t' read -r u h; do
            u="${u%$'\r'}"
            h="${h%$'\r'}"
            if [[ "$u" == "$usuario" && ( "$h" == "$hash_ingresado" || "$h" == "$hash_ingresado_n" ) ]]; then
                autenticado=1
                break
            fi
        done < "$USUARIOS_FILE"

        if [[ $autenticado -eq 1 ]]; then
            printf "Acceso concedido.\n"
            return 0
        fi

        intentos=$((intentos + 1))
        printf "Credenciales incorrectas (%d/3 intentos).\n" "$intentos"
    done

    return 1
}

# Registro de nuevos usuarios en usuarios.tsv con clave cifrada
registrar_usuario() {
    declare usuario=""
    declare clave=""

    read -rp "Ingrese nombre de usuario: " usuario

    if [[ -z "$usuario" ]]; then
        printf "Error: El nombre de usuario no puede estar vacio.\n"
        return 1
    fi

    # Validar que no se agregue un usuario ya existente
    if [[ -f "$USUARIOS_FILE" ]]; then
        declare u="" h=""
        while IFS=$'\t' read -r u h; do
            u="${u%$'\r'}"
            if [[ "$u" == "$usuario" ]]; then
                printf "Error: El usuario ya existe.\n"
                return 1
            fi
        done < "$USUARIOS_FILE"
    fi

    read -rp "Ingrese contraseña: " clave

    if [[ -z "$clave" ]]; then
        printf "Error: La contraseña no puede estar vacia.\n"
        return 1
    fi

    # Cifrado sha256 usando buffer y extraccion de subcadena
    declare raw_hash
    raw_hash=$(echo "$clave" | sha256sum)
    declare hash_cifrado=${raw_hash:0:64}

    printf "%s\t%s\n" "$usuario" "$hash_cifrado" >> "$USUARIOS_FILE"
    printf "Usuario '%s' registrado exitosamente.\n" "$usuario"
    return 0
}

# Comprueba si un producto ya existe en productos.tsv segun su ID
producto_existe() {
    declare id_buscar="$1"

    if [[ ! -f "$PRODUCTOS_FILE" ]]; then
        return 1
    fi

    declare col1 col2 col3
    while IFS=$'\t' read -r col1 col2 col3; do
        col1="${col1%$'\r'}"
        if [[ "$col1" == "$id_buscar" ]]; then
            return 0
        fi
    done < "$PRODUCTOS_FILE"

    return 1
}

# Alta de producto en productos.tsv
alta() {
    declare id="$1"
    declare nombre="$2"
    declare precio="$3"

    if [[ -z "$id" || -z "$nombre" || -z "$precio" ]]; then
        printf "Error: Todos los campos (ID, Nombre, Precio) son obligatorios.\n"
        return 1
    fi

    if producto_existe "$id"; then
        printf "Error: El producto con ID '%s' ya existe.\n" "$id"
        return 1
    fi

    printf "%s\t%s\t%s\n" "$id" "$nombre" "$precio" >> "$PRODUCTOS_FILE"
    printf "Producto %s guardado correctamente.\n" "$id"
    return 0
}

# Baja de producto en productos.tsv
baja() {
    declare id="$1"

    if [[ -z "$id" ]]; then
        printf "Error: Debe ingresar un ID.\n"
        return 1
    fi

    if ! producto_existe "$id"; then
        printf "El producto no existe.\n"
        return 1
    fi

    declare temp_file
    temp_file=$(mktemp 2>/dev/null) || temp_file="${PRODUCTOS_FILE}.tmp"

    declare col1 col2 col3
    while IFS=$'\t' read -r col1 col2 col3; do
        col3="${col3%$'\r'}"
        col2="${col2%$'\r'}"
        col1="${col1%$'\r'}"
        if [[ "$col1" != "$id" && -n "$col1" ]]; then
            printf "%s\t%s\t%s\n" "$col1" "$col2" "$col3" >> "$temp_file"
        fi
    done < "$PRODUCTOS_FILE"

    mv "$temp_file" "$PRODUCTOS_FILE"
    printf "Producto %s eliminado.\n" "$id"
    return 0
}

# Modificar producto en productos.tsv
modificar() {
    declare id="$1"

    if [[ -z "$id" ]]; then
        printf "Error: Debe ingresar un ID.\n"
        return 1
    fi

    if ! producto_existe "$id"; then
        printf "El producto no existe.\n"
        return 1
    fi

    declare col1 col2 col3
    declare actual_nombre="" actual_precio=""

    while IFS=$'\t' read -r col1 col2 col3; do
        col3="${col3%$'\r'}"
        col2="${col2%$'\r'}"
        col1="${col1%$'\r'}"
        if [[ "$col1" == "$id" ]]; then
            actual_nombre="$col2"
            actual_precio="$col3"
            break
        fi
    done < "$PRODUCTOS_FILE"

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

    declare temp_file
    temp_file=$(mktemp 2>/dev/null) || temp_file="${PRODUCTOS_FILE}.tmp"

    while IFS=$'\t' read -r col1 col2 col3; do
        col3="${col3%$'\r'}"
        col2="${col2%$'\r'}"
        col1="${col1%$'\r'}"
        if [[ "$col1" == "$id" ]]; then
            printf "%s\t%s\t%s\n" "$col1" "$nuevo_nombre" "$nuevo_precio" >> "$temp_file"
        elif [[ -n "$col1" ]]; then
            printf "%s\t%s\t%s\n" "$col1" "$col2" "$col3" >> "$temp_file"
        fi
    done < "$PRODUCTOS_FILE"

    mv "$temp_file" "$PRODUCTOS_FILE"
    printf "Producto %s modificado con precio $%s.\n" "$id" "$nuevo_precio"
    return 0
}

# Mostrar inventario listando los productos desde productos.tsv
mostrar() {
    if [[ ! -f "$PRODUCTOS_FILE" || ! -s "$PRODUCTOS_FILE" ]]; then
        printf "\nLISTADO:\n"
        printf "No hay productos registrados.\n"
        return 0
    fi

    printf "\nLISTADO:\n"
    declare col1 col2 col3
    while IFS=$'\t' read -r col1 col2 col3; do
        col3="${col3%$'\r'}"
        col2="${col2%$'\r'}"
        col1="${col1%$'\r'}"
        [[ -z "$col1" ]] && continue
        printf "ID %s : %s - $%s\n" "$col1" "$col2" "$col3"
    done < "$PRODUCTOS_FILE"
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

    if [[ -f "$PRODUCTOS_FILE" ]]; then
        declare col1 col2 col3
        while IFS=$'\t' read -r col1 col2 col3; do
            col3="${col3%$'\r'}"
            col2="${col2%$'\r'}"
            col1="${col1%$'\r'}"
            [[ -z "$col1" ]] && continue
            printf "            <tr><td>%s</td><td>%s</td><td>$%s</td></tr>\n" "$col1" "$col2" "$col3" >> "$REPORTE_HTML"
        done < "$PRODUCTOS_FILE"
    fi

    cat << 'EOF' >> "$REPORTE_HTML"
        </tbody>
    </table>
</body>
</html>
EOF

    printf "Reporte '%s' generado exitosamente.\n" "$REPORTE_HTML"
    return 0
}

main() {
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
                # Si estado_auth == 2 (no hay usuarios registrados), vuelve al menu
                ;;
            $OPCION_INICIO_REGISTRO)
                registrar_usuario
                printf "\n"
                ;;
            $OPCION_INICIO_SALIR)
                printf "\nSaliendo del programa...\n"
                return 0
                ;;
            *)
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
                printf "\nSaliendo del programa...\n"
                ;;
            *)
                printf "\nOpcion invalida.\n"
                ;;
        esac
    done

    return 0
}

main
