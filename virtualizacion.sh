#/bin/bash

# Definir variables

imagen_base="bullseye-base-sparse.qcow2"
imagen_final="maquina1.qcow2"
imagen_nueva="newmaquina1.qcow2"
nmaquina="maquina1"
os="debian10"
index=index.j2
www=/var/www/html/  

#1. Crea una imagen nueva, que utilice bullseye-base.qcow2 como imagen base y tenga 5 GiB de tamaño máximo. Esta imagen se denominará maquina1.qcow2.
echo "Creando imagen nueva"
qemu-img create -f qcow2 -b $imagen_base $imagen_final 5G > /dev/null 2>&1
cp maquina1.qcow2 newmaquina1.qcow2 
echo "Expandiendo sistema de ficheros de la nueva imagen"
virt-resize --expand /dev/sda1 maquina1.qcow2 newmaquina1.qcow2 > /dev/null 2>&1
mv newmaquina1.qcow2 maquina1.qcow2
sleep 3
clear
#2. Crea una red interna de nombre intra con salida al exterior mediante NAT que utilice el direccionamiento 10.10.20.0/24.
echo "Creando red interna"
echo "<network>
  <name>intra2</name>
  <bridge name='virbr11'/>
  <forward/>
  <ip address='10.10.20.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='10.10.20.2' end='10.10.20.254'/>
    </dhcp>
  </ip>
</network>" > intra2.xml
sleep 1
echo "Red interna creada"
sleep 1
virsh -c qemu:///system net-define intra2.xml > /dev/null 2>&1     
echo "Red interna iniciada"
virsh -c qemu:///system net-start intra2  > /dev/null 2>&1
virsh -c qemu:///system net-autostart intra2 > /dev/null 2>&1 
sleep 3
clear
#3. Crea una máquina virtual con virsh (maquina1) conectada a la red intra, con 1 GiB de RAM, que utilice como disco raíz maquina1.qcow2 y que se inicie automáticamente. Arranca la máquina. Modifica el fichero /etc/hostname con maquina1.
echo "Creando maquina virtual"
virt-install --connect qemu:///system --name $nmaquina --ram 1024 --vcpus 1 --disk $imagen_final --network network=intra2 --network network=default --os-type linux --os-variant debian10 --import --noautoconsole
sleep 5
virsh -c qemu:///system start $nmaquina > /dev/null 2>&1
virsh -c quemu///system autostart $nmaquina > /dev/null 2>&1
echo "Iniciando la máquina $nmaquina" 
clear

