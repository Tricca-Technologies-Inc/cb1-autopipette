# Boot splash — decision tree

The CB1 image generation determines which splash mechanism physically exists.
Run ON THE BOARD:

    grep -i BOOTSPLASH /boot/config-$(uname -r)

## CONFIG_BOOTSPLASH=y  →  BTT blob world
The kernel carries the bootsplash patchset; the blob at
/usr/lib/firmware/bootsplash.armbian is the splash. Build a Tricca blob ON A
LINUX DESKTOP (the packer binary is x86-64):

    ./make-btt-bootsplash.sh path/to/tricca-logo.png
    scp bootsplash.armbian tricca@marie:/tmp/

then on the board:

    sudo cp /usr/lib/firmware/bootsplash.armbian /usr/lib/firmware/bootsplash.armbian.orig
    sudo mv /tmp/bootsplash.armbian /usr/lib/firmware/bootsplash.armbian
    sudo sed -i 's/^bootlogo=.*/bootlogo=true/' /boot/armbianEnv.txt
    sudo update-initramfs -u && sudo reboot

## CONFIG_BOOTSPLASH absent  →  plymouth-or-nothing world
The blob mechanism does not exist in this kernel; no packer output can ever
render. Test whether plymouth can draw on this board's DRM at all:

    sudo plymouthd && sudo plymouth --show-splash && sleep 5 && sudo plymouth quit

- Logo appears → plymouth works; bootstrap step 6 (bootlogo=true + theme
  watermark replacement) is the whole answer; remaining issues are initramfs
  timing (`sudo update-initramfs -u`, confirm cmdline shows
  `splash plymouth.ignore-serial-consoles` not `splash=verbose`).
- Screen unchanged → neither mechanism works on this image (the sunxi gap).
  Fallback: no splash daemon; silence the console for a clean black boot:
  set verbosity=1, bootlogo=false in /boot/armbianEnv.txt and add
  `extraargs=quiet loglevel=0 vt.global_cursor_default=0`. The kiosk taking
  over the screen is then the "splash".
