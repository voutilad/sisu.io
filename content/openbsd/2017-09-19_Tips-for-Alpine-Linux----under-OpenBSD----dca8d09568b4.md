---
title: "Tips for Alpine Linux \U0001F5FB under OpenBSD \U0001F421"
description: "Tips & Tricks for a kickass OpenBSD \U0001F421 dev-oriented laptop \U0001F4BB"
date: '2017-09-19T11:48:58.385Z'
tags: [archives, linux, openbsd]
---

> Note: This is an old post from when I wrote on medium.com...formatting may be wonky here until I clean it up.

![Matterhorn…if you squint you can see Puffy up there, I swear. ([https://commons.wikimedia.org/wiki/File:Matterhorn\_from\_Domh%C3%BCtte\_-\_2.jpg](https://commons.wikimedia.org/wiki/File:Matterhorn_from_Domh%C3%BCtte_-_2.jpg))](https://cdn-images-1.medium.com/max/800/1*Ird9QLfasg60n7LVB6RCpw.jpeg)
Matterhorn…if you squint you can see Puffy up there, I swear. ([https://commons.wikimedia.org/wiki/File:Matterhorn\_from\_Domh%C3%BCtte\_-\_2.jpg](https://commons.wikimedia.org/wiki/File:Matterhorn_from_Domh%C3%BCtte_-_2.jpg))

Virtualization is just plain fun. While I do rely on it specifically to satisfy professional needs while running OpenBSD on my laptop (mostly hacking on [some enterprise Java software](https://www.attivio.com) that doesn’t natively support \*BSD), I find myself constantly fascinated by it and tinkering with it.

The OpenBSD man pages are a great resources, as well are the [mailing lists](https://www.openbsd.org/mail.html) and [FAQ](https://www.openbsd.org/faq/index.html)…but when it comes to _non-OpenBSD specific needs like tuning your Linux VM_ there isn’t much out there. Hopefully someone finds these useful 😀

The following are some tips/tricks for making Alpine Linux far more usable under OpenBSD, especially if you need to do real _work_ in a Linux environment and want to do it on your local OpenBSD machine without rebooting.

This post will cover some **installation**, **disk management**, and **vm networking** tips!

1.  The Serial Console
2.  Alpine install over SSH
3.  Fast Alpine VM boots
4.  Adding a dedicated data disk
5.  Telling Docker to use a separate disk

### Alpine VM under OpenBSD 101: the Serial Console

_Honestly, this should be self-evident if you’ve played with Alpine and VMD. If not, it doesn’t hurt to revisit. Trust me I’ve_ [_personally lost sanity points_](https://marc.info/?t=150445710200001&r=1&w=2) _on this._

Alpine has many flavors, each with slightly different, pre-baked boot args, kernel configs, etc. Regardless of which you use you need to properly tell [Alpine’s boot loader](http://www.syslinux.org/) to pass along details to the kernel that you need serial console support. (I believe the exception is the _virt_ flavor, but it doesn’t hurt to know this!)

At boot, hit `TAB` to see the boot menu label available. Chances are it’s something like `hardened` or `grsec` depending on your Alpine version (3.6 vs. older).

Type the name (e.g. “hardened”), a space, and then `console=ttyS0,115200` like so: `hardened console=ttyS0,115200`. It should be all you need to properly get serial console access via the `-c` flag during `vmctl start` or when using `vmctl console`.

### Install over SSH instead of the Serial Console

There are still some sync issues between OpenBSD’s serial terminal emulator ([cu(1)](https://man.openbsd.org/cu)) and the virtualized serial console “plugged” into the Alpine Linux VM. This problem, on my host system, seems non-deterministic in how it randomly locks up…so I recommend scrambling to establish SSH access to complete the install.

While it’s not readily apparent, most Alpine iso flavors (at least _alpine-standard_) have the OpenSSH package available, just not installed. This means you don’t even need internet access in the VM.

Once your inside Alpine Linux after initial boot from the iso:

1.  **Install OpenSSH**: `apk add openssh`
2.  **Set a root password**: `passwd root`
3.  **Permit root login**: Edit the sshd config in `/etc/ssh/sshd_config`, uncommenting and changing the _PermitRootLogin_ line to something like `PermitRootLogin yes`. You can use `vi` or `sed` or whatever floats your 🛥
4.  **Start OpenSSH**: `/etc/init.d/sshd start`
5.  **Initialize the virtualized ethernet device and get an IP**: `setup-alpine` is the easiest way to do this…just work through the steps up until you select a network device and configure either static of a dynamic IP (write this down or copy it).
6.  **Abort the install**: `^c`

Once you have the IP, it’s safe to kill the serial console via the `cu(1)` control sequence `<return><return><tilde><period>` (`RET RET ~.`).

Then just ssh into the Alpine box using the IP you obtained or set during the aborted install and you’ll be on far more stable connection, bypassing the serial console. From there you can re-run `alpine-setup` and complete the install.

### ⏱ Faster, Unassisted VM Boots

If you’ve followed other guidance you may have at least configured the Alpine instance to [use the serial console by default](https://wiki.alpinelinux.org/wiki/Enable_Serial_Console_on_Boot). However, unless you intervene you’ll either have long boot times or have to manually intervene to navigate the boot menu presented by syslinux. Let’s change that so `vm.conf` can then be used to start it automatically at OpenBSD boot time quickly and confidently.

BTW: This is easily done during install and _before_ reboot/poweroff of the VM. If you’ve just completed `alpine-setup`, you just need to mount the boot partition from your new disk: `mount /dev/vdb1 /mnt`

> Note: It most likely will be the `vdb` block device assuming `vdb` is the device you chose to initialize as `sys` . Choose whichever device you chose during `setup-alpine`.

Update the config file`/mnt/boot/syslinux/extlinux.conf` (or `/boot/syslinux/extlinux.conf` if you’re already rebooted after install) to make it look more like the following:

You can either comment out existing lines or remove them entirely. The important things to note are:

1.  Remove the `MENU` related entries, other than any nested under `LABEL`.
2.  Preserve your `LABEL` block since it has your system’s root partition _UUID_ (mine won’t work for you) and the proper kernel name, which may be different.
3.  Set `DEFAULT` to the `LABEL` value you want to boot, e.g. `hardened`

Save and reboot. Other than maybe a slow ntp daemon, it should boot right up and be ready to go.

### 💾 Adding a Dedicated “Data” Disk to the Alpine VM

This is super handy if you plan on storing lots of stuff within the Alpine VM and want to be able to nuke the root disk. Let’s say your root disk image (where you’ve installed Alpine) is called `alpine-data.img`.

1.  Create a new disk image: `$ vmctl create alpine-data.img -s 20G`
2.  Start the VM with the new disk attached: `$ vmctl start my-alpine-vm -d alpine-root.img -d alpine-data.img`
3.  Once booted, install [GNU parted](https://www.gnu.org/software/parted/): `# apk add parted`
4.  Configure a new [GPT](https://en.wikipedia.org/wiki/GUID_Partition_Table) label: `(parted) mklabel gpt`
5.  Set unit size: `(parted) unit MiB`
6.  Make a new Ext4 partition (use like _disk size-1_: `(parted) mkpart 1 ext4 1 20479`
7.  Check for optimal disk partition alignment: `(parted) align-check opt`
8.  Name the partition whatever you want (e.g. “data”): `(parted) name 1 data`
9.  Quit parted: `(parted) quit`
10.  Initialize the Ext4 filesystem on the new disk: `# mkfs.ext4 /dev/vdb1`
11.  Note the partition UUID that `mkfs` reports! Copy that.
12.  Make a new mount point for the disk, ideally owned by the Alpine Linux user you’ll be working as most of the time.
13.  Update `/etc/fstab` in Alpine, adding a new line with the UUID like: `UUID=2fc3aff6–5a80–4ef7–809b-33de8a3ceb17 /data ext4 rw,relatime,user 0 0`
14.  Confirm things are A-OK by running as root: `mount /data` (where /data is my mount-point). If things are good, the entry in `/etc/fstab` should tell the system all it needs to mount the disk.
15.  If using `vm.conf`, update to include the additional disk in the vm settings.

Using disk partition UUIDs, we can make sure if we accidentally or purposely change the order we attach the virtual block devices, the system can still find the right partitions for booting, root, and our new data partition. The joy of GPT and UUIDs!

### 🐳 Docker on a Separate Disk

If you use the data disk idea above and plan on [using Docker on Alpine](https://medium.com/@dave_voutila/docker-on-openbsd-6-1-current-c620513b8110), it makes a perfect way to isolate the storage used by the containers and their data so you don’t blow out disk space for your root partition.

First [install Docker](https://wiki.alpinelinux.org/wiki/Docker), then modify the `/etc/conf.d/docker` config file, adding a custom `DOCKER_OPTS` setting:

\# any other random options you want to pass to docker
DOCKER\_OPTS="--data-root /data/docker"

Where `/data/docker` is a location on my mounted data disk.

Restart Docker with `rc-service docker restart`. You should see the hierarchy of the Docker puke 🤢 in your new directory.

Last step is never tell anyone on the internet you run Docker on virtualized hardware because you’ll be told you just killed about 1000 kittens. 🤷‍

Hopefully the above tips help someone someday. If they do, do us all a favor and [kick a few bucks to OpenBSD development](https://www.openbsd.org/donations.html).

Future tips might include:

*   Network [trunking](https://man.openbsd.org/trunk) in conjunction with the VM
*   Backup/restore
