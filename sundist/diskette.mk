#
# @(#)diskette.mk 1.1 92/07/30 Copyright 1988, 1989 Sun Microsystems, Inc.
#
#
# Assumptions:
#
#	There are two sets of diskettes: the "boot" set and the
#	"suninstall" set (aka Application SunOS???).
#
#	The "boot" set consists of:
#	1 filesystem diskette with /boot.sun4c and /vmunix (munix) on it.
#	1 dd(1)'d filesystem image diskette with munixfs on it
#	3 diskettes with the COMPRESSED miniroot on them
#
#	The "suninstall" set consists of:
#	~30 diskettes, with the various catagories dd(1)'d onto them.
#	Each catagory is a COMPRESSED tar file, generated by the
#	main sundist Makefile.
#	they are numbered starting at 1, corresponding to the
#	root filesystem on the suninstall tape.  The catagories
#	are packed together, saving space - some catagories
#	span multiple diskettes, others only part.
#
#	sizeing is done by the sundist Makefile,
#	so all this has to do is grab the tar images from $(TARFILES)/$(ARCH).Z
#	The compression is also handled in the sundist/Makefile.
#
#	Putting the files onto diskettes is done by a shell script generated
#	by the install_set rule.  If (scratch that - WHEN) the system panics,
#	hangs, etc. - you can edit that left over command file to delete
#	the previously done portions and restart the undone portion
#	to finish making diskettes.
#	
# CONFIGURABLE THINGS - that might change
# this is where the temp compressed tar image files go
# TARFILES is now passed from Makefile
# ARCH passed in from sun4c_diskette from mkdk_input from Makefile
# PROTO passed in from sun4c_diskette from mkdk_input from Makefile
XDRTOC=$(ARCH)_diskette.xdr
KERNEL=$(PROTO)/usr/kvm/stand/munix

#
# STATIC THINGS - change these only with great forethought
#
# ...CDEV is raw device, ...BDEV is block (for mounts) of all but last cyl
#
BOOTCDEV=/dev/rfd0c
BOOTBDEV=/dev/fd0c
FLOPPYCDEV=/dev/rfd0a
FLOPPYBDEV=/dev/fd0a
# use partition-b as the single cylinder device for copyright, xdrtoc, vollabel
CYL1DEV=/dev/rfd0b
# sector offset to XDRTOC on CYL1DEV
XDRTOCOFF=4
# number of sectors possibly used for xdrtoc
XDRTOCSIZE=31
# sector offset of volume label on CYL1DEV (is last sector in partition)
# VOLLBLOFF=35 NOTUSED: assume XDRTOCOFF+XDRTOCSIZE = 35

FLOPPYFS=/mnt
FLOPPYBSIZE=18
# for dd'ing partition "c"
DDBS_C=36b
DDCNT_C=80
# sectors on 79 trks: 2844, on 80 trks: 2880
SECTORS=2844
SPT=18
TRACKS=158
NBPI=1536
# for data size of miniroot
MINISZ=1472000
# number of blocks (79*18*2) + ((18*2)-(4+1)) = 80*18*2 - 5 = 2875
MINICNT=2875

INSTALLBOOT=$(PROTO)/usr/mdec/installboot
BOOTBLKS=$(PROTO)/usr/mdec/rawboot
#BOOTBLKS=/usr/src/sys/boot/sun4c/bootopen
BOOTPROG=$(PROTO)/usr/stand/boot.${ARCH}

FILESYSTEMS=root usr

COPYRIGHT=./Copyright
COPYRIGHT.TMP=./Copyright.tmp
PARTNUM=./part_num_diskette_sun4c_abcd

#
# "make -f diskette.mk PROTO=/proto ARCH=`arch -k` dist" will make the diskettes
# if the munixfs, miniroot and tarfiles are already done
#
dist: bootfloppy munixfs miniroot install_set

