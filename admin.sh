#!/bin/bash

check_requirements() {
    local missing=()

    # Check for sshpass
    if ! command -v sshpass &> /dev/null; then
        missing+=("sshpass")
    fi

    # Check for dialog
    if ! command -v dialog &> /dev/null; then
        missing+=("dialog")
    fi

    # If any utilities are missing, prompt the user
    if [ ${#missing[@]} -ne 0 ]; then
        echo "The following required utilities are missing: ${missing[*]}"
        read -p "Would you like to install them now? (y/n): " choice
        case "$choice" in
            y|Y )
                for pkg in "${missing[@]}"; do
                    if command -v apt-get &> /dev/null; then
                        sudo apt-get install -y "$pkg"
                    elif command -v yum &> /dev/null; then
                        sudo yum install -y "$pkg"
                    else
                        echo "Unsupported package manager. Please install $pkg manually."
                        exit 1
                    fi
                done
                ;;
            * )
                echo "Please install the required utilities and rerun the script."
                exit 1
                ;;
        esac
    fi
}

# Call the check_requirements function at the start of the script
check_requirements

# Simple Login Menu
login_menu() {
    ENCRYPTION_PASSPHRASE=$(dialog --title "Encryption Passphrase" --passwordbox "Enter encryption passphrase:" 8 40 3>&1 1>&2 2>&3)
    gpg --quiet --batch --yes --decrypt --passphrase "$ENCRYPTION_PASSPHRASE" --output hosts.txt hosts.txt.gpg

    dialog --title "Login" --inputbox "Enter Username:" 8 40 2>username.txt
    dialog --title "Login" --passwordbox "Enter Password:" 8 40 2>password.txt

    USERNAME=$(<username.txt)
    PASSWORD=$(<password.txt)

    # Simulated authentication (replace with real logic)
    if [[ "$USERNAME" == "admin" && "$PASSWORD" == "password" ]]; then
        rm -f username.txt password.txt
        return 0
    else
        rm -f username.txt password.txt
        dialog --title "Error" --msgbox "Invalid credentials!" 6 40
        return 1
    fi
}

#!/bin/bash

# Ensure dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "dialog could not be found. Please install it before running this script."
    exit 1
fi

# File to store SSH hosts
HOSTS_FILE="hosts.txt"

# Function to add a host

add_host() {
    # Decrypt the file
    gpg --quiet --batch --yes --decrypt --passphrase "$ENCRYPTION_PASSPHRASE" --output hosts.txt hosts.txt.gpg

    # Add a new host
    dialog --title "Add Host" --inputbox "Enter Hostname or IP:" 8 40 2>host.txt
    dialog --title "Add Host" --inputbox "Enter Username:" 8 40 2>username.txt
    dialog --title "Add Host" --inputbox "Enter SSH Key Path (optional):" 8 40 2>keypath.txt
    dialog --title "SSH Password" --passwordbox "Enter your SSH password (for remote host access):" 8 40 2>ssh_password.txt
    dialog --title "Sudo Password" --passwordbox "Enter your sudo password (for remote commands):" 8 40 2>sudo_password.txt

    HOSTNAME=$(<host.txt)
    USERNAME=$(<username.txt)
    KEYPATH=$(<keypath.txt)
    SSH_PASSWORD=$(<ssh_password.txt)
    SUDO_PASSWORD=$(<sudo_password.txt)

    rm -f host.txt username.txt keypath.txt ssh_password.txt sudo_password.txt

    if [ -z "$HOSTNAME" ] || [ -z "$USERNAME" ]; then
        dialog --title "Error" --msgbox "Hostname and Username are required!" 6 40
        return
    fi

    echo "$HOSTNAME,$USERNAME,$KEYPATH,$SSH_PASSWORD,$SUDO_PASSWORD" >> hosts.txt

    # Re-encrypt the file
    gpg --quiet --batch --yes --symmetric --cipher-algo AES256 --passphrase "$ENCRYPTION_PASSPHRASE" hosts.txt
    rm -f hosts.txt

    dialog --title "Success" --msgbox "Host added successfully!" 6 40
}


