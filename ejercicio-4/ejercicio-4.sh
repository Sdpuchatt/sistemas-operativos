#!/usr/bin/env bash

source "./api.sh"

if ! api_init; then
    exit 1
fi

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
            1)
                read -rp "Ingrese ID: " id
                read -rp "Ingrese Nombre: " nom
                read -rp "Ingrese Precio: " pre
                api_product_add "$id" "$nom" "$pre"
                ;;
            2)
                read -rp "Ingrese ID a eliminar: " id
                api_product_delete "$id"
                ;;
            3)
                read -rp "Ingrese ID a modificar: " id
                read -rp "Ingrese nuevo Nombre: " nom
                read -rp "Ingrese nuevo Precio: " pre
                api_product_modify "$id" "$nom" "$pre"
                ;;
            4)
                echo -e "\nLISTADO DE PRODUCTOS:"
                echo -e "ID\tNombre\tPrecio"
                echo "-----------------------------------"
                api_product_list
                ;;
            5)
                api_generate_report
                ;;
            6)
                api_user_logout
                echo "Cerrando sesión..."
                ;;
            *)
                echo "Opción inválida."
                ;;
        esac
    done
}

main() {
    echo "Bienvenido/a al sistema (Arquitectura en Capas)"
    local opcion_inicio=""

    while true; do
        echo -e "\nMENU DE INICIO:"
        echo "1. Iniciar sesion"
        echo "2. Registrar usuario"
        echo "3. Salir"
        read -rp "Opcion: " opcion_inicio

        case $opcion_inicio in
            1)
                local intentos=0
                local autenticado=0
                while (( intentos < 3 )); do
                    read -rp "Usuario: " user
                    read -rp "Contraseña: " pass

                    local res=$(api_user_login "$user" "$pass")
                    if [[ "$res" == OK* ]]; then
                        echo "Acceso concedido. ¡Bienvenido/a $user!"
                        autenticado=1
                        break
                    elif [[ "$res" == "ERROR: No hay usuarios registrados." ]]; then
                        echo "$res"
                        break
                    else
                        intentos=$((intentos + 1))
                        echo "Credenciales incorrectas ($intentos/3)."
                    fi
                done

                if (( autenticado == 1 )); then
                    menu_principal
                fi
                ;;
            2)
                read -rp "Ingrese nuevo usuario: " user
                read -rp "Ingrese nueva contraseña: " pass
                api_user_register "$user" "$pass"
                ;;
            3)
                echo "Saliendo del programa..."
                exit 0
                ;;
            *)
                echo "Opción inválida."
                ;;
        esac
    done
}

main
