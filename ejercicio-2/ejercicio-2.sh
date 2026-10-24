#!/usr/bin/env bash

FILE_PRODUCTOS="productos.tsv"
FILE_USUARIOS="usuarios.tsv"
FILE_REPORTE="productos.html"

touch "$FILE_PRODUCTOS" "$FILE_USUARIOS"


cifrar_clave() {
    local clave="$1"
    local raw=$(echo "$clave" | sha256sum)
    local hash=${raw:0:64}
    echo "$hash"
}


existe_usuario() {
    local user_buscar="$1"
    local u="" h=""
    while IFS=$'\t' read -r u h; do
        if [[ "$u" == "$user_buscar" ]]; then
            return 0  # Existe
        fi
    done < "$FILE_USUARIOS"
    return 1  # No existe
}


registrar_usuario() {
    local user="" clave=""
    read -rp "Ingrese nombre de usuario: " user

    if [[ -z "$user" ]]; then
        echo "Error: El usuario no puede estar vacío."
        return
    fi

    if existe_usuario "$user"; then
        echo "Error: El usuario '$user' ya existe."
        return
    fi

    read -rp "Ingrese contraseña: " clave
    if [[ -z "$clave" ]]; then
        echo "Error: La contraseña no puede estar vacía."
        return
    fi



    local hash=$(cifrar_clave "$clave")
    printf "%s\t%s\n" "$user" "$hash" >> "$FILE_USUARIOS"
    echo "Usuario '$user' registrado con éxito."
}



autenticar() {
    if [[ ! -s "$FILE_USUARIOS" ]]; then
        echo "No hay usuarios registrados. Por favor registre un usuario primero."
        return 1
    fi

    local intentos=0 user="" clave=""
    while (( intentos < 3 )); do
        read -rp "Usuario: " user
        read -rp "Contraseña: " clave

        local hash_ingresado=$(cifrar_clave "$clave")
        local u="" h=""

        while IFS=$'\t' read -r u h; do
            if [[ "$u" == "$user" && "$h" == "$hash_ingresado" ]]; then
                echo "Acceso concedido. Bienvenido/a $user!"
                return 0
            fi
        done < "$FILE_USUARIOS"

        intentos=$((intentos + 1))
        echo "Credenciales incorrectas ($intentos/3 intentos)."
    done

    return 1
}


existe_producto() {
    local id_buscar="$1"
    local id="" nom="" pre=""
    while IFS=$'\t' read -r id nom pre; do
        if [[ "$id" == "$id_buscar" ]]; then
            return 0  # Existe
        fi
    done < "$FILE_PRODUCTOS"
    return 1  # No existe
}

alta_producto() {
    local id="" nombre="" precio=""
    read -rp "Ingrese ID: " id

    if [[ -z "$id" ]]; then
        echo "Error: El ID no puede estar vacío."
        return
    fi

    if existe_producto "$id"; then
        echo "Error: Ya existe un producto con el ID '$id'."
        return
    fi

    read -rp "Ingrese Nombre: " nombre
    read -rp "Ingrese Precio: " precio

    printf "%s\t%s\t%s\n" "$id" "$nombre" "$precio" >> "$FILE_PRODUCTOS"
    echo "Producto '$nombre' agregado con éxito."
}

baja_producto() {
    local id=""
    read -rp "Ingrese ID a eliminar: " id

    if ! existe_producto "$id"; then
        echo "Error: El producto no existe."
        return
    fi


    local col1="" col2="" col3=""
    while IFS=$'\t' read -r col1 col2 col3; do
        if [[ "$col1" != "$id" && -n "$col1" ]]; then
            printf "%s\t%s\t%s\n" "$col1" "$col2" "$col3"
        fi
    done < "$FILE_PRODUCTOS" > temp.tsv

    mv temp.tsv "$FILE_PRODUCTOS"
    echo "Producto '$id' eliminado con éxito."
}

modificar_producto() {
    local id=""
    read -rp "Ingrese ID a modificar: " id

    if ! existe_producto "$id"; then
        echo "Error: El producto no existe."
        return
    fi

    local nuevo_nom="" nuevo_pre=""
    read -rp "Ingrese nuevo Nombre: " nuevo_nom
    read -rp "Ingrese nuevo Precio: " nuevo_pre


    local col1="" col2="" col3=""
    while IFS=$'\t' read -r col1 col2 col3; do
        if [[ "$col1" == "$id" ]]; then
            printf "%s\t%s\t%s\n" "$id" "$nuevo_nom" "$nuevo_pre"
        elif [[ -n "$col1" ]]; then
            printf "%s\t%s\t%s\n" "$col1" "$col2" "$col3"
        fi
    done < "$FILE_PRODUCTOS" > temp.tsv

    mv temp.tsv "$FILE_PRODUCTOS"
    echo "Producto '$id' modificado con éxito."
}

mostrar_productos() {
    echo -e "\nLISTADO DE PRODUCTOS:"
    echo -e "ID\tNombre\tPrecio"
    echo "-----------------------------------"

    local col1="" col2="" col3=""
    local hay_datos=0
    while IFS=$'\t' read -r col1 col2 col3; do
        if [[ -n "$col1" ]]; then
            printf "%s\t%s\t$%s\n" "$col1" "$col2" "$col3"
            hay_datos=1
        fi
    done < "$FILE_PRODUCTOS"

    if (( hay_datos == 0 )); then
        echo "No hay productos registrados."
    fi
}

generar_reporte_html() {

    echo "<html>" > "$FILE_REPORTE"
    echo "<head><meta charset='UTF-8'><title>Reporte de Productos</title></head>" >> "$FILE_REPORTE"
    echo "<body>" >> "$FILE_REPORTE"
    echo "  <h1>Reporte de Productos</h1>" >> "$FILE_REPORTE"
    echo "  <table border='1' cellpadding='8'>" >> "$FILE_REPORTE"
    echo "    <tr><th>ID</th><th>Nombre</th><th>Precio</th></tr>" >> "$FILE_REPORTE"


    local id="" nom="" pre=""
    while IFS=$'\t' read -r id nom pre; do
        if [[ -n "$id" ]]; then
            echo "    <tr><td>$id</td><td>$nom</td><td>$$pre</td></tr>" >> "$FILE_REPORTE"
        fi
    done < "$FILE_PRODUCTOS"

    echo "  </table>" >> "$FILE_REPORTE"
    echo "</body>" >> "$FILE_REPORTE"
    echo "</html>" >> "$FILE_REPORTE"

    echo "Reporte HTML generado exitosamente en '$FILE_REPORTE'."
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
            6) echo "Cerrando sesión..." ;;
            *) echo "Opción inválida." ;;
        esac
    done
}

main() {
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
            3) echo "Saliendo del programa..."; exit 0 ;;
            *) echo "Opción inválida." ;;
        esac
    done
}

main