# Function to remove a host
remove_host() {
    gpg --quiet --batch --yes --decrypt --passphrase "$ENCRYPTION_PASSPHRASE" --output hosts.txt hosts.txt.gpg

    if [ ! -f $HOSTS_FILE ] || [ ! -s $HOSTS_FILE ]; then
        dialog --title "Error" --msgbox "No hosts to remove!" 6 40
        return
    fi

    HOSTS=$(awk -F',' '{print NR" "$1" ("$2")"}' $HOSTS_FILE)
    SELECTION=$(dialog --title "Remove Host" --menu "Select a host to remove:" 15 50 10 $HOSTS 2>&1 >/dev/tty)

    if [ -n "$SELECTION" ]; then
        sed -i "${SELECTION}d" $HOSTS_FILE
        dialog --title "Success" --msgbox "Host removed successfully!" 6 40
    fi
}
manage_power() {
    
    decrypt_hosts
    
     # Decrypt the file temporarily
    gpg --quiet --batch --yes --decrypt --passphrase "$ENCRYPTION_PASSPHRASE" --output hosts.txt hosts.txt.gpg

    # Parse hosts.txt to create a selection menu
    HOSTS_MENU="ALL All_Hosts "
    while IFS=',' read -r HOSTNAME USERNAME _; do
        if [ -n "$HOSTNAME" ]; then
            HOSTS_MENU+="$HOSTNAME $USERNAME "
        fi
    done < hosts.txt

    # Present the menu
    SELECTED_HOST=$(dialog --title "Power Management" --menu "Choose a host or select ALL:" 15 50 10 $HOSTS_MENU 2>&1 >/dev/tty)
    if [ -z "$SELECTED_HOST" ]; then
        dialog --title "Error" --msgbox "No host selected." 6 40
        return
    fi

    # Prompt for action
    ACTION=$(dialog --title "Select Action" --menu "Choose an action:" 12 50 3 \
        "1" "Shutdown" \
        "2" "Restart" \
        "3" "Restart thinclient Script" 2>&1 >/dev/tty)

    case $ACTION in
        1)
            execute_remote_command "$SELECTED_HOST" "sudo shutdown now"
            ;;
        2)
            execute_remote_command "$SELECTED_HOST" "sudo reboot"
            ;;
        3)
            execute_remote_command "$SELECTED_HOST" "sudo pkill -f thinclient; sleep 3; nohup thinclient &"
            ;;
        *)
            dialog --title "Error" --msgbox "Invalid action selected." 6 40
            ;;
    esac
}


execute_remote_command() {
    local host=$1
    local command=$2

    if [ "$host" == "ALL" ]; then
        # Process all hosts
        while IFS=',' read -r HOSTNAME USERNAME KEYPATH SSH_PASSWORD SUDO_PASSWORD; do
            dialog --title "Processing Host" --infobox "Performing action on $HOSTNAME..." 6 40
            if [[ -z "$KEYPATH" ]]; then
                sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no $USERNAME@$HOSTNAME "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$command'"
            else
                ssh -i "$KEYPATH" -o StrictHostKeyChecking=no $USERNAME@$HOSTNAME "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$command'"
            fi
        done < hosts.txt
        dialog --title "Success" --msgbox "Action applied to all hosts!" 6 40
    else
        # Process a single host
        HOST_DETAILS=$(grep "^$host," hosts.txt)
        REMOTE_USERNAME=$(echo "$HOST_DETAILS" | cut -d ',' -f 2)
        KEYPATH=$(echo "$HOST_DETAILS" | cut -d ',' -f 3)
        SSH_PASSWORD=$(echo "$HOST_DETAILS" | cut -d ',' -f 4)
        SUDO_PASSWORD=$(echo "$HOST_DETAILS" | cut -d ',' -f 5)

        if [[ -z "$REMOTE_USERNAME" || -z "$SSH_PASSWORD" || -z "$SUDO_PASSWORD" ]]; then
            dialog --title "Error" --msgbox "Host details are incomplete. Please re-add the host." 6 40
            return
        fi

        if [[ -z "$KEYPATH" ]]; then
            sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no $REMOTE_USERNAME@$host "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$command'"
        else
            ssh -i "$KEYPATH" -o StrictHostKeyChecking=no $REMOTE_USERNAME@$host "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$command'"
        fi

        dialog --title "Success" --msgbox "Action applied to $host!" 6 40
    fi
}
decrypt_hosts() {
    # Decrypt the file temporarily
    gpg --quiet --batch --yes --decrypt --passphrase "$ENCRYPTION_PASSPHRASE" --output hosts.txt hosts.txt.gpg

}
view_hosts() {
    # Decrypt the file temporarily
    gpg --quiet --batch --yes --decrypt --passphrase "$ENCRYPTION_PASSPHRASE" --output hosts.txt hosts.txt.gpg

    # Display only IP and username
    awk -F',' '{print NR". " $1 " (" $2 ")"}' hosts.txt > view_hosts.txt
    dialog --title "View Hosts" --textbox view_hosts.txt 15 50
    rm -f view_hosts.txt hosts.txt

     # Re-encrypt the file
    gpg --quiet --batch --yes --symmetric --cipher-algo AES256 --passphrase "$ENCRYPTION_PASSPHRASE" hosts.txt
    rm -f hosts.txt
    rm -f modify_vdi.sh
}


# Function to manage hosts
manage_hosts() {
    while true; do
        OPTION=$(dialog --clear \
            --title "Manage Hosts" \
            --menu "Choose an option:" 15 50 4 \
            "1" "Add Host" \
            "2" "Remove Host" \
            "3" "View Hosts" \
            "4" "Back to Main Menu" \
            2>&1 >/dev/tty)

        case $OPTION in
            1)
                add_host
                ;;
            2)
                remove_host
                ;;
            3)
                view_hosts
                ;;
            4)
                break
                ;;
            *)
                dialog --title "Error" --msgbox "Invalid option. Please try again." 6 40
                ;;
        esac
    done
}
# Function to modify the VDI client configuration via SSH
# Main variables
LOG_FILE="/home/vdiuser/admin.log"

