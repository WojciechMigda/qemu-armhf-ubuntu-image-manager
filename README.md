# qemu-armhf-ubuntu-image-manager
Out-of-the-box setup of ubuntu image to run with qemu

```
$ ./varm.sh --help
Usage: varm.sh [OPTION]...
-h | --help         show help
--ssh[=COMMAND]     open ssh session to the started qemu and execute optional COMMAND upon log-on
--scp=ARGS          transfer data between host and qemu machine, e.g. --scp="file qemu@localhost:/path"
-i | --init         setup and initialize guest files from scratch. This will download kernel, initrd, and QCOW2 image,
                    and create delta image, mountable ISO image with ssh keys
-c | --continue     resume interrupted downloading of files initiated with -i option
--stdio             use stdout for console output for booted machine. If not specified data is saved in console.log file
--start             boot existing machine. This option can only appear by itself or with -i argument.
```
