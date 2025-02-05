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
login_menu

# Simple Login Menu
login_menu() {
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



# Ensure dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "dialog could not be found. Please install it before running this script."
    exit 1
fi

# File to store SSH hosts
HOSTS_FILE="hosts.txt"

# Function to add a host

add_host() {
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


    rm -f host.txt username.txt keypath.txt ssh_password.txtsudo_password.txt

    if [ -z "$HOSTNAME" ] || [ -z "$USERNAME" ]; then
        dialog --title "Error" --msgbox "Hostname and Username are required!" 6 40
        return
    fi

    echo "$HOSTNAME,$USERNAME,$KEYPATH,$SSH_PASSWORD,$SUDO_PASSWORD" >> hosts.txt
    dialog --title "Success" --msgbox "Host added successfully!" 6 40
}

# Function to remove a host
remove_host() {
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
    # Ensure the hosts file exists
    if [ ! -f "hosts.txt" ] || [ ! -s "hosts.txt" ]; then
        dialog --title "Error" --msgbox "No hosts found! Add hosts first." 6 40
        return
    fi

    # Parse hosts.txt to create a selection menu
    HOSTS_MENU="ALL All_Hosts "
    while IFS=',' read -r HOSTNAME USERNAME _; do
        if [ -n "$HOSTNAME" ]; then
            HOSTS_MENU+="$HOSTNAME $USERNAME "
        fi
    done < hosts.txt

    # Present the menu
    SELECTED_HOST=$(dialog --title "Select SSH Host" --menu "Choose a host to manage power or select ALL for all hosts:" 15 50 10 $HOSTS_MENU 2>&1 >/dev/tty)

    if [ -z "$SELECTED_HOST" ]; then
        dialog --title "Error" --msgbox "No host selected." 6 40
        return
    fi

    # Prompt for shutdown or restart
    ACTION=$(dialog --title "Shutdown or Restart" --menu "Choose an action:" 10 40 2 \
        "1" "Shutdown" \
        "2" "Restart" 2>&1 >/dev/tty)

    if [ "$ACTION" == "1" ]; then
        POWER_CMD="sudo shutdown now"
    elif [ "$ACTION" == "2" ]; then
        POWER_CMD="sudo reboot"
    else
        dialog --title "Error" --msgbox "Invalid action selected." 6 40
        return
    fi

    if [ "$SELECTED_HOST" == "ALL" ]; then
        # Process all hosts
        exec 3< hosts.txt
        while IFS=',' read -r HOSTNAME USERNAME KEYPATH SSH_PASSWORD SUDO_PASSWORD <&3; do
            dialog --title "Processing Host" --infobox "Performing action on $HOSTNAME..." 6 40
            if [[ -z "$KEYPATH" ]]; then
                sshpass -p "$SSH_PASSWORD" ssh $USERNAME@$HOSTNAME "echo \"$SUDO_PASSWORD\" | sudo -S $POWER_CMD"
            else
                ssh -i "$KEYPATH" $USERNAME@$HOSTNAME "echo \"$SUDO_PASSWORD\" | sudo -S $POWER_CMD"
            fi
        done
        exec 3<&-
        dialog --title "Success" --msgbox "Action applied to all hosts!" 6 40
    else
        # Process a single host
        HOST_DETAILS=$(grep "^$SELECTED_HOST," hosts.txt)
        REMOTE_USERNAME=$(echo "$HOST_DETAILS" | cut -d ',' -f 2)
        KEYPATH=$(echo "$HOST_DETAILS" | cut -d ',' -f 3)
        SSH_PASSWORD=$(echo "$HOST_DETAILS" | cut -d ',' -f 4)
        SUDO_PASSWORD=$(echo "$HOST_DETAILS" | cut -d ',' -f 5)

        if [[ -z "$REMOTE_USERNAME" || -z "$SSH_PASSWORD" || -z "$SUDO_PASSWORD" ]]; then
            dialog --title "Error" --msgbox "Host details are incomplete. Please re-add the host." 6 40
            return
        fi

        if [[ -z "$KEYPATH" ]]; then
            sshpass -p "$SSH_PASSWORD" ssh $REMOTE_USERNAME@$SELECTED_HOST "echo \"$SUDO_PASSWORD\" | sudo -S $POWER_CMD"
        else
            ssh -i "$KEYPATH" $REMOTE_USERNAME@$SELECTED_HOST "echo \"$SUDO_PASSWORD\" | sudo -S $POWER_CMD"
        fi

        dialog --title "Success" --msgbox "Action applied to $SELECTED_HOST!" 6 40
    fi
}

lockdown_mode() {

    
    # Parse hosts.txt to create a selection menu
    HOSTS_MENU="ALL All_Hosts "
    while IFS=',' read -r HOSTNAME USERNAME KEYPATH SSH_PASSWORD SUDO_PASSWORD; do
        if [ -n "$HOSTNAME" ]; then
            HOSTS_MENU+="$HOSTNAME $USERNAME "
        fi
    done < hosts.txt

    # Present the menu
    SELECTED_HOST=$(dialog --title "Select SSH Host" --menu "Choose a host to apply lockdown mode:" 15 50 10 $HOSTS_MENU 2>&1 >/dev/tty)

    if [ -z "$SELECTED_HOST" ]; then
        dialog --title "Error" --msgbox "No host selected." 6 40
        return
    fi
    
    # Choose action: Lockdown or Reopen Terminal
    ACTION=$(dialog --title "Lockdown Mode" --menu "Select an action:" 10 40 2 \
        "1" "Lockdown System" \
        "2" "Reopen Terminal" 2>&1 >/dev/tty)
    
    if [ "$ACTION" == "1" ]; then
        STATUS_MSG="Lockdown"
    elif [ "$ACTION" == "2" ]; then
        STATUS_MSG="System Online"
    else
        dialog --title "Error" --msgbox "Invalid action selected." 6 40
        return
    fi
    
    # Check current status and apply action
    if [ "$SELECTED_HOST" == "ALL" ]; then
        exec 3< hosts.txt
        while IFS=',' read -r HOSTNAME USERNAME KEYPATH SSH_PASSWORD SUDO_PASSWORD <&3; do
            dialog --title "Processing Host" --infobox "Applying action on $HOSTNAME..." 6 40
            if [[ -z "$KEYPATH" ]]; then
                sshpass -p "$SSH_PASSWORD" ssh $USERNAME@$HOSTNAME "echo '$STATUS_MSG' > status"
                sshpass -p "$SSH_PASSWORD" ssh $USERNAME@$HOSTNAME "pkill -f python"
            else
                ssh -i "$KEYPATH" $USERNAME@$HOSTNAME "echo '$STATUS_MSG' > status"
                ssh -i "$KEYPATH" $USERNAME@$HOSTNAME "pkill -f python"
            fi
        done
        exec 3<&-
        dialog --title "Success" --msgbox "Action applied to all hosts!" 6 40
    else
        HOST_DETAILS=$(grep "^$SELECTED_HOST," hosts.txt)
        REMOTE_USERNAME=$(echo "$HOST_DETAILS" | cut -d ',' -f 2)
        KEYPATH=$(echo "$HOST_DETAILS" | cut -d ',' -f 3)
        SSH_PASSWORD=$(echo "$HOST_DETAILS" | cut -d ',' -f 4)
        SUDO_PASSWORD=$(echo "$HOST_DETAILS" | cut -d ',' -f 5)

        if [[ -z "$REMOTE_USERNAME" || -z "$SSH_PASSWORD" || -z "$SUDO_PASSWORD" ]]; then
            dialog --title "Error" --msgbox "Host details are incomplete. Please re-add the host." 6 40
            return
        fi

        if [[ -z "$KEYPATH" ]]; then
            sshpass -p "$SSH_PASSWORD" ssh $REMOTE_USERNAME@$SELECTED_HOST "echo '$STATUS_MSG' > status"
            sshpass -p "$SSH_PASSWORD" ssh $REMOTE_USERNAME@$SELECTED_HOST "pkill -f python"
        else
            ssh -i "$KEYPATH" $REMOTE_USERNAME@$SELECTED_HOST "echo '$STATUS_MSG' > status"
            ssh -i "$KEYPATH" $REMOTE_USERNAME@$SELECTED_HOST "pkill -f python"
        fi

        dialog --title "Success" --msgbox "Action applied to $SELECTED_HOST!" 6 40
    fi
}




update_hosts() {
    

    # Parse hosts.txt to create a selection menu
    HOSTS_MENU="ALL All_Hosts "
    while IFS=',' read -r HOSTNAME USERNAME _; do
        if [ -n "$HOSTNAME" ]; then
            HOSTS_MENU+="$HOSTNAME $USERNAME "
        fi
    done < hosts.txt

    # Select a host or all hosts
    SELECTED_HOST=$(dialog --title "Update Hosts" --menu "Choose a host to update or select ALL:" 15 50 10 $HOSTS_MENU 2>&1 >/dev/tty)
    if [ -z "$SELECTED_HOST" ]; then
        dialog --title "Error" --msgbox "No host selected." 6 40
        return
    fi

    # Define the update commands
    UPDATE_COMMANDS=$(cat <<EOF
sudo apt update &&
sudo apt upgrade -y &&
sudo apt install -y proxmoxer python3-pip virt-viewer lightdm zenity lightdm-gtk-greeter dialog sshpass python3-tk &&
sudo apt autoremove -y
EOF
)

    if [ "$SELECTED_HOST" == "ALL" ]; then
        # Process all hosts
        exec 3< hosts.txt
        while IFS=',' read -r HOSTNAME USERNAME KEYPATH SSH_PASSWORD SUDO_PASSWORD <&3; do
            dialog --title "Processing Host" --infobox "Performing action on $HOSTNAME..." 6 40
            if [[ -z "$KEYPATH" ]]; then
                sshpass -p "$SSH_PASSWORD" ssh $USERNAME@$HOSTNAME "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$UPDATE_COMMANDS'"
            else
                ssh -i "$KEYPATH" $USERNAME@$HOSTNAME "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$UPDATE_COMMANDS'"
            fi
        done
        exec 3<&-
        dialog --title "Success" --msgbox "Action applied to all hosts!" 6 40
    else
        # Process a single host
        HOST_DETAILS=$(grep "^$SELECTED_HOST," hosts.txt)
        REMOTE_USERNAME=$(echo "$HOST_DETAILS" | cut -d ',' -f 2)
        KEYPATH=$(echo "$HOST_DETAILS" | cut -d ',' -f 3)
        SSH_PASSWORD=$(echo "$HOST_DETAILS" | cut -d ',' -f 4)
        SUDO_PASSWORD=$(echo "$HOST_DETAILS" | cut -d ',' -f 5)

        if [[ -z "$REMOTE_USERNAME" || -z "$SSH_PASSWORD" || -z "$SUDO_PASSWORD" ]]; then
            dialog --title "Error" --msgbox "Host details are incomplete. Please re-add the host." 6 40
            return
        fi

        if [[ -z "$KEYPATH" ]]; then
            sshpass -p "$SSH_PASSWORD" ssh $REMOTE_USERNAME@$SELECTED_HOST "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$UPDATE_COMMANDS'"
        else
            ssh -i "$KEYPATH" $REMOTE_USERNAME@$SELECTED_HOST "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$UPDATE_COMMANDS'"
        fi

        dialog --title "Success" --msgbox "Action applied to $SELECTED_HOST!" 6 40
    fi
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
                if [ ! -f $HOSTS_FILE ] || [ ! -s $HOSTS_FILE ]; then
                    dialog --title "View Hosts" --msgbox "No hosts available!" 6 40
                else
                    dialog --title "View Hosts" --textbox $HOSTS_FILE 15 50
                fi
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
    if [ ! -f "$HOSTS_FILE" ] || [ ! -s "$HOSTS_FILE" ]; then
        dialog --title "Error" --msgbox "No hosts found! Add hosts first." 6 40
        return
    fi

    # Parse hosts for selection
    HOSTS_MENU="ALL All_Hosts "
    while IFS=',' read -r HOSTNAME USERNAME _; do
        if [ -n "$HOSTNAME" ]; then
            HOSTS_MENU+="$HOSTNAME $USERNAME "
        fi
    done < $HOSTS_FILE

    SELECTED_HOST=$(dialog --title "Select SSH Host" --menu "Choose a client to modify or select ALL:" 15 50 10 $HOSTS_MENU 2>&1 >/dev/tty)
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

    # Read user inputs
    PROXMOX_IP=$(<proxmox_ip.txt)
    VDI_TITLE=$(<vdi_title.txt)
    VDI_AUTH=$(<vdi_auth.txt)
    rm -f proxmox_ip.txt vdi_title.txt vdi_auth.txt

    if [[ -z "$PROXMOX_IP" || -z "$VDI_TITLE" || -z "$VDI_AUTH" ]]; then
        dialog --title "Error" --msgbox "All fields are required!" 6 40
        return
    fi

    # Generate the modification script
    cat > ./modify_vdi.sh <<EOF
#!/bin/bash
sudo mkdir -p /etc/vdiclient
sudo tee /etc/vdiclient/vdiclient.ini > /dev/null <<EOL
[General]
title = $VDI_TITLE
theme = $VDI_THEME
[Authentication]
auth_backend = $VDI_AUTH
auth_totp = false
tls_verify = false

[Hosts]
$PROXMOX_IP=8006
EOL
EOF






    if [ "$SELECTED_HOST" == "ALL" ]; then
        # Process all hosts
        exec 3< hosts.txt  # Open hosts.txt for reading using file descriptor 3
        while IFS=',' read -r HOSTNAME USERNAME KEYPATH SSH_PASSWORD SUDO_PASSWORD <&3; do
            dialog --title "Processing Host" --infobox "Processing $HOSTNAME..." 6 40
            if [[ -z "$KEYPATH" ]]; then
                sshpass -p "$SSH_PASSWORD" scp ./modify_vdi.sh $USERNAME@$HOSTNAME:~/
                sshpass -p "$SSH_PASSWORD" ssh $USERNAME@$HOSTNAME "chmod +x modify_vdi.sh && echo \"$SUDO_PASSWORD\" | sudo -S ./modify_vdi.sh && rm -f modify_vdi.sh && pkill -f python"
            else
                scp -i "$KEYPATH" ./modify_vdi.sh $USERNAME@$HOSTNAME:~/
                ssh -i "$KEYPATH" $USERNAME@$HOSTNAME "chmod +x modify_vdi.sh && echo \"$SUDO_PASSWORD\" | sudo -S ./modify_vdi.sh && rm -f modify_vdi.sh && pkill -f python"
            fi
        done
        exec 3<&-  # Close file descriptor 3
        dialog --title "Success" --msgbox "Configuration applied to all hosts!" 6 40
    else
        # Process a single host
        HOST_DETAILS=$(grep "^$SELECTED_HOST," hosts.txt)
        REMOTE_USERNAME=$(echo "$HOST_DETAILS" | cut -d ',' -f 2)
        KEYPATH=$(echo "$HOST_DETAILS" | cut -d ',' -f 3)
        SSH_PASSWORD=$(echo "$HOST_DETAILS" | cut -d ',' -f 4)
        SUDO_PASSWORD=$(echo "$HOST_DETAILS" | cut -d ',' -f 5)

        if [[ -z "$REMOTE_USERNAME" || -z "$SSH_PASSWORD" || -z "$SUDO_PASSWORD" ]]; then
            dialog --title "Error" --msgbox "Host details are incomplete. Please re-add the host." 6 40
            return
        fi

        if [[ -z "$KEYPATH" ]]; then
            sshpass -p "$SSH_PASSWORD" scp ./modify_vdi.sh $REMOTE_USERNAME@$SELECTED_HOST:~/
            sshpass -p "$SSH_PASSWORD" ssh $REMOTE_USERNAME@$SELECTED_HOST "chmod +x modify_vdi.sh && echo \"$SUDO_PASSWORD\" | sudo -S ./modify_vdi.sh && rm -f modify_vdi.sh"
            sshpass -p "$SSH_PASSWORD" ssh $REMOTE_USERNAME@$SELECTED_HOST "pkill python"
        else
            scp -i "$KEYPATH" ./modify_vdi.sh $REMOTE_USERNAME@$SELECTED_HOST:~/
            ssh -i "$KEYPATH" $REMOTE_USERNAME@$SELECTED_HOST "chmod +x modify_vdi.sh && echo \"$SUDO_PASSWORD\" | sudo -S ./modify_vdi.sh && rm -f modify_vdi.sh"
            ssh -i "$KEYPATH" $REMOTE_USERNAME@$SELECTED_HOST "pkill zenity"
            
        fi

        dialog --title "Success" --msgbox "Configuration applied to $SELECTED_HOST!" 6 40
    fi

    #     # After the installation or updates are done
    # if [ "$SELECTED_HOST" == "ALL" ]; then
    #     exec 3< hosts.txt
    #     while IFS=',' read -r HOSTNAME USERNAME KEYPATH SSH_PASSWORD SUDO_PASSWORD <&3; do
    #         dialog --title "Processing Host" --infobox "Prompting restart on $HOSTNAME..." 6 40
    #         prompt_restart_vdi "$HOSTNAME" "$USERNAME" "$KEYPATH" "$SSH_PASSWORD" "$SUDO_PASSWORD"
    #     done
    #     exec 3<&-
    # else
    #     HOST_DETAILS=$(grep "^$SELECTED_HOST," hosts.txt)
    #     REMOTE_USERNAME=$(echo "$HOST_DETAILS" | cut -d ',' -f 2)
    #     KEYPATH=$(echo "$HOST_DETAILS" | cut -d ',' -f 3)
    #     SSH_PASSWORD=$(echo "$HOST_DETAILS" | cut -d ',' -f 4)
    #     SUDO_PASSWORD=$(echo "$HOST_DETAILS" | cut -d ',' -f 5)

    #     prompt_restart_vdi "$SELECTED_HOST" "$REMOTE_USERNAME" "$KEYPATH" "$SSH_PASSWORD" "$SUDO_PASSWORD"
    # fi

    # Cleanup
    rm -f modify_vdi.sh
}
prompt_restart_vdi() {
    local host=$1
    local username=$2
    local keypath=$3
    local ssh_password=$4
    local sudo_password=$5

    # Command to display the Zenity prompt on the remote machine
    local zenity_command=$(cat <<EOF
DISPLAY=:0 zenity --question --title="Restart VDI Client" --text="A system update has been performed. Would you like to restart the VDI client now?" --ok-label="Restart" --cancel-label="Later"
if [ \$? -eq 0 ]; then
    echo "$sudo_password" | sudo -S reboot
fi
EOF
)

    if [[ -z "$keypath" ]]; then
        sshpass -p "$ssh_password" ssh -o StrictHostKeyChecking=no $username@$host "bash -c '$zenity_command'"
    else
        ssh -i "$keypath" -o StrictHostKeyChecking=no $username@$host "bash -c '$zenity_command'"
    fi
}

decrypt_hosts() {
    # Decrypt the file temporarily
    gpg --quiet --batch --yes --decrypt --passphrase "$ENCRYPTION_PASSPHRASE" --output hosts.txt hosts.txt.gpg

}

install_vdi_client() {
    

    # Prompt to add a new host or use an existing host
    CHOICE=$(dialog --title "Install VDI Client" --menu "Choose an option:" 12 50 2 \
        "1" "Add a New Host" \
        "2" "Use an Existing Host" 3>&1 1>&2 2>&3)

    if [ "$CHOICE" == "1" ]; then
        add_host
    fi

    # Parse hosts.txt to create a selection menu
    HOSTS_MENU="ALL All_Hosts "
    while IFS=',' read -r HOSTNAME USERNAME _; do
        if [ -n "$HOSTNAME" ]; then
            HOSTS_MENU+="$HOSTNAME $USERNAME "
        fi
    done < hosts.txt

    SELECTED_HOST=$(dialog --title "Select SSH Host" --menu "Choose a host to install VDI Client or select ALL:" 15 50 10 $HOSTS_MENU 2>&1 >/dev/tty)
    if [ -z "$SELECTED_HOST" ]; then
        dialog --title "Error" --msgbox "No host selected." 6 40
        return
    fi

    # Gather required variables
    dialog --title "Install VDI Client" --inputbox "Enter the Proxmox IP or DNS name:" 8 40 2>proxmox_ip.txt
    dialog --title "Install VDI Client" --inputbox "Enter the Thin Client Title:" 8 40 2>vdi_title.txt

    while true; do
        VDI_AUTH=$(dialog --title "Install VDI Client" --menu "Select Authentication Type:" 12 40 2 \
            "pve" "Proxmox VE Authentication" \
            "pam" "Pluggable Authentication Module" 3>&1 1>&2 2>&3)
        if [[ "$VDI_AUTH" == "pve" || "$VDI_AUTH" == "pam" ]]; then
            break
        else
            dialog --title "Error" --msgbox "Invalid selection. Please choose 'pve' or 'pam'." 6 40
        fi
    done

    #dialog --title "Install VDI Client" --inputbox "Enter your Network Adapter (e.g., eth0, enp1s0):" 8 40 2>network_adapter.txt

    PROXMOX_IP=$(<proxmox_ip.txt)
    VDI_TITLE=$(<vdi_title.txt)
    #NETWORK_ADAPTER=$(<network_adapter.txt)
    rm -f proxmox_ip.txt vdi_title.txt 

    # Confirm the collected variables
    dialog --title "Confirm Installation Variables" --msgbox "Proxmox IP: $PROXMOX_IP\nThin Client Title: $VDI_TITLE\nAuth Type: $VDI_AUTH" 10 50

    # Clone and prepare the repo locally
    TEMP_DIR="/tmp/simpledebianvdi"
    REPO_URL="https://github.com/JacksonBaer/simpledebianvdi.git"
    BRANCH="cli"

    dialog --title "Cloning Repository" --infobox "Cloning repository branch $BRANCH..." 6 50
    # rm -rf "$TEMP_DIR"
    # git clone -b "$BRANCH" "$REPO_URL" "$TEMP_DIR"

    # if [ $? -ne 0 ]; then
    #     dialog --title "Error" --msgbox "Failed to clone repository. Check your internet connection." 6 50
    #     return
    # fi

    # Define commands
    INSTALL_COMMAND="sudo git clone -b $BRANCH $REPO_URL && cd simpledebianvdi && sudo chmod +x simple_setup.sh && sudo ./simple_setup.sh -i $PROXMOX_IP -t '$VDI_TITLE' -a $VDI_AUTH "
    AUTOSTART_COMMAND="sudo mkdir -p /home/vdiuser/.config/lxsession/LXDE && echo '@/usr/bin/bash /home/vdiuser/thinclient' | sudo tee /home/vdiuser/.config/lxsession/LXDE/autostart"
    REBOOT_COMMAND="sudo reboot"

    # Execute the install command
    dialog --title "Installing VDI Client" --infobox "Installing VDI Client on selected host(s)..." 6 50
    if [ "$SELECTED_HOST" == "ALL" ]; then
        # Loop over all hosts and execute the commands
        exec 3< hosts.txt
        while IFS=',' read -r HOSTNAME USERNAME KEYPATH SSH_PASSWORD SUDO_PASSWORD <&3; do
            dialog --title "Processing Host" --infobox "Installing on $HOSTNAME..." 6 40
            if [[ -z "$KEYPATH" ]]; then
                sshpass -p "$SSH_PASSWORD" ssh $USERNAME@$HOSTNAME "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$INSTALL_COMMAND'"
                sshpass -p "$SSH_PASSWORD" ssh $USERNAME@$HOSTNAME "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$AUTOSTART_COMMAND'"
                sshpass -p "$SSH_PASSWORD" ssh $USERNAME@$HOSTNAME "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$REBOOT_COMMAND'"
            else
                ssh -i "$KEYPATH" $USERNAME@$HOSTNAME "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$INSTALL_COMMAND'"
                ssh -i "$KEYPATH" $USERNAME@$HOSTNAME "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$AUTOSTART_COMMAND'"
                ssh -i "$KEYPATH" $USERNAME@$HOSTNAME "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$REBOOT_COMMAND'"
            fi
        done
        exec 3<&-
    else
        # Execute on the selected host
        HOST_DETAILS=$(grep "^$SELECTED_HOST," hosts.txt)
        REMOTE_USERNAME=$(echo "$HOST_DETAILS" | cut -d ',' -f 2)
        KEYPATH=$(echo "$HOST_DETAILS" | cut -d ',' -f 3)
        SSH_PASSWORD=$(echo "$HOST_DETAILS" | cut -d ',' -f 4)
        SUDO_PASSWORD=$(echo "$HOST_DETAILS" | cut -d ',' -f 5)

        if [[ -z "$REMOTE_USERNAME" || -z "$SSH_PASSWORD" || -z "$SUDO_PASSWORD" ]]; then
            dialog --title "Error" --msgbox "Host details are incomplete. Please re-add the host." 6 40
            return
        fi

        if [[ -z "$KEYPATH" ]]; then
            sshpass -p "$SSH_PASSWORD" ssh $REMOTE_USERNAME@$SELECTED_HOST "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$INSTALL_COMMAND'"
            sshpass -p "$SSH_PASSWORD" ssh $REMOTE_USERNAME@$SELECTED_HOST "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$AUTOSTART_COMMAND'"
            sshpass -p "$SSH_PASSWORD" ssh $REMOTE_USERNAME@$SELECTED_HOST "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$REBOOT_COMMAND'"
        else
            ssh -i "$KEYPATH" $REMOTE_USERNAME@$SELECTED_HOST "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$INSTALL_COMMAND'"
            ssh -i "$KEYPATH" $REMOTE_USERNAME@$SELECTED_HOST "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$AUTOSTART_COMMAND'"
            ssh -i "$KEYPATH" $REMOTE_USERNAME@$SELECTED_HOST "echo \"$SUDO_PASSWORD\" | sudo -S bash -c '$REBOOT_COMMAND'"
        fi
    fi

    # Cleanup
    rm -rf "$TEMP_DIR"
    dialog --title "Installation Complete" --msgbox "VDI Client installation and autostart configuration completed successfully!" 8 50
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
            "6" "Lockdown Systems" \
            "7" "Exit" \
            2>&1 >/dev/tty)

        case $OPTION in
            1)
                update_hosts
                ;;
            2)
                install_vdi_client                
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
                lockdown_mode
                ;;
            7)
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
            exit 0
        fi
    fi

done

