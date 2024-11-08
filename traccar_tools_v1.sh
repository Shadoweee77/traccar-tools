#!/bin/bash
# by slawallo

show_menu(){
    normal=`echo "\033[m"`
    menu=`echo "\033[36m"` #Blue
    number=`echo "\033[33m"` #yellow
    bgred=`echo "\033[41m"`
    fgred=`echo "\033[31m"`
    printf "\n${menu}*********************************************************${normal}\n"
    printf "${menu}**${number} 1)${menu} Uninstall Traccar v4.1 and later ${normal}\n"
    printf "${menu}**${number} 2)${menu} Uninstall Traccar v4.0 and earlier ${normal}\n"
    printf "${menu}**${number} 3)${menu} Fresh Install Traccar ${normal}\n"
    printf "${menu}**${number} 4)${menu} Upgrade Traccar (Back up and restore config files) ${normal}\n"
    printf "${menu}**${number} 5)${menu} Restart Traccar v4.1 and later${normal}\n"
    printf "${menu}**${number} 6)${menu} Show log (q to exit)${normal}\n"
    printf "${menu}**${number} 7)${menu} Traccar service status (q to exit)${normal}\n"
    printf "${menu}**${number} 8)${menu} Check latest Traccar version ${normal}\n"
    printf "${menu}*********************************************************${normal}\n"
    printf "Please choose from menu option, ${fgred}enter ${normal}or ${fgred}x ${normal}to exit. ${normal}"
    read opt
}

option_picked(){
    msgcolor=`echo "\033[01;31m"` # bold red
    normal=`echo "\033[00;00m"` # normal white
    message=${@:-"${normal}Error: No message passed"}
    printf "${msgcolor}${message}${normal}\n"
}

clear
show_menu
while [ "$opt" != '' ]
    do
    if [ "$opt" = '' ]; then
      exit;
    else
      case $opt in
        1) clear;
            option_picked "Option 1 Picked";
while true; do
    read -p "Do you really want to uninstall Traccar y/n ? " yn
    case $yn in
        [Yy]* ) sudo systemctl stop traccar.service; sudo systemctl disable traccar.service; sudo rm /etc/systemd/system/traccar.service; sudo systemctl daemon-reload; sudo rm -R /opt/traccar; sleep 3; clear; break;;
        [Nn]* ) clear; break;;
        * ) echo "Please answer yes or no.";;
    esac

done
            show_menu;
        ;;
        2) clear;
            option_picked "Option 2 Picked";
while true; do
    read -p "Do you really want to uninstall Traccar y/n ? " yn
    case $yn in
        [Yy]* ) sudo /opt/traccar/bin/uninstallDaemon.sh; sudo rm -R /opt/traccar; sleep 3; clear; break;;
        [Nn]* ) clear; break;;
        * ) echo "Please answer yes or no.";;
    esac

done

            show_menu;
        ;;
        3) clear;
            option_picked "Option 3 Picked";
# Download Traccar
	    curl -fsSLI -o /dev/null -w %{url_effective} https://github.com/traccar/traccar/releases/latest > upgrade_traccar.tmp
	    sed -i 's/tag/download/g' upgrade_traccar.tmp
            sed -i 's|$|/traccar-linux-64-*.zip|g' upgrade_traccar.tmp
            sed -i "s/*/$(grep -E -o "v.{0,3}" upgrade_traccar.tmp | tail -c +2)/g" upgrade_traccar.tmp

while true; do
            echo Latest available version
            grep -E -o ".{0,21}z.{0,4}" upgrade_traccar.tmp
    read -p "Do you wish to download Traccar y/n ? " yn
    case $yn in
        [Yy]* ) wget -i upgrade_traccar.tmp; break;;
        [Nn]* ) rm -f traccar.run README.txt traccar-linux-*.zip* upgrade_traccar.tmp; break;;
        * ) echo "Please answer yes or no.";;
    esac

done

rm -f upgrade_traccar.tmp


# Install Traccar

while true; do
    read -p "Do you wish to install Traccar y/n ? " yn
    case $yn in
        [Yy]* ) echo "Installation in 3s.";sleep 3; unzip traccar-linux-*.zip; sudo ./traccar.run; echo "Starting System"; sleep 2; sudo systemctl start traccar.service; echo "Done"; sleep 3; clear; break;;
        [Nn]* ) rm -f traccar.run README.txt traccar-linux-*.zip* upgrade_traccar.tmp; clear; break;;
        * ) echo "Please answer yes or no.";;
    esac
done