# this actually make the diskettes that SunOS comes on
install_set:
	@ echo;echo "Copying the Application SunOS clusters from ${TARFILES}/${ARCH}.Z to diskette ..."
	./bin/xdrtoc ${XDRTOC} | \
		awk -f diskette.awk tarfiles=${TARFILES}/${ARCH}.Z - > install_set.cmds
	sh -x install_set.cmds
	rm install_set.cmds
	
# rule to start each diskette in install set, VOL passed in from command script
# NOTE: dd of=FLOPPY munges FLOPPY every time!
newdisk:
	eject ${FLOPPYCDEV}
	@ echo -n "Insert diskette ${VOL}, hit return when ready. "; read answer
	fdformat -f
	rm -f FLOPPY
	cat $(COPYRIGHT) /dev/zero | dd bs=1b count=$(XDRTOCOFF) conv=sync > FLOPPY
	cat $(XDRTOC) /dev/zero | dd bs=1b count=$(XDRTOCSIZE) conv=sync >> FLOPPY 
	echo "volume=${VOL} arch=${ARCH}" | dd bs=1b count=1 conv=sync >> FLOPPY 
	dd if=FLOPPY of=$(CYL1DEV) bs=36b count=1


$(COPYRIGHT.TMP): $(PARTNUM)
	cat $(PARTNUM) $(COPYRIGHT) > $@
#
# make a bootable diskette, with munix and /boot.sun4c on it
# we use mkfs vs. newfs because we want to put our own boot on it
#
# here's a groady rule if ever there was: turn a generic MUNIX kernel into`
# one that knows what to use for root and swap - 
# it still ask to how to load ramdisk tho'
#
# XXX move to getmunix.sh with MINIMEDIATYPE
munix.diskette.${ARCH}: ${KERNEL}
	@ echo "snarfing memory unix kernel ..."
	cp ${KERNEL} ./munix.diskette.${ARCH}
	@ echo "making rootfs \"4.2\" + \"rd0a\"; swapfile \"spec\" + \"ns0b\""
	( echo "rootfs?W '4.2'" ; \
	  echo "rootfs+10?W 'rd0a'" ; \
	  echo "swapfile?W 'spec'" ; \
	  echo "swapfile+10?W 'ns0b'" ; \
	  echo "loadramdiskfrom?W 'fd0c'" ; \
	  echo '$$q'; ) | adb -w munix.diskette.${ARCH}

bootfloppy: munix.diskette.${ARCH} $(COPYRIGHT.TMP)
	@ echo;echo "Constructing bootable diskette ..."
	@ echo -n "Insert diskette A, hit return when ready. " ; read answer
	@ echo "formatting diskette with label ..."
	fdformat -f
	@ echo "Making file system on diskette ..."
	mkfs $(BOOTCDEV) $(SECTORS) $(SPT) 2 4096 512 32 0 5 8192 s 0 0
	@ echo "Mounting diskette ..." ;
	mount $(BOOTBDEV) $(FLOPPYFS)
	@ echo "Installing boot block and boot program ..."
# copy boot program onto diskette, run installboot to put bootblock prog
#  onto disk.
	cp -p $(BOOTPROG) $(FLOPPYFS)
# put on a copy of the copyright file
	cp -p $(COPYRIGHT.TMP) $(FLOPPYFS)
	sync ; sync ; sync ; sleep 10
	$(INSTALLBOOT) -hv $(FLOPPYFS)/boot.${ARCH} $(BOOTBLKS) $(BOOTCDEV)
	sleep 5
	@ echo "Installing memory unix kernel ..."
	cp ./munix.diskette.${ARCH} $(FLOPPYFS)/vmunix
	@ echo "Unmounting floppy ..."
	sync ; sync ; sleep 20
	umount $(FLOPPYFS)
	sleep 4
	eject $(BOOTCDEV)
#XXX	rm ./munix.diskette.${ARCH}