#3.1 Sacar ip
sleep 10
ip=$(virsh -c qemu:///system domifaddr maquina1 | grep -oE "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | head -n 1) 

#3.1 Pasar clave pública a la máquina virtual
echo "Pasando clave pública a la máquina virtual"
ssh-copy-id debian@$ip
sleep 5
clear

#3.2 Activar usuario debian a sudoers sin contraseña
#echo "Activando usuario debian a sudoers sin contraseña"
#ssh debian@$ip "sudo apt install sudo -y"
#ssh debian@$ip "echo 'debian ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d"
#sleep 3
#clear

#4. Crea un volumen adicional de 1 GiB de tamaño en formato RAW ubicado en el pool por defecto
echo "Creando volumen adicional"
virsh -c qemu:///system vol-create-as --name maquina1-raw.img --capacity 1G --format raw --pool default > /dev/null 2>&1 
#5. Una vez iniciada la MV maquina1, conecta el volumen a la máquina, crea un sistema de ficheros XFS en el volumen y móntalo en el directorio /var/www/html. Ten cuidado con los propietarios y grupos que pongas, para que funcione adecuadamente el siguiente punto.
echo "Conectando volumen a la máquina"
virsh -c qemu:///system attach-disk maquina1 /var/lib/libvirt/images/maquina1-raw.img vdb --targetbus virtio --persistent > /dev/null 2>&1
echo "Creando sistema de ficheros XFS"
ssh debian@$ip sudo apt update -y > /dev/null 2>&1
#sshdebian@$ip sudo dpkg --configure -a /dev/null 2>&1
ssh debian@$ip sudo apt install xfsprogs -y > /dev/null 2>&1
ssh debian@$ip sudo modprobe -V xfs > /dev/null 2>&1
ssh debian@$ip sudo mkfs.xfs /dev/vdb > /dev/null 2>&1
ssh debian@$ip sudo mkdir /var/www 
ssh debian@$ip sudo mkdir /var/www/html 
echo "Configurando el volumen para montaje automático"
ssh debian@$ip "sudo -- bash -c 'echo "/dev/vdb /var/www/html xfs defaults 0 0" >> /etc/fstab'"
echo "Montando volumen en '/var/www/html'..."
ssh debian@$ip sudo mount -a

#6. Instala en maquina1 el servidor web apache2. Copia un fichero index.html a la máquina virtual.
echo "Instalando apache2"
ssh debian@$ip sudo apt install apache2 -y > /dev/null 2>&1
echo "Copiando fichero index.j2" 
scp index.j2 debian@$ip:/home/debian > /dev/null 2>&1
ssh debian@$ip sudo rm /var/www/html/index.html > /dev/null 2>&1
ssh debian@$ip sudo mv /home/debian/index.j2 /var/www/html/index.j2 > /dev/null 2>&1 
ssh debian@$ip sudo mv /var/www/html/index.j2 /var/www/html/index.html > /dev/null 2>&1 
sleep 5
clear
#7. Muestra por pantalla la dirección IP de máquina1. Pausa el script y comprueba que puedes acceder a la página web.
echo "La dirección IP de la máquina es $ip"
echo "Pulsa una tecla para continuar"
read
clear

#8. Instala LXC y crea un linux container llamado container1.
echo "Instalando LXC"
ssh debian@$ip sudo apt install lxc -y 
echo "Creando container1"
ssh debian@$ip sudo lxc-create -n contenedor1 -t debian -- -r bullseye
sleep 5
clear

#9. Añade una nueva interfaz a la máquina virtual para conectarla a la red pública (al punte br0).
echo "Apagando máquina.."
virsh -c qemu:///system shutdown $nombrevm &> /dev/null
sleep 5

## Añadimos la nueva interfaz (br0)

echo "Añadiendo nueva interfaz (br0)"
virsh -c qemu:///system attach-interface $nombrevm bridge br0 --model virtio --persistent --config &> /dev/null
echo "La intefaz br0 ha sido asociada exitosamente."
sleep 2

## Iniciamos la máquina

echo "Iniciando máquina..."
virsh -c qemu:///system start $nombrevm &> /dev/null
sleep 15
ssh debian@$ip "sudo -- bash -c 'echo "allow-hotplug enp2s0" >> /etc/network/interfaces && echo "iface enp2s0 inet dhcp" >> /etc/network/interfaces'"
sleep 3
ssh debian@$ip sudo dhclient -r && sudo dhclient
# MOSTRAR IP DE LA NUEVA INTERFAZ-----------------------------------------------------------------------
br0=$(ssh debian@$ip "ip a | egrep enp2s0 | egrep -o '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1")

echo "IP obtenida en la nueva interfaz puente: $br0"

sleep 5
#11.Apaga maquina1 y auméntale la RAM a 2 GiB y vuelve a iniciar la máquina.
echo "Apagando la máquina"
virsh -c qemu:///system shutdown $nmaquina > /dev/null 2>&1
sleep 10
echo "Aumentando la RAM a 2 GiB"
virt-xml -c qemu:///system  $nmaquina --edit --memory memory=2048,currentMemory=2048
echo "Iniciando la máquina"
virsh -c qemu:///system start $nmaquina > /dev/null 2>&1
sleep 10
clear
#12.Crea un snapshot de la máquina virtual.
echo "Creando snapshot"
virsh -c qemu:///system snapshot-create-as $nmaquina --name "snapshot1" --description "Snapshot_máquina" --disk-only --atomic
echo "Fin del script"