rm -f traccar.run README.txt traccar-linux-*.zip* upgrade_traccar.tmp
            show_menu;
        ;;
        4) clear;
            option_picked "Option 4 Picked";
# Download Traccar
	    curl -fsSLI -o /dev/null -w %{url_effective} https://github.com/traccar/traccar/releases/latest > upgrade_traccar.tmp
	    sed -i 's/tag/download/g' upgrade_traccar.tmp
            sed -i 's|$|/traccar-linux-64-*.zip|g' upgrade_traccar.tmp
            sed -i "s/*/$(grep -E -o "v.{0,3}" upgrade_traccar.tmp | tail -c +2)/g" upgrade_traccar.tmp

while true; do
            echo Latest available version
            grep -E -o ".{0,21}z.{0,4}" upgrade_traccar.tmp
    read -p "Do you wish to download Traccar y/n ? " yn
    case $yn in
        [Yy]* ) wget -i upgrade_traccar.tmp; break;;
        [Nn]* ) rm -f traccar.run README.txt traccar-linux-*.zip* upgrade_traccar.tmp; break;;
        * ) echo "Please answer yes or no.";;
    esac

done

rm -f upgrade_traccar.tmp


# Install Traccar

while true; do
    read -p "Do you wish to upgrade Traccar y/n ? " yn
    case $yn in
        [Yy]* ) echo "Installation in 3s.";sleep 3; 
# Create the backup folder
BACKUP_PATH='/root/backup/'
if [ ! -d $BACKUP_PATH ]; then
  mkdir -p $BACKUP_PATH
fi

sudo systemctl stop traccar.service
		
# Backup config files
sudo cp /etc/systemd/system/traccar.service /root/backup/traccar.service
sudo cp /opt/traccar/conf/*.xml /root/backup
sudo cp /opt/traccar/conf/traccar.xml /root/backup/traccar.xml_`date +"%d-%m-%Y_%H:%M:%S"`
sudo cp /opt/traccar/conf/default.xml /root/backup/default.xml_`date +"%d-%m-%Y_%H:%M:%S"`
sudo cp /opt/traccar/conf/*.conf /root/backup
sudo cp /opt/traccar/data/*.db /root/backup



# Remove Traccar
sudo systemctl disable traccar.service
sudo rm /etc/systemd/system/traccar.service
sudo systemctl daemon-reload
sudo rm -R /opt/traccar		
		
unzip traccar-linux-*.zip
sudo ./traccar.run

# Restore config files
sudo cp /root/backup/traccar.service /etc/systemd/system/traccar.service
sudo chmod 664 /etc/systemd/system/traccar.service
sudo systemctl daemon-reload
sudo cp /root/backup/traccar.xml /opt/traccar/conf
sudo cp /root/backup/*.conf /opt/traccar/conf
sudo cp /root/backup/*.db /opt/traccar/data
		
		echo "Starting System"; sleep 2; sudo systemctl start traccar.service; echo "Done"; sleep 3; clear; break;;
        [Nn]* ) rm -f traccar.run README.txt traccar-linux-*.zip* upgrade_traccar.tmp; clear; break;;
        * ) echo "Please answer yes or no.";;
    esac
done


rm -f traccar.run README.txt traccar-linux-*.zip* upgrade_traccar.tmp
            show_menu;
        ;;
        5) clear;
            option_picked "Option 5 Picked";
            sudo systemctl restart traccar.service;
            show_menu;
        ;;
        6) clear;
            option_picked "Option 6 Picked";
            less /opt/traccar/logs/tracker-server.log;
            show_menu;
        ;;
        7) clear;
            option_picked "Option 7 Picked";
            sudo systemctl status traccar.service;
            show_menu;
        ;;
        8) clear;
            option_picked "Option 8 Picked";
	    curl -fsSLI -o /dev/null -w %{url_effective} https://github.com/traccar/traccar/releases/latest > upgrade_traccar.tmp
	    sed -i 's/tag/download/g' upgrade_traccar.tmp
            sed -i 's|$|/traccar-linux-64-*.zip|g' upgrade_traccar.tmp
            sed -i "s/*/$(grep -E -o "v.{0,3}" upgrade_traccar.tmp | tail -c +2)/g" upgrade_traccar.tmp
            echo Latest available version
            grep -E -o ".{0,21}z.{0,4}" upgrade_traccar.tmp
            rm -f upgrade_traccar.tmp
            show_menu;
        ;;
        x)exit;
        ;;
        \n)exit;
        ;;
        *)clear;
            option_picked "Pick an option from the menu";
            show_menu;
        ;;
      esac
    fi
done