#
# NOTE: the munixfs for floppy is made the same way as for tape, with
# a little different config info and files - see Makefile / getmunixfs.sh
#
# munixfs.$(ARCH).diskette build in Makefile
#munixfs: munixfs.$(ARCH).diskette
munixfs:
	@ echo "Constructing munix diskette ..."
	@ echo -n "Insert diskette B, hit return when ready. " ; read answer
	fdformat -f $(BOOTCDEV)
	dd if=munixfs.$(ARCH).diskette of=$(BOOTCDEV) bs=${DDBS_C} count=${DDCNT_C}
	sleep 3
	eject $(BOOTCDEV)

#
# we use the same miniroot as for tape, except that instead of just dd(1)-ing
# it onto tape, we compress it and then use dd(1) to cut it up and put on
# multiple floppies
#
miniroot.$(ARCH).Z: miniroot.$(ARCH) 
	compress -c miniroot.$(ARCH) > miniroot.$(ARCH).Z

miniroot: miniroot.$(ARCH).Z $(COPYRIGHT.TMP)
	@ echo;echo "Copying the miniroot to diskette ..."
	@ echo -n "Insert diskette \"C\", hit return when ready."; read answer
	fdformat -f $(BOOTCDEV)
	rm -f FLOPPY
	cat $(COPYRIGHT.TMP) /dev/zero | dd bs=1b count=4 conv=sync > FLOPPY
	echo "C ${MINISZ}" | dd count=1 bs=1b conv=sync >> FLOPPY
	dd if=miniroot.$(ARCH).Z bs=1b count=${MINICNT} conv=sync >> FLOPPY
	dd if=FLOPPY of=$(BOOTCDEV) bs=36b count=80
	@ echo "done with diskette C";
	eject $(FLOPPYCDEV);
	@ echo
	@ echo -n "Insert diskette \"D\", hit return when ready."; read answer;
	fdformat -f $(BOOTCDEV)
	rm -f FLOPPY
	cat $(COPYRIGHT.TMP) /dev/zero | dd bs=1b count=4 conv=sync > FLOPPY
	echo "D ${MINISZ}" | dd count=1 bs=1b conv=sync >> FLOPPY
	dd if=miniroot.$(ARCH).Z bs=1b skip=${MINICNT} count=${MINICNT} conv=sync >> FLOPPY
	dd if=FLOPPY of=$(BOOTCDEV) bs=36b count=80
	@ echo "done with diskette D";
	eject $(FLOPPYCDEV);
	@ echo
	@ echo -n "Insert diskette \"E\", hit return when ready."; read answer;
	fdformat -f $(BOOTCDEV)
	rm -f FLOPPY
	cat $(COPYRIGHT.TMP) /dev/zero | dd bs=1b count=4 conv=sync > FLOPPY
	# check for overflow of last diskette
	ls -l miniroot.$(ARCH).Z > tmp$$$$ ; \
	read perms link own size junk < tmp$$$$ ; \
	rm -f tmp$$$$ ; \
	echo "perms is $$perms, size is $$size, fsize is ${MINISZ}" ; \
	size=`expr $$size - \( 2 \* ${MINISZ} \)` ; \
	if [ $$size -gt ${MINISZ} ]; then \
	echo "ERROR: MINIROOT TOO BIG! - fix the makefile diskette.mk"; \
	exit 1; \
	fi ; \
	echo "E $$size" | dd count=1 bs=1b conv=sync >> FLOPPY
	dd if=miniroot.$(ARCH).Z bs=1b skip=`expr 2 \* ${MINICNT}` count=${MINICNT} conv=sync >> FLOPPY
	dd if=FLOPPY of=$(BOOTCDEV) bs=36b count=80
	@ echo "done with diskette E"
	@ echo "Done with miniroot diskettes"
	eject $(FLOPPYCDEV)

clean:
	rm -rf $(COPYRIGHT.TMP)
	rm -f munixfs.$(ARCH).diskette 
	rm -f munix.diskette.$(ARCH)