# Ensure the log directory exists
mkdir -p $(dirname "$LOG_FILE")

# Ensure dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "dialog could not be found. Please install it before running this script."
    exit 1
fi


# Function to modify the VDI client configuration

# Modify Client Configuration
modify_client() {
    decrypt_hosts

    # Parse hosts.txt to create a selection menu
    HOSTS_MENU="ALL All_Hosts "
    while IFS=',' read -r HOSTNAME USERNAME _; do
        if [ -n "$HOSTNAME" ]; then
            HOSTS_MENU+="$HOSTNAME $USERNAME "
        fi
    done < hosts.txt

    # Select a host or all hosts
    SELECTED_HOST=$(dialog --title "Modify Thin Client" --menu "Choose a client to modify or select ALL:" 15 50 10 $HOSTS_MENU 2>&1 >/dev/tty)
    if [ -z "$SELECTED_HOST" ]; then
        dialog --title "Error" --msgbox "No host selected." 6 40
        return
    fi

    # Gather modification details
    dialog --title "Modify Thin Client" --inputbox "Enter Proxmox IP/DNS:" 8 40 2>proxmox_ip.txt
    dialog --title "Modify Thin Client" --inputbox "Enter Thin Client Title:" 8 40 2>vdi_title.txt
    dialog --title "Modify Thin Client" --inputbox "Enter Authentication Method (pve/pam):" 8 40 2>vdi_auth.txt

    VDI_THEME=$(dialog --title "Theme" --menu "Choose a Theme:" 15 50 20 \
        "Black" "Black Theme" \
        "BlueMono" "Blue Mono Theme" \
        "BluePurple" "Blue Purple Theme" \
        "BrightColors" "Bright Colors Theme" \
        "BrownBlue" "Brown Blue Theme" \
        "Dark" "Dark Theme" \
        "Dark2" "Dark Theme 2" \
        "DarkAmber" "Dark Amber Theme" \
        "DarkBlack" "Dark Black Theme" \
        "DarkBlue" "Dark Blue Theme" \
        "DarkGreen" "Dark Green Theme" \
        "LightBlue" "Light Blue Theme" \
        "LightGrey" "Light Grey Theme" \
        "Material1" "Material Theme 1" \
        "NeutralBlue" "Neutral Blue Theme" \
        "Purple" "Purple Theme" \
        "Reddit" "Reddit Theme" \
        "TanBlue" "Tan Blue Theme" \
        "TealMono" "Teal Mono Theme" \
        3>&1 1>&2 2>&3)

    if [ -z "$VDI_THEME" ]; then
        dialog --title "Error" --msgbox "No theme selected. Please try again." 6 40
        return
    fi

    # Build the modification script
    MODIFICATION_COMMAND=$(cat <<EOF
sudo mkdir -p /etc/vdiclient
sudo tee /etc/vdiclient/vdiclient.ini > /dev/null <<EOL
[General]
title = $(<vdi_title.txt)
theme = $VDI_THEME
[Authentication]
auth_backend = $(<vdi_auth.txt)
tls_verify = false
[Hosts]
$(<proxmox_ip.txt)=8006
EOL
EOF
)

rm -f proxmox_ip.txt vdi_title.txt vdi_auth.txt

# Execute the modification command
execute_remote_command "$SELECTED_HOST" "$MODIFICATION_COMMAND"



# Cleanup
    # Re-encrypt the file
gpg --quiet --batch --yes --symmetric --cipher-algo AES256 --passphrase "$ENCRYPTION_PASSPHRASE" hosts.txt
rm -f hosts.txt
rm -f modify_vdi.sh

}

# VDI Management System Main Menu
main_menu() { 
    while true; do
        OPTION=$(dialog --clear \
            --title "VDI Management System" \
            --menu "Choose an option:" 15 50 7 \
            "1" "Update" \
            "2" "Install" \
            "3" "Modify" \
            "4" "Add/Remove Hosts" \
            "5" "Shutdown/Restart Hosts" \
            "6" "Exit" \
            2>&1 >/dev/tty)

        case $OPTION in
            1)
                dialog --title "Update" --msgbox "Performing update..." 6 40
                ;;
            2)
                dialog --title "Install" --msgbox "Installing software..." 6 40
                ;;
            3)
                modify_client
                ;;
            4)
                manage_hosts
                ;;
            5)
                manage_power
                ;;
            6)
                dialog --title "Exit" --msgbox "Exiting system. Goodbye!" 6 40
                clear
                exit 0
                ;;
            *)
                dialog --title "Error" --msgbox "Invalid option. Please try again." 6 40
                ;;
        esac
    done
}


# Main script logic
while true; do
    if login_menu; then
        main_menu
    else
        dialog --title "Authentication Failed" --yesno "Would you like to retry?" 6 40
        if [[ $? -ne 0 ]]; then
            clear
            # Re-encrypt the file
            gpg --quiet --batch --yes --symmetric --cipher-algo AES256 --passphrase "$ENCRYPTION_PASSPHRASE" hosts.txt
            rm -f hosts.txt
            exit 0
        fi
    fi

done

